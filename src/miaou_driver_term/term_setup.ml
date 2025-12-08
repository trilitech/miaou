(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@coverage off]

(** Terminal setup and cleanup utilities *)

let enter_raw_mode fd orig =
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

let restore_mode fd orig =
  match orig with None -> () | Some o -> Unix.tcsetattr fd Unix.TCSANOW o

let disable_mouse_tracking () =
  try
    print_string
      "\027[?1000l\027[?1002l\027[?1003l\027[?1005l\027[?1006l\027[?1015l" ;
    Stdlib.flush stdout ;
    Unix.sleepf 0.01
  with _ -> ()

let cleanup fd orig =
  disable_mouse_tracking () ;
  try restore_mode fd orig with _ -> ()

let install_signal_handlers cleanup_fn =
  let set sigv =
    try
      Sys.set_signal
        sigv
        (Sys.Signal_handle
           (fun _sig ->
             (try cleanup_fn () with _ -> ()) ;
             exit 130))
    with _ -> ()
  in
  set Sys.sigint ;
  set Sys.sigterm ;
  (try set Sys.sighup with _ -> ()) ;
  try set Sys.sigquit with _ -> ()

let setup_resize_handler () =
  let resize_pending = Atomic.make false in
  (try
     let sigwinch = 28 in
     Sys.set_signal
       sigwinch
       (Sys.Signal_handle (fun _ -> Atomic.set resize_pending true))
   with _ -> ()) ;
  resize_pending
