(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type t = {
  fd : Unix.file_descr;
  tty_out_fd : Unix.file_descr;
  orig_termios : Unix.terminal_io option;
  mutable cached_size : (int * int) option;
  mutable cleanup_done : bool;
  resize_pending : bool Atomic.t;
}

let setup () =
  let fd = Unix.descr_of_in_channel stdin in
  if not (try Unix.isatty fd with _ -> false) then
    failwith "interactive TUI requires a terminal" ;
  let orig_termios = try Some (Unix.tcgetattr fd) with _ -> None in
  let tty_out_fd =
    try Unix.openfile "/dev/tty" [Unix.O_WRONLY] 0
    with _ -> Unix.descr_of_out_channel stdout
  in
  {
    fd;
    tty_out_fd;
    orig_termios;
    cached_size = None;
    cleanup_done = false;
    resize_pending = Atomic.make false;
  }

let enter_raw t =
  match t.orig_termios with
  | None -> ()
  | Some orig ->
      let raw =
        {
          orig with
          Unix.c_icanon = false;
          Unix.c_echo = false;
          Unix.c_vmin = 1;
          Unix.c_vtime = 0;
        }
      in
      Unix.tcsetattr t.fd Unix.TCSANOW raw

let leave_raw t =
  match t.orig_termios with
  | None -> ()
  | Some orig -> ( try Unix.tcsetattr t.fd Unix.TCSANOW orig with _ -> ())

let disable_mouse t =
  let disable_seq =
    "\027[?1006l\027[?1015l\027[?1005l\027[?1003l\027[?1002l\027[?1000l"
  in
  (* Write to /dev/tty *)
  (try
     for _ = 1 to 2 do
       let _ =
         Unix.write
           t.tty_out_fd
           (Bytes.of_string disable_seq)
           0
           (String.length disable_seq)
       in
       ()
     done ;
     Unix.tcdrain t.tty_out_fd
   with _ -> ()) ;
  (* Write to stdout *)
  (try
     print_string disable_seq ;
     Stdlib.flush stdout
   with _ -> ()) ;
  (* Write to stderr *)
  (try Printf.eprintf "%s%!" disable_seq with _ -> ()) ;
  Unix.sleepf 0.05

let cleanup t =
  if not t.cleanup_done then begin
    t.cleanup_done <- true ;
    leave_raw t
  end ;
  disable_mouse t

let enable_mouse _t =
  try
    print_string "\027[?1000h\027[?1006h" ;
    Stdlib.flush stdout
  with _ -> ()

(* Size detection - direct method without System capability *)
let detect_size_direct () =
  try
    let pipe_read, pipe_write = Unix.pipe () in
    let tty_fd = Unix.openfile "/dev/tty" [Unix.O_RDONLY] 0 in
    let pid =
      Unix.create_process
        "stty"
        [|"stty"; "size"|]
        tty_fd
        pipe_write
        Unix.stderr
    in
    Unix.close tty_fd ;
    Unix.close pipe_write ;
    let buf = Buffer.create 32 in
    let tmp = Bytes.create 64 in
    let rec read_all () =
      match Unix.read pipe_read tmp 0 64 with
      | 0 -> ()
      | n ->
          Buffer.add_subbytes buf tmp 0 n ;
          read_all ()
    in
    read_all () ;
    Unix.close pipe_read ;
    let _ = Unix.waitpid [] pid in
    let output = String.trim (Buffer.contents buf) in
    match String.split_on_char ' ' output with
    | [r; c] ->
        let rows = int_of_string r in
        let cols = int_of_string c in
        Some (rows, cols)
    | _ -> None
  with _ -> None

let detect_size_env () =
  match (Sys.getenv_opt "MIAOU_TUI_ROWS", Sys.getenv_opt "MIAOU_TUI_COLS") with
  | Some r, Some c -> (
      try
        let rows = int_of_string (String.trim r) in
        let cols = int_of_string (String.trim c) in
        Some (rows, cols)
      with _ -> None)
  | _ -> None

let detect_size_uncached () =
  match detect_size_env () with
  | Some s -> s
  | None -> ( match detect_size_direct () with Some s -> s | None -> (24, 80))

let size t =
  match t.cached_size with
  | Some s -> s
  | None ->
      let s = detect_size_uncached () in
      t.cached_size <- Some s ;
      s

let invalidate_size_cache t = t.cached_size <- None

let fd t = t.fd

let write t s =
  try
    let _ = Unix.write t.tty_out_fd (Bytes.of_string s) 0 (String.length s) in
    ()
  with _ -> (
    try
      print_string s ;
      Stdlib.flush stdout
    with _ -> ())

let install_signals t cleanup_fn =
  let exit_flag = Atomic.make false in
  let sigwinch = 28 in
  (* Install resize handler *)
  (try
     Sys.set_signal
       sigwinch
       (Sys.Signal_handle
          (fun _ ->
            invalidate_size_cache t ;
            Atomic.set t.resize_pending true))
   with _ -> ()) ;
  (* Install exit handlers *)
  let set_exit_handler sigv =
    try
      Sys.set_signal
        sigv
        (Sys.Signal_handle
           (fun _ ->
             (try cleanup_fn () with _ -> ()) ;
             Atomic.set exit_flag true ;
             exit 130))
    with _ -> ()
  in
  set_exit_handler Sys.sigint ;
  set_exit_handler Sys.sigterm ;
  (try set_exit_handler Sys.sighup with _ -> ()) ;
  (try set_exit_handler Sys.sigquit with _ -> ()) ;
  exit_flag

let resize_pending t = Atomic.get t.resize_pending

let clear_resize_pending t = Atomic.set t.resize_pending false
