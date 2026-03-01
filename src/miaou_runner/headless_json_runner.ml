(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Headless JSON-over-stdio runner.  Activated when [MIAOU_DRIVER=headless].
    Reads newline-delimited JSON commands from stdin and writes JSON responses
    to stdout.  The app binary becomes a subprocess that an AI agent or CI
    script can drive without a real terminal. *)

[@@@warning "-32-34-37-69"]

module HD = Lib_miaou_internal.Headless_driver
module Tui_page = Miaou_core.Tui_page

(* ── ANSI strip ─────────────────────────────────────────────────────────── *)

(** Remove ANSI/VT escape sequences from [s], returning plain text. *)
let ansi_strip s =
  let buf = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '\x1b' then (
      incr i ;
      if !i < n && s.[!i] = '[' then (
        (* CSI sequence: ESC [ ... <final byte 0x40-0x7e> *)
        incr i ;
        while !i < n && (s.[!i] < '@' || s.[!i] > '~') do
          incr i
        done ;
        if !i < n then incr i (* consume final byte *))
      else if !i < n then incr i (* skip single char after ESC (Fe sequence) *))
    else (
      Buffer.add_char buf s.[!i] ;
      incr i)
  done ;
  Buffer.contents buf

(* ── Frame helpers ───────────────────────────────────────────────────────── *)

let current_frame () =
  let size = HD.get_size () in
  let text = ansi_strip (HD.Screen.get ()) in
  `Assoc
    [
      ("type", `String "frame");
      ("text", `String text);
      ("rows", `Int size.LTerm_geom.rows);
      ("cols", `Int size.LTerm_geom.cols);
    ]

let nav_response action =
  `Assoc [("type", `String "nav"); ("action", `String action)]

let error_response msg =
  `Assoc [("type", `String "error"); ("message", `String msg)]

let emit json =
  (print_string [@allow_forbidden "headless runner writes JSON to stdout"])
    (Yojson.Safe.to_string json) ;
  (print_char [@allow_forbidden "headless runner writes JSON to stdout"]) '\n' ;
  (flush [@allow_forbidden "headless runner flushes stdout"]) stdout

(* ── Command dispatch ────────────────────────────────────────────────────── *)

(** Process one parsed command.  Returns [true] to keep running, [false] to
    stop the loop. *)
let handle_cmd (cmd : (string * Yojson.Safe.t) list) : bool =
  let get_string key =
    match List.assoc_opt key cmd with Some (`String s) -> Some s | _ -> None
  in
  let get_int key =
    match List.assoc_opt key cmd with Some (`Int n) -> Some n | _ -> None
  in
  match get_string "cmd" with
  | None ->
      emit (error_response "Missing 'cmd' field") ;
      true
  | Some "render" ->
      emit (current_frame ()) ;
      true
  | Some "key" -> (
      match get_string "key" with
      | None ->
          emit (error_response "Missing 'key' field") ;
          true
      | Some k -> (
          let outcome = HD.Stateful.send_key k in
          (* Run a few idle ticks so timers/refresh settle *)
          let outcome =
            match outcome with
            | `Continue -> HD.Stateful.idle_wait ~iterations:3 ()
            | other -> other
          in
          match outcome with
          | `Quit ->
              emit (nav_response "quit") ;
              false
          | `Back ->
              emit (nav_response "back") ;
              false
          | `SwitchTo name ->
              emit (nav_response ("switch:" ^ name)) ;
              true
          | `Continue ->
              emit (current_frame ()) ;
              true))
  | Some "click" ->
      (* Click is not yet implemented in Stateful; just re-render *)
      ignore (get_int "row") ;
      ignore (get_int "col") ;
      emit (current_frame ()) ;
      true
  | Some "tick" -> (
      let n = Option.value ~default:1 (get_int "n") in
      let outcome = HD.Stateful.idle_wait ~iterations:n () in
      (match outcome with
      | `Quit -> emit (nav_response "quit")
      | `Back -> emit (nav_response "back")
      | `SwitchTo name -> emit (nav_response ("switch:" ^ name))
      | `Continue -> emit (current_frame ())) ;
      match outcome with `Quit | `Back -> false | _ -> true)
  | Some "resize" -> (
      match (get_int "rows", get_int "cols") with
      | Some rows, Some cols ->
          HD.set_size rows cols ;
          emit (current_frame ()) ;
          true
      | _ ->
          emit (error_response "Missing 'rows' or 'cols'") ;
          true)
  | Some "quit" ->
      emit (nav_response "quit") ;
      false
  | Some other ->
      emit (error_response (Printf.sprintf "Unknown command: %s" other)) ;
      true

(* ── Main entry point ────────────────────────────────────────────────────── *)

let run (page : (module Tui_page.PAGE_SIG)) =
  (* Redirect stderr to /dev/null unless verbose mode requested *)
  (match Sys.getenv_opt "MIAOU_HEADLESS_VERBOSE" with
  | None | Some "" -> (
      try
        let null_fd = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
        Unix.dup2 null_fd Unix.stderr ;
        Unix.close null_fd
      with _ -> ())
  | _ -> ()) ;
  (* Unpack and repack to give OCaml a concrete module with an abstract state
     type, avoiding first-class module type-path issues with Stateful.init. *)
  let module P = (val page : Tui_page.PAGE_SIG) in
  HD.Stateful.init (module P) ;
  let rec loop () =
    match input_line stdin with
    | exception End_of_file -> ()
    | line -> (
        let line = String.trim line in
        if line = "" then loop ()
        else
          match Yojson.Safe.from_string line with
          | exception Yojson.Json_error msg ->
              emit (error_response ("JSON parse error: " ^ msg)) ;
              loop ()
          | `Assoc pairs -> if handle_cmd pairs then loop ()
          | _ ->
              emit (error_response "Expected a JSON object") ;
              loop ())
  in
  loop () ;
  (* Exit cleanly — same pattern as Tui_driver_common which calls exit 0
     after its event loop to avoid blocking on pending Eio fibers. *)
  exit 0
