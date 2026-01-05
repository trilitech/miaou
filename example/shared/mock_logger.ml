(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* File-based Logger implementation for examples and demos.
   Writes all log messages to a file to avoid corrupting the TUI display.
   Log file location can be configured via MIAOU_LOG_FILE env var,
   defaults to /tmp/miaou-demo.log *)

let log_channel : out_channel option ref = ref None

let enabled = ref true

let default_log_file = "/tmp/miaou-demo.log"

let get_log_file () =
  match Sys.getenv_opt "MIAOU_LOG_FILE" with
  | Some f -> f
  | None -> default_log_file

let ensure_channel () =
  match !log_channel with
  | Some ch -> Some ch
  | None -> (
      try
        let ch =
          open_out_gen
            [Open_append; Open_creat; Open_text]
            0o644
            (get_log_file ())
        in
        log_channel := Some ch ;
        Some ch
      with _ -> None)

let level_to_string = function
  | Miaou_interfaces.Logger_capability.Debug -> "DBG"
  | Info -> "INF"
  | Warning -> "WRN"
  | Error -> "ERR"

let logf lvl s =
  if !enabled then
    match ensure_channel () with
    | Some ch ->
        let timestamp = Unix.gettimeofday () in
        let tm = Unix.localtime timestamp in
        Printf.fprintf
          ch
          "[%04d-%02d-%02d %02d:%02d:%02d] %s: %s\n"
          (tm.Unix.tm_year + 1900)
          (tm.Unix.tm_mon + 1)
          tm.Unix.tm_mday
          tm.Unix.tm_hour
          tm.Unix.tm_min
          tm.Unix.tm_sec
          (level_to_string lvl)
          s ;
        flush ch
    | None -> ()

let set_enabled b = enabled := b

let set_logfile path_opt =
  (* Close existing channel if any *)
  (match !log_channel with
  | Some ch -> ( try close_out ch with _ -> ())
  | None -> ()) ;
  log_channel := None ;
  (* Open new file if specified *)
  match path_opt with
  | None -> Ok ()
  | Some path -> (
      try
        let ch = open_out_gen [Open_append; Open_creat; Open_text] 0o644 path in
        log_channel := Some ch ;
        Ok ()
      with exn -> Error (Printexc.to_string exn))

let register () =
  let module L = Miaou_interfaces.Logger_capability in
  L.set {L.logf; set_enabled; set_logfile}

(* Cleanup function to close log file on exit *)
let () =
  at_exit (fun () ->
      match !log_channel with
      | Some ch -> ( try close_out ch with _ -> ())
      | None -> ())
