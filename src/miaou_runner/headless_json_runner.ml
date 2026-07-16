(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Headless JSON-over-stdio runner.  Activated when [MIAOU_DRIVER=headless].
    Reads newline-delimited JSON commands from stdin and writes JSON responses
    to stdout.  The app binary becomes a subprocess that an AI agent or CI
    script can drive without a real terminal.

    This module is a thin stdio transport shim: command dispatch itself lives
    in the transport-agnostic {!Miaou_protocol.Protocol_core}, shared with the
    [miaou-mcp] server. *)

module Tui_page = Miaou_core.Tui_page
module Protocol_core = Miaou_protocol.Protocol_core

let emit json =
  (print_string [@allow_forbidden "headless runner writes JSON to stdout"])
    (Yojson.Safe.to_string json) ;
  (print_char [@allow_forbidden "headless runner writes JSON to stdout"]) '\n' ;
  (flush [@allow_forbidden "headless runner flushes stdout"]) stdout

let error_response msg =
  `Assoc [("type", `String "error"); ("message", `String msg)]

(* [--no-record] (FR-061): checked via argv since this module is itself the
   process entry point when [MIAOU_DRIVER=headless]. *)
let no_record_flag () =
  Array.exists (fun a -> a = "--no-record") Sys.argv
  ||
  match Sys.getenv_opt "MIAOU_NO_RECORD" with
  | Some v ->
      let v = String.lowercase_ascii (String.trim v) in
      not (v = "" || v = "0" || v = "false" || v = "off" || v = "no")
  | None -> false

(* ── Main entry point ────────────────────────────────────────────────────── *)

let run ?on_frame (page : (module Tui_page.PAGE_SIG)) =
  Protocol_core.set_on_frame on_frame ;
  (* Redirect stderr to /dev/null unless verbose mode requested *)
  (match Sys.getenv_opt "MIAOU_HEADLESS_VERBOSE" with
  | None | Some "" -> (
      try
        let null_fd = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
        Unix.dup2 null_fd Unix.stderr ;
        Unix.close null_fd
      with _ -> ())
  | _ -> ()) ;
  Protocol_core.init_session ~no_record:(no_record_flag ()) page ;
  let rec loop () =
    (* Use run_in_systhread so the blocking input_line runs in a system
       thread.  This keeps the eio event loop active, allowing background
       fibers (e.g. LLM subprocess I/O) to make progress between commands. *)
    match
      Eio_unix.run_in_systhread ~label:"headless-stdin" (fun () ->
          input_line stdin)
    with
    | exception End_of_file -> ()
    | line -> (
        let line = String.trim line in
        if line = "" then loop ()
        else
          match Yojson.Safe.from_string line with
          | exception Yojson.Json_error msg ->
              emit (error_response ("JSON parse error: " ^ msg)) ;
              loop ()
          | `Assoc pairs ->
              let resp, outcome = Protocol_core.handle_cmd pairs in
              emit resp ;
              if outcome = `Continue then loop ()
          | _ ->
              emit (error_response "Expected a JSON object") ;
              loop ())
  in
  (* When a viewer is attached, fork a daemon fiber that periodically
     re-renders the screen and broadcasts changes.  Eio's cooperative
     scheduling ensures the refresh fiber only runs while the main loop
     is blocked on stdin (run_in_systhread), so there is no concurrent
     access to the headless driver state. *)
  (match on_frame with
  | Some on_frame ->
      Eio.Switch.run @@ fun sw ->
      Eio.Fiber.fork_daemon ~sw (fun () ->
          let module HD = Lib_miaou_internal.Headless_driver in
          let prev = ref "" in
          while true do
            Eio_unix.sleep 0.2 ;
            (* Read the cached screen content written by the command handler.
               Do NOT call idle_wait here — that would race with the command
               handler's own idle_wait (both mutate the shared page-state ref
               and double-tick clocks/timers whenever the command handler
               yields).  The cache is always fresh: every tick/key/render
               command updates it before returning a response. *)
            let size = HD.get_size () in
            let raw = HD.Screen.get () in
            if raw <> !prev then (
              prev := raw ;
              on_frame ~rows:size.LTerm_geom.rows ~cols:size.LTerm_geom.cols raw)
          done ;
          `Stop_daemon) ;
      loop ()
  | None -> loop ()) ;
  (* Exit cleanly — same pattern as Tui_driver_common which calls exit 0
     after its event loop to avoid blocking on pending Eio fibers. *)
  exit 0
