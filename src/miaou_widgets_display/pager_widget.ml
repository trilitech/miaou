(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
[@@@warning "-32-34-37-69"]

(* Removed Unix dependency to keep this module lightweight; use Sys.time for timestamps. *)

(* local Widgets functions are referenced qualified; no open needed here *)

let debug_enabled = lazy (Sys.getenv_opt "MIAOU_DEBUG" = Some "1")

let debug fmt =
  Printf.ksprintf
    (fun s -> if Lazy.force debug_enabled then Printf.eprintf "%s%!" s)
    fmt

(* ANSI color palette for UI elements *)
module Colors = struct
  (* JSON syntax highlighting *)
  let json_number = 136 (* orange/brown *)

  let json_bool_null = 34 (* blue *)

  let json_key = 33 (* yellow *)

  let json_string = 178 (* pale yellow *)

  (* Status indicators *)
  let status_dim = 242 (* gray *)
end

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
  mutable last_win : int;
      (* last render window height to keep follow anchored *)
  mutable search : string option;
  mutable is_regex : bool;
  mutable input_mode : [`None | `Search_edit | `Lookup];
  mutable input_buffer : string;
  mutable input_pos : int;
  mutable notify_render : (unit -> unit) option;
      (* optional callback to request a UI render when content changes *)
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

(* Calculate maximum offset given total lines and window size *)
let max_offset_for ~total ~win = max 0 (total - win)

let build_body_buffer ~wrap ~cols lines =
  let buf =
    let est =
      List.fold_left (fun acc l -> acc + String.length l + 1) 0 lines + 16
    in
    Buffer.create est
  in
  let first = ref true in
  let add_line line =
    if !first then first := false else Buffer.add_char buf '\n' ;
    if String.contains line '\027' then
      debug
        "[PAGER] Adding line with ANSI codes (len=%d)\n"
        (String.length line) ;
    Buffer.add_string buf line
  in
  if wrap then
    let width = max 10 (cols - 2) in
    List.iter
      (fun line ->
        if String.contains line '\027' then
          debug "[PAGER] Before wrap: line has ANSI codes\n" ;
        let wrapped = Widgets.wrap_text ~width line in
        if String.contains line '\027' then
          debug
            "[PAGER] After wrap: %d lines, checking for ANSI...\n"
            (List.length wrapped) ;
        List.iter add_line wrapped)
      lines
  else List.iter add_line lines ;
  Buffer.contents buf

let open_lines ?title ?notify_render lines =
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
    last_win = default_win;
    search = None;
    is_regex = false;
    input_mode = `None;
    input_buffer = "";
    input_pos = 0;
    notify_render;
  }

let open_text ?title ?notify_render s =
  open_lines ?title ?notify_render (split_lines s)

let set_offset t o = {t with offset = o}

let set_search t s = {t with search = s; offset = 0}

(* Append APIs ----------------------------------------------------------- *)
let append_lines_follow t =
  if t.follow then t.offset <- max 0 (List.length t.lines - t.last_win)

let append_lines t ls =
  t.lines <- t.lines @ ls ;
  append_lines_follow t

let append_text t s =
  let more = split_lines s in
  append_lines t more

(* --- Batched append APIs: push into pending buffer and let render() flush at a limited rate --- *)
let append_lines_batched t ls =
  (* accumulate into pending_rev (reversed) for O(1) appends; set dirty flag
		 and notify renderer if present so UI can wake up quickly. *)
  t.pending_rev <- List.rev_append ls t.pending_rev ;
  t.pending_dirty <- true ;
  (* Invalidate cached rendered body: content changed (or will) *)
  t.cached_body <- None ;
  match t.notify_render with
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
          t.lines <- t.lines @ to_add ;
          append_lines_follow t) ;
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
        t.lines <- t.lines @ to_add ;
        append_lines_follow t) ;
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
  let color_num s = Widgets.fg Colors.json_number s in
  let color_bool_null s = Widgets.fg Colors.json_bool_null s in
  let color_key s = Widgets.fg Colors.json_key s in
  let color_string s = Widgets.fg Colors.json_string s in

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
  let max_off = max_offset_for ~total ~win in
  if t.follow then (max_off, total)
  else
    let start = clamp 0 max_off t.offset in
    let stop = min total (start + win) in
    (start, stop)

let render ?cols ?(wrap = true) ~win (t : t) ~focus : string =
  (* flush buffered lines opportunistically on render *)
  flush_pending_if_needed t ;
  t.last_win <- win ;
  debug
    "[PAGER] render called: search=%s input_mode=%s\n"
    (match t.search with Some s -> "Some('" ^ s ^ "')" | None -> "None")
    (match t.input_mode with
    | `None -> "None"
    | `Search_edit -> "Search_edit"
    | `Lookup -> "Lookup") ;
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
    debug
      "[PAGER] render: t.search=%s, is_regex=%b, slice_len=%d\n"
      (match t.search with Some s -> "Some('" ^ s ^ "')" | None -> "None")
      t.is_regex
      (List.length slice) ;
    match t.search with
    | None -> slice
    | Some q ->
        debug
          "[PAGER] Highlighting search query: '%s' in %d lines\n"
          q
          (List.length slice) ;
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
    Widgets.dim (Widgets.fg Colors.status_dim (pos ^ mode))
  in
  let cols = match cols with Some c -> c | None -> 80 in
  (* Show search input prompt when in search edit mode *)
  let search_prompt =
    match t.input_mode with
    | `Search_edit ->
        let prompt = "Search: " in
        (* Use ASCII fallback for cursor to ensure compatibility across terminals *)
        let cursor =
          if Lazy.force Widgets.use_ascii_borders then "|" else "▌"
        in
        (* Insert cursor at input position *)
        let before =
          String.sub
            t.input_buffer
            0
            (min t.input_pos (String.length t.input_buffer))
        in
        let after =
          if t.input_pos < String.length t.input_buffer then
            String.sub
              t.input_buffer
              t.input_pos
              (String.length t.input_buffer - t.input_pos)
          else ""
        in
        Some (Widgets.bg 236 (prompt ^ before ^ cursor ^ after))
    | _ -> None
  in
  let header =
    match search_prompt with Some sp -> [status; sp] | None -> [status]
  in
  let footer =
    let hints =
      match t.input_mode with
      | `Search_edit -> [("Enter", "search"); ("Esc", "cancel")]
      | _ ->
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
  Widgets.render_frame ~title ~header ~body ~footer ~cols ()

(* Kept for compatibility; callers that can compute terminal cols should prefer
   calling [render ~win ~cols] directly to fully utilize available width. *)
let render_with_size ~size t ~focus = render ~win:(win_of_size size) t ~focus

(* Key handling --------------------------------------------------------- *)

(* Helper to insert a character at the current cursor position in search input *)
let insert_char t c =
  let before = String.sub t.input_buffer 0 t.input_pos in
  let after =
    if t.input_pos < String.length t.input_buffer then
      String.sub
        t.input_buffer
        t.input_pos
        (String.length t.input_buffer - t.input_pos)
    else ""
  in
  t.input_buffer <- before ^ c ^ after ;
  t.input_pos <- t.input_pos + String.length c ;
  t

(* Check if a key is a printable character for search input *)
let is_printable_char key =
  String.length key = 1
  &&
  let c = Char.code key.[0] in
  (c >= 32 && c < 127) || c >= 128

(* Handle search-mode input keys; returns Some result if handled *)
let handle_search_input t ~key =
  match key with
  | "Enter" | "Return" ->
      debug "[PAGER] Enter pressed in search mode, query='%s'\n" t.input_buffer ;
      let q = String.trim t.input_buffer in
      if q = "" then (
        t.search <- None ;
        t.input_mode <- `None)
      else (
        t.search <- Some q ;
        t.input_mode <- `None) ;
      debug
        "[PAGER] Search set to: %s\n"
        (match t.search with Some s -> "'" ^ s ^ "'" | None -> "None") ;
      Some (t, true)
  | "Esc" | "Escape" ->
      t.input_mode <- `None ;
      Some (t, true)
  | ("Backspace" | "BackSpace") when t.input_pos > 0 ->
      let before = String.sub t.input_buffer 0 (t.input_pos - 1) in
      let after_start = t.input_pos in
      let after_len = String.length t.input_buffer - after_start in
      let after =
        if after_len > 0 then String.sub t.input_buffer after_start after_len
        else ""
      in
      t.input_buffer <- before ^ after ;
      t.input_pos <- t.input_pos - 1 ;
      Some (t, true)
  | "Backspace" | "BackSpace" ->
      Some (t, true) (* consume but do nothing at position 0 *)
  | "Left" when t.input_pos > 0 ->
      t.input_pos <- t.input_pos - 1 ;
      Some (t, true)
  | "Left" -> Some (t, true)
  | "Right" when t.input_pos < String.length t.input_buffer ->
      t.input_pos <- t.input_pos + 1 ;
      Some (t, true)
  | "Right" -> Some (t, true)
  | _ when is_printable_char key -> Some (insert_char t key, true)
  | _ -> None (* not handled in search mode *)

(* Handle navigation keys; returns (t, consumed) *)
let handle_nav_key t ~key ~win ~total ~page =
  let max_offset = max_offset_for ~total ~win in
  (* Helper: if we land at max_offset (bottom), auto-resume follow if it was on *)
  let with_auto_follow t new_offset =
    let clamped_offset = clamp 0 max_offset new_offset in
    (* Re-enable follow if: (1) trying to scroll past bottom, OR (2) exactly at bottom *)
    let at_or_past_bottom = new_offset >= max_offset in
    (* Auto-resume follow when user scrolls to/past bottom and streaming is active *)
    t.offset <- clamped_offset ;
    t.follow <- at_or_past_bottom && t.streaming ;
    t
  in
  match key with
  | "Up" -> Some (with_auto_follow t (t.offset - 1), true)
  | "Down" -> Some (with_auto_follow t (t.offset + 1), true)
  | "Page_up" -> Some (with_auto_follow t (t.offset - page), true)
  | "Page_down" -> Some (with_auto_follow t (t.offset + page), true)
  | "g" ->
      t.offset <- 0 ;
      t.follow <- false ;
      Some (t, true)
  | "G" ->
      t.offset <- max_offset ;
      t.follow <- t.streaming ;
      Some (t, true)
  | "f" | "F" ->
      t.follow <- not t.follow ;
      if t.follow then t.offset <- max_offset ;
      Some (t, true)
  | "/" ->
      t.input_mode <- `Search_edit ;
      t.input_buffer <- "" ;
      t.input_pos <- 0 ;
      Some (t, true)
  | "n" -> (
      let q = match t.search with Some s -> s | None -> "" in
      match
        find_next
          t.lines
          ~start:(min (total - 1) (t.offset + 1))
          ~q
          ~is_regex:t.is_regex
      with
      | None -> Some (t, true)
      | Some i ->
          t.offset <- clamp 0 max_offset i ;
          Some (t, true))
  | "p" -> (
      let q = match t.search with Some s -> s | None -> "" in
      match
        find_prev t.lines ~start:(max 0 (t.offset - 1)) ~q ~is_regex:t.is_regex
      with
      | None -> Some (t, true)
      | Some i ->
          t.offset <- clamp 0 max_offset i ;
          Some (t, true))
  | _ -> None

let handle_key ?win (t : t) ~key : t * bool =
  debug
    "[PAGER] handle_key: key='%s' input_mode=%s\n"
    key
    (match t.input_mode with
    | `Search_edit -> "Search_edit"
    | `Lookup -> "Lookup"
    | `None -> "None") ;
  let win = match win with Some w -> w | None -> default_win in
  let total = List.length t.lines in
  let page = max 1 (win - 1) in
  match t.input_mode with
  | `Search_edit -> (
      match handle_search_input t ~key with
      | Some result -> result
      | None -> (t, false))
  | `None | `Lookup -> (
      match handle_nav_key t ~key ~win ~total ~page with
      | Some result -> result
      | None -> (t, false))
