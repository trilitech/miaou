(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let cleanup_done = ref false

let setup_and_cleanup () =
  let fd = Unix.descr_of_in_channel stdin in
  if not (try Unix.isatty fd with _ -> false) then
    failwith "interactive TUI requires a terminal" ;
  let orig = try Some (Unix.tcgetattr fd) with _ -> None in
  let enter_raw () =
    match orig with
    | None -> ()
    | Some o ->
        let raw =
          {
            o with
            Unix.c_icanon = false;
            Unix.c_echo = false;
            Unix.c_vmin = 1;
            Unix.c_vtime = 0;
          }
        in
        Unix.tcsetattr fd Unix.TCSANOW raw
  in
  let restore () =
    match orig with None -> () | Some o -> Unix.tcsetattr fd Unix.TCSANOW o
  in
  let cleanup () =
    if not !cleanup_done then (
      cleanup_done := true ;
      (* Disable xterm mouse tracking modes - do this first before terminal restore *)
      (try
         (* Disable all common mouse tracking modes *)
         print_string
           "\027[?1000l\027[?1002l\027[?1003l\027[?1005l\027[?1006l\027[?1015l" ;
         (* Also send a hard reset sequence as fallback *)
         print_string "\027[?1000l\027[?1006l" ;
         (* Force multiple flushes to ensure escape sequences go through *)
         Stdlib.flush stdout ;
         Stdlib.flush stderr ;
         (* Write directly to terminal to ensure it gets through *)
         ignore (Unix.write Unix.stdout (Bytes.of_string "\027[?1000l\027[?1006l") 0 18)
       with _ -> ()) ;
      (* Small delay to ensure escape sequences are processed *)
      (try Unix.sleepf 0.1 with _ -> ()) ;
      try restore () with _ -> ())
  in
  let install_signal_handlers () =
    let set sigv =
      try
        Sys.set_signal
          sigv
          (Sys.Signal_handle
             (fun _sig ->
               (try cleanup () with _ -> ()) ;
               exit 130))
      with _ -> ()
    in
    set Sys.sigint ;
    set Sys.sigterm ;
    (try set Sys.sighup with _ -> ()) ;
    try set Sys.sigquit with _ -> ()
  in
  (fd, enter_raw, cleanup, install_signal_handlers)
