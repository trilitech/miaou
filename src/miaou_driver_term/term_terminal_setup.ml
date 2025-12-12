(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let cleanup_done = ref false
(* DO NOT use a flag for mouse cleanup - it needs to run every time cleanup is called,
   because mouse tracking might be re-enabled between cleanup calls. The escape sequences
   to disable mouse tracking are idempotent (safe to send multiple times). *)

let setup_and_cleanup () =
  let fd = Unix.descr_of_in_channel stdin in
  if not (try Unix.isatty fd with _ -> false) then
    failwith "interactive TUI requires a terminal" ;
  let orig = try Some (Unix.tcgetattr fd) with _ -> None in
  (* Open /dev/tty directly for writing escape sequences - this is more reliable than
     stdout during cleanup/signal handling because stdout might be redirected *)
  let tty_out_fd =
    try Unix.openfile "/dev/tty" [Unix.O_WRONLY] 0
    with _ -> Unix.descr_of_out_channel stdout
  in
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
  let disable_mouse () =
    (* ALWAYS run mouse cleanup - no flag check!
       The flag was causing the bug where cleanup during navigation would prevent
       cleanup during Ctrl+C from actually disabling mouse tracking. *)
    try
      (* CRITICAL: Mouse tracking must be disabled AFTER terminal is restored to canonical mode.

         We use multiple methods to ensure the escape sequences are delivered:
         1. Write to /dev/tty (avoids stdout redirection issues)
         2. Also write to stdout/stderr as fallback
         3. Repeat writes to handle dropped packets
         4. Use tcdrain to wait for transmission
         5. Sleep to give terminal time to process

         If this fails, the terminal will be left in mouse mode, causing
         "unbound keyseq: mouse" errors when scrolling. *)
      let disable_seq =
        "\027[?1006l\027[?1015l\027[?1005l\027[?1003l\027[?1002l\027[?1000l"
      in
      (* Method 1: Write to /dev/tty *)
      (try
         for _i = 1 to 2 do
           let _ =
             Unix.write
               tty_out_fd
               (Bytes.of_string disable_seq)
               0
               (String.length disable_seq)
           in
           ()
         done ;
         Unix.tcdrain tty_out_fd
       with _ -> ()) ;
      (* Method 2: Write to stdout using same mechanism as enable *)
      (try
         print_string disable_seq ;
         Stdlib.flush stdout
       with _ -> ()) ;
      (* Method 3: Write to stderr as last resort *)
      (try Printf.eprintf "%s%!" disable_seq with _ -> ()) ;
      (* Give terminal time to process all escape sequences *)
      Unix.sleepf 0.2
    with _ -> ()
  in
  let cleanup () =
    (* Terminal restore FIRST - the terminal may need to be in canonical mode
       to properly process escape sequences during cleanup *)
    if not !cleanup_done then (
      cleanup_done := true ;
      try restore () with _ -> ()) ;
    (* THEN disable mouse tracking - terminal is now in normal mode *)
    disable_mouse ()
  in
  let signal_exit_flag = Atomic.make false in
  let install_signal_handlers () =
    let set sigv =
      try
        Sys.set_signal
          sigv
          (Sys.Signal_handle
             (fun _sig ->
               (* Run cleanup synchronously in signal handler.

                  The cleanup() function is now idempotent (safe to call multiple times)
                  because we removed the mouse_cleanup_done flag. This means cleanup can
                  run here in the signal handler AND also via at_exit without issues.

                  We need to run it here because the main loop might be stuck in blocking
                  read and won't check the exit flag quickly enough. *)
               (try cleanup () with _ -> ()) ;
               (* Set flag so main loop can exit gracefully if it's still running *)
               Atomic.set signal_exit_flag true))
      with _ -> ()
    in
    set Sys.sigint ;
    set Sys.sigterm ;
    (try set Sys.sighup with _ -> ()) ;
    try set Sys.sigquit with _ -> ()
  in
  (fd, enter_raw, cleanup, install_signal_handlers, signal_exit_flag)
