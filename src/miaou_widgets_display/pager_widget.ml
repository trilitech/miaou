(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
[@@@warning "-32-34-37-69"]

(* Removed Unix dependency to keep this module lightweight; use Sys.time for timestamps. *)

(* local Widgets functions are referenced qualified; no open needed here *)

type t = {
  title : string option;
  mutable lines : string list; (* made mutable to support incremental appends *)
  mutable offset : int;
  mutable follow : bool;
  mutable streaming : bool;
      (* whether this pager is currently showing a streaming request *)
  mutable spinner_pos : int; (* spinner animation position updated on render *)
  mutable pending_lines : string list;
      (* buffered appended lines waiting to be flushed into `lines` *)
  mutable pending_rev : string list;
      (* pending lines stored in reversed order for O(1) appends *)
  mutable pending_dirty : bool; (* whether there are pending lines to flush *)
  mutable cached_body : string option;
      (* cached rendered body to avoid recomputing for spinner-only refreshes *)
  mutable last_flush : float; (* timestamp of last flush, seconds since epoch *)
  mutable flush_interval_ms : int;
      (* minimum interval between flushes in milliseconds *)
  mutable search : string option;
  mutable is_regex : bool;
  mutable input_mode : [`None | `Search_edit | `Lookup];
  mutable input_buffer : string;
  mutable input_pos : int;
}

let default_win = 20

(* Avoid referencing LTerm types here to keep this lib independent. *)
let win_of_rows rows = max 1 (rows - 1)

(* Keep a shim so call sites that pass a Lambda-Term size keep compiling without
	forcing a lambda-term dependency here. We ignore the actual value and use a
	conservative default window size. *)
let win_of_size _size = default_win

let split_lines s = String.split_on_char '\n' s

let clamp lo hi x = max lo (min hi x)

let build_body_buffer ~wrap ~cols lines =
  let buf =
    let est =
      List.fold_left (fun acc l -> acc + String.length l + 1) 0 lines
      + 16
    in
    Buffer.create est
  in
  let first = ref true in
  let add_line line =
    if !first then first := false else Buffer.add_char buf '\n' ;
    Buffer.add_string buf line
  in
  if wrap then
    let width = max 10 (cols - 2) in
    List.iter
      (fun line -> Widgets.wrap_text ~width line |> List.iter add_line)
      lines
  else List.iter add_line lines ;
  Buffer.contents buf

let open_lines ?title lines =
  {
    title;
    lines;
    offset = 0;
    follow = false;
    streaming = false;
    spinner_pos = 0;
    pending_lines = [];
    pending_rev = [];
    pending_dirty = false;
    cached_body = None;
    last_flush = 0.;
    flush_interval_ms = 200;
    (* default: 200ms -> conservative flush rate *)
    search = None;
    is_regex = false;
    input_mode = `None;
    input_buffer = "";
    input_pos = 0;
  }

let open_text ?title s = open_lines ?title (split_lines s)

let set_offset t o = {t with offset = o}

let set_search t s = {t with search = s; offset = 0}

(* Append APIs ----------------------------------------------------------- *)
let append_lines t ls = t.lines <- t.lines @ ls

let append_text t s =
  let more = split_lines s in
  append_lines t more

(* --- Batched append APIs: push into pending buffer and let render() flush at a limited rate --- *)
(* Notification hook: optional global callback set by UI driver so pager can request a render. *)
let notify_render_val : (unit -> unit) option ref = ref None

let set_notify_render f = notify_render_val := f

let append_lines_batched t ls =
  (* accumulate into pending_rev (reversed) for O(1) appends; set dirty flag
		 and notify renderer if present so UI can wake up quickly. *)
  t.pending_rev <- List.rev_append ls t.pending_rev ;
  t.pending_dirty <- true ;
  (* Invalidate cached rendered body: content changed (or will) *)
  t.cached_body <- None ;
  match !notify_render_val with
  | Some f -> ( try f () with _ -> ())
  | None -> (
      (* No notifier registered: flush immediately so background appends
								are not indefinitely hidden when the driver doesn't provide a
								render hook (e.g., headless runs). This is a conservative
								fallback to avoid a frozen pager. *)
      (* Inline quick flush: merge pending_rev into visible lines preserving order *)
      try
        if t.pending_rev <> [] then (
          let to_add = List.rev t.pending_rev in
          t.pending_rev <- [] ;
          t.lines <- t.lines @ to_add) ;
        t.pending_dirty <- false ;
        (* Invalidate cached body after flush so next build recomputes it *)
        t.cached_body <- None ;
        t.last_flush <- Sys.time ()
      with _ -> ())

let append_text_batched t s =
  let more = split_lines s in
  append_lines_batched t more

(* end notify hook *)

(* Streaming UI helpers ------------------------------------------------- *)
let start_streaming t =
  t.streaming <- true ;
  t.spinner_pos <- 0

let flush_pending_if_needed ?(force = false) t =
  if not t.pending_dirty then ()
  else
    let now = Sys.time () in
    let elapsed_ms = int_of_float ((now -. t.last_flush) *. 1000.) in
    if force || elapsed_ms >= t.flush_interval_ms then (
      (* merge pending_rev into visible lines efficiently, preserving order *)
      if t.pending_rev <> [] then (
        let to_add = List.rev t.pending_rev in
        t.pending_rev <- [] ;
        t.lines <- t.lines @ to_add) ;
      t.pending_dirty <- false ;
      t.last_flush <- now)

let stop_streaming t =
  (* Ensure any buffered content is flushed when streaming stops so final view is complete *)
  flush_pending_if_needed ~force:true t ;
  t.streaming <- false ;
  t.spinner_pos <- 0

(* Simple incremental JSON pretty-printer (streaming-friendly).
	 Usage:
		 let st = json_streamer_create ()
		 let lines = json_streamer_feed st chunk1 in
		 append_lines pager lines
		 let lines2 = json_streamer_feed st chunk2 in ...
	 This is a heuristic pretty-printer: it inserts newlines/indentation and
	 maintains indentation and string/escape state across chunks. It returns
	 only complete lines (the last partial line is kept internal until
	 completed by a later chunk).
*)
type json_streamer = {
  mutable buf : Buffer.t; (* holds completed text ready to split into lines *)
  mutable partial : Buffer.t;
      (* holds last partial line without trailing newline *)
  mutable indent : int;
  mutable in_string : bool;
  mutable in_escape : bool;
  mutable token_buf : Buffer.t option;
      (* accumulates non-string tokens like numbers/idents *)
  mutable pending_string : Buffer.t option;
      (* holds a completed quoted string until we see if it's a key (followed by ':') *)
  mutable pending_ws : Buffer.t option;
      (* whitespace after a closed string while awaiting colon check *)
}

let json_streamer_create () =
  {
    buf = Buffer.create 1024;
    partial = Buffer.create 256;
    indent = 0;
    in_string = false;
    in_escape = false;
    token_buf = None;
    pending_string = None;
    pending_ws = None;
  }

let json_streamer_feed st chunk =
  let n = String.length chunk in
  (* Helper to emit ANSI colored text *)
  let color_num s = Widgets.fg 136 s in
  let color_bool_null s = Widgets.fg 34 s in
  let color_key s = Widgets.fg 33 s in
  let color_string s = Widgets.fg 178 s in

  let flush_token () =
    match st.token_buf with
    | None -> ()
    | Some b ->
        let tok = Buffer.contents b in
        st.token_buf <- None ;
        (* classify token *)
        let out =
          if tok = "true" || tok = "false" then color_bool_null tok
          else if tok = "null" then color_bool_null tok
          else
            (* try number *)
            try
              ignore (float_of_string tok) ;
              color_num tok
            with _ -> tok
        in
        Buffer.add_string st.partial out
  in

  let flush_pending_string_as_key () =
    match st.pending_string with
    | None -> ()
    | Some b ->
        let s = Buffer.contents b in
        st.pending_string <- None ;
        st.pending_ws <- None ;
        Buffer.add_string st.partial (color_key s)
  in

  let flush_pending_string_as_value () =
    match st.pending_string with
    | None -> ()
    | Some b ->
        let s = Buffer.contents b in
        st.pending_string <- None ;
        st.pending_ws <- None ;
        Buffer.add_string st.partial (color_string s)
  in

  let rec handle_char c =
    (* If we're holding a closed string waiting to see if it is followed by ':' *)
    match st.pending_string with
    | Some _ -> (
        (* If whitespace, accumulate and wait; if colon -> key; otherwise flush as value then continue processing this char *)
        match c with
        | ' ' | '\t' | '\r' | '\n' -> (
            match st.pending_ws with
            | Some w -> Buffer.add_char w c
            | None ->
                st.pending_ws <-
                  Some
                    (let b = Buffer.create 8 in
                     Buffer.add_char b c ;
                     b))
        | ':' ->
            (* flush as key, then emit ':' and a space *)
            flush_pending_string_as_key () ;
            flush_token () ;
            Buffer.add_char st.partial ':' ;
            Buffer.add_char st.partial ' '
        | _ ->
            (* Not a colon: flush as normal string then handle this char anew *)
            flush_pending_string_as_value () ;
            handle_char c)
    | None -> (
        if st.in_string then (
          (* accumulate full string in pending buffer so we can decide key/value after close *)
          match st.token_buf with
          | Some _ ->
              flush_token () ;
              st.token_buf <- None
          | None ->
              () ;
              (match st.pending_string with
              | Some _ -> ()
              | None ->
                  st.pending_string <-
                    Some
                      (let b = Buffer.create 64 in
                       Buffer.add_char b '"' ;
                       b)) ;
              (* add char into pending string *)
              (match st.pending_string with
              | Some b -> Buffer.add_char b c
              | None -> ()) ;
              (* handle escape/closing in the pending string *)
              if st.in_escape then st.in_escape <- false
              else if c = '\\' then st.in_escape <- true
              else if c = '"' then st.in_string <- false)
        else
          match c with
          | '{' | '[' ->
              flush_token () ;
              Buffer.add_char st.partial c ;
              st.indent <- st.indent + 1 ;
              Buffer.add_char st.partial '\n' ;
              Buffer.add_string st.partial (String.make (st.indent * 2) ' ')
          | '}' | ']' ->
              flush_token () ;
              st.indent <- max 0 (st.indent - 1) ;
              Buffer.add_char st.partial '\n' ;
              Buffer.add_string st.partial (String.make (st.indent * 2) ' ') ;
              Buffer.add_char st.partial c
          | ',' ->
              flush_token () ;
              Buffer.add_char st.partial c ;
              Buffer.add_char st.partial '\n' ;
              Buffer.add_string st.partial (String.make (st.indent * 2) ' ')
          | ':' ->
              flush_token () ;
              Buffer.add_char st.partial ':' ;
              Buffer.add_char st.partial ' '
          | '\n' ->
              flush_token () ;
              Buffer.add_char st.partial '\n'
          | ' ' | '\t' | '\r' ->
              (* whitespace outside tokens: output directly *)
              Buffer.add_char st.partial c
          | '"' ->
              (* start a string *)
              st.in_string <- true ;
              st.in_escape <- false ;
              st.pending_string <-
                Some
                  (let b = Buffer.create 64 in
                   Buffer.add_char b '"' ;
                   b)
          | _ ->
              (* token char: accumulate into token_buf *)
              let is_token_char ch =
                match ch with
                | '0' .. '9' | 'a' .. 'z' | 'A' .. 'Z' | '+' | '-' | '.' | '_'
                  ->
                    true
                | _ -> false
              in
              if is_token_char c then
                match st.token_buf with
                | Some b -> Buffer.add_char b c
                | None ->
                    st.token_buf <-
                      Some
                        (let b = Buffer.create 16 in
                         Buffer.add_char b c ;
                         b)
              else (
                flush_token () ;
                Buffer.add_char st.partial c))
  in

  for i = 0 to n - 1 do
    let c = chunk.[i] in
    handle_char c
  done ;
  (* Move completed lines from partial into buf, keeping trailing partial if no newline at end *)
  let content = Buffer.contents st.partial in
  let lines = String.split_on_char '\n' content in
  Buffer.clear st.partial ;
  (* If the chunk ended without a newline the last element is partial; keep it. *)
  let complete, last_partial =
    match List.rev lines with [] -> ([], "") | hd :: tl -> (List.rev tl, hd)
  in
  List.iter (fun l -> Buffer.add_string st.buf (l ^ "\n")) complete ;
  if last_partial <> "" then Buffer.add_string st.partial last_partial ;
  (* Extract complete lines to return *)
  let out = Buffer.contents st.buf in
  Buffer.clear st.buf ;
  if out = "" then []
  else
    String.split_on_char
      '\n'
      (if out.[String.length out - 1] = '\n' then
         String.sub out 0 (String.length out - 1)
       else out)

let find_next lines ~start ~q ~is_regex =
  if q = "" then None
  else
    let n = List.length lines in
    let rec aux i =
      if i >= n then None
      else
        let l = List.nth lines i in
        try
          let rex = if is_regex then Str.regexp q else Str.regexp_string q in
          ignore (Str.search_forward rex l 0) ;
          Some i
        with Not_found -> aux (i + 1)
    in
    aux start

let find_prev lines ~start ~q ~is_regex =
  if q = "" then None
  else
    let rec aux i =
      if i < 0 then None
      else
        let l = List.nth lines i in
        try
          let rex = if is_regex then Str.regexp q else Str.regexp_string q in
          ignore (Str.search_forward rex l 0) ;
          Some i
        with Not_found -> aux (i - 1)
    in
    aux start

(* Rendering ------------------------------------------------------------ *)

let visible_slice ~win t =
  let total = List.length t.lines in
  if t.follow then
    let start = max 0 (total - win) in
    (start, total)
  else
    let start = clamp 0 (max 0 (total - win)) t.offset in
    let stop = min total (start + win) in
    (start, stop)

let render ?cols ?(wrap = true) ~win (t : t) ~focus : string =
  (* flush buffered lines opportunistically on render *)
  flush_pending_if_needed t ;
  let start, stop = visible_slice ~win t in
  let body_lines =
    let slice =
      let rec take_range i acc = function
        | [] -> List.rev acc
        | x :: xs ->
            if i >= stop then List.rev acc
            else if i >= start then take_range (i + 1) (x :: acc) xs
            else take_range (i + 1) acc xs
      in
      take_range 0 [] t.lines
    in
    match t.search with
    | None -> slice
    | Some q ->
        List.map
          (Widgets.highlight_matches ~is_regex:t.is_regex ~query:(Some q))
          slice
  in
  let title = match t.title with Some s -> s | None -> "Pager" in
  let status =
    let pos =
      Printf.sprintf "%d-%d/%d" (start + 1) stop (List.length t.lines)
    in
    let mode = if t.follow then " [follow]" else "" in
    Widgets.dim (Widgets.fg 242 (pos ^ mode))
  in
  let cols = match cols with Some c -> c | None -> 80 in
  let footer =
    let hints =
      [
        ("Up/Down", "scroll");
        ("PgUp/PgDn", "page");
        ("/", "search");
        ("n/p", "next/prev");
        ("f", if t.follow then "follow off" else "follow on");
      ]
    in
    Widgets.footer_hints_wrapped_capped
      ~cols
      ~max_lines:(if focus then 2 else 1)
      hints
  in
  let body = build_body_buffer ~wrap ~cols body_lines in
  Widgets.render_frame ~title ~header:[status] ~body ~footer ~cols ()

(* Kept for compatibility; callers that can compute terminal cols should prefer
   calling [render ~win ~cols] directly to fully utilize available width. *)
let render_with_size ~size t ~focus = render ~win:(win_of_size size) t ~focus

(* Key handling --------------------------------------------------------- *)

let handle_key ?win (t : t) ~key : t * bool =
  let win = match win with Some w -> w | None -> default_win in
  let total = List.length t.lines in
  let page = max 1 (win - 1) in
  let consumed = true in
  match key with
  | "Up" ->
      ( {
          t with
          offset = clamp 0 (max 0 (total - win)) (t.offset - 1);
          follow = false;
        },
        consumed )
  | "Down" ->
      ( {
          t with
          offset = clamp 0 (max 0 (total - win)) (t.offset + 1);
          follow = false;
        },
        consumed )
  | "Page_up" ->
      ( {
          t with
          offset = clamp 0 (max 0 (total - win)) (t.offset - page);
          follow = false;
        },
        consumed )
  | "Page_down" ->
      ( {
          t with
          offset = clamp 0 (max 0 (total - win)) (t.offset + page);
          follow = false;
        },
        consumed )
  | "g" -> ({t with offset = 0; follow = false}, consumed)
  | "G" ->
      let last = max 0 (total - win) in
      ({t with offset = last; follow = false}, consumed)
  | "f" | "F" -> ({t with follow = not t.follow}, consumed)
  | "/" ->
      ( {t with input_mode = `Search_edit; input_buffer = ""; input_pos = 0},
        consumed )
  | "Enter" -> (
      match t.input_mode with
      | `Search_edit ->
          let q = String.trim t.input_buffer in
          let t' =
            if q = "" then {t with search = None; input_mode = `None}
            else {t with search = Some q; input_mode = `None}
          in
          (t', consumed)
      | _ -> (t, false))
  | "Esc" | "Escape" -> (
      match t.input_mode with
      | `Search_edit -> ({t with input_mode = `None}, consumed)
      | _ -> (t, false))
  | "n" -> (
      let q = match t.search with Some s -> s | None -> "" in
      match
        find_next
          t.lines
          ~start:(min (total - 1) (t.offset + 1))
          ~q
          ~is_regex:t.is_regex
      with
      | None -> (t, true)
      | Some i -> ({t with offset = clamp 0 (max 0 (total - win)) i}, true))
  | "p" -> (
      let q = match t.search with Some s -> s | None -> "" in
      match
        find_prev t.lines ~start:(max 0 (t.offset - 1)) ~q ~is_regex:t.is_regex
      with
      | None -> (t, true)
      | Some i -> ({t with offset = clamp 0 (max 0 (total - win)) i}, true))
  | _ -> (t, false)
