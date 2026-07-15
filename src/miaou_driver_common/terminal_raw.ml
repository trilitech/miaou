(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Raw terminal operations shared between drivers.
    Based on term_terminal_setup.ml (lambda-term driver). *)

type t = {
  fd : Unix.file_descr;
  tty_out_fd : Unix.file_descr;
  orig_termios : Unix.terminal_io option;
  mutable cached_size : (int * int) option;
  mutable cleanup_done : bool;
  resize_pending : bool Atomic.t;
  write_mutex : Mutex.t;
  (* Screen content to dump on exit for debugging *)
  mutable exit_screen_dump : string option;
  (* When false, enter_raw / cleanup skip the alternate-screen
     sequences. The TUI then renders inline at the cursor position
     and its final frame stays in the terminal scrollback. *)
  mutable use_alt_screen : bool;
  (* Self-pipe used by {!install_signals'}'s async-signal-safe exit-signal
     handler to wake a fiber blocked in a blocking read/await on another fd
     (e.g. the Matrix driver's input reader, parked in
     [Eio_unix.await_readable]). The handler only sets [exit_flag] and
     writes one byte here — no mutex, no cleanup call, no [exit] — leaving
     graceful shutdown to whichever fiber observes the flag/pipe from
     ordinary (non-signal) context. Created lazily on first use. *)
  mutable signal_pipe : (Unix.file_descr * Unix.file_descr) option;
}

let write_all_fd fd bytes =
  let len = Bytes.length bytes in
  let rec loop off =
    if off < len then
      match Unix.write fd bytes off (len - off) with
      | 0 -> raise End_of_file
      | n -> loop (off + n)
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop off
  in
  loop 0

let write_all_string fd s = write_all_fd fd (Bytes.of_string s)

let with_write_lock t f =
  Mutex.lock t.write_mutex ;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.write_mutex) f

let setup () =
  let fd = Unix.descr_of_in_channel stdin in
  if not (try Unix.isatty fd with _ -> false) then
    failwith "interactive TUI requires a terminal" ;
  let orig_termios = try Some (Unix.tcgetattr fd) with _ -> None in
  (* Open /dev/tty directly for writing escape sequences - this is more reliable
     than stdout during cleanup/signal handling because stdout might be redirected *)
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
    write_mutex = Mutex.create ();
    exit_screen_dump = None;
    use_alt_screen = true;
    signal_pipe = None;
  }

let set_exit_screen_dump t dump = t.exit_screen_dump <- Some dump

(* Lazily create (once) the self-pipe used to wake a fiber blocked on
   another fd when an exit signal arrives. Returns the existing pipe if
   already created. *)
let ensure_signal_pipe t =
  match t.signal_pipe with
  | Some p -> p
  | None ->
      let read_fd, write_fd = Unix.pipe ~cloexec:true () in
      Unix.set_nonblock write_fd ;
      let p = (read_fd, write_fd) in
      t.signal_pipe <- Some p ;
      p

let signal_read_fd t = fst (ensure_signal_pipe t)

let set_alt_screen t enabled = t.use_alt_screen <- enabled

let alt_screen_enabled t = t.use_alt_screen

let fd t = t.fd

let enter_raw t =
  match t.orig_termios with
  | None -> ()
  | Some orig -> (
      let raw =
        {
          orig with
          Unix.c_icanon = false;
          Unix.c_echo = false;
          Unix.c_isig = false;
          (* Disable SIGINT/SIGQUIT/SIGSUSP generation *)
          Unix.c_vmin = 1;
          Unix.c_vtime = 0;
        }
      in
      Unix.tcsetattr t.fd Unix.TCSANOW raw ;
      (* Enter alternate screen mode unless inline mode is on *)
      if t.use_alt_screen then
        try
          let alt_seq = "\027[?1049h" in
          with_write_lock t (fun () -> write_all_string t.tty_out_fd alt_seq)
        with _ -> ())

let leave_raw t =
  match t.orig_termios with
  | None -> ()
  | Some orig -> ( try Unix.tcsetattr t.fd Unix.TCSANOW orig with _ -> ())

let disable_mouse t =
  (* ALWAYS run mouse cleanup - no flag check!
     Mouse tracking must be disabled reliably on exit.
     The escape sequences are idempotent (safe to send multiple times). *)
  let disable_seq =
    "\027[?1006l\027[?1015l\027[?1005l\027[?1003l\027[?1002l\027[?1000l"
  in
  (* Method 1: Write to /dev/tty *)
  (try
     with_write_lock t (fun () ->
         for _ = 1 to 2 do
           write_all_string t.tty_out_fd disable_seq
         done ;
         Unix.tcdrain t.tty_out_fd)
   with _ -> ()) ;
  (* Method 2: Write to stdout *)
  (try
     with_write_lock t (fun () ->
         (print_string
         [@allow_forbidden "terminal driver writes escape sequences"])
           disable_seq ;
         Stdlib.flush stdout)
   with _ -> ()) ;
  (* Method 3: Write to stderr as last resort *)
  (try with_write_lock t (fun () -> Printf.eprintf "%s%!" disable_seq)
   with _ -> ()) ;
  (* Give terminal time to process escape sequences *)
  (Unix.sleepf [@allow_forbidden "terminal cleanup needs blocking wait"]) 0.05

let enable_mouse t =
  (* 1002: Button event tracking (reports motion while button pressed)
     1006: SGR extended mode (allows coordinates > 223)
     Write to tty_out_fd for consistency with other terminal operations. *)
  let enable_seq = "\027[?1002h\027[?1006h" in
  (try
     with_write_lock t (fun () ->
         write_all_string t.tty_out_fd enable_seq ;
         Unix.tcdrain t.tty_out_fd)
   with _ -> ()) ;
  (* Also write to stdout as fallback *)
  try
    with_write_lock t (fun () ->
        (print_string
        [@allow_forbidden "terminal driver writes escape sequences"])
          enable_seq ;
        Stdlib.flush stdout)
  with _ -> ()

let cleanup t =
  if not t.cleanup_done then begin
    t.cleanup_done <- true ;
    (* Step 1: Exit alternate screen mode (restores main buffer).
       In inline mode we skip this — the rendered frame stays in
       scrollback. We do, however, append a newline so the next shell
       prompt does not land on top of the last rendered row. *)
    (if t.use_alt_screen then
       let exit_alt_seq = "\027[?1049l" in
       try
         with_write_lock t (fun () ->
             write_all_string t.tty_out_fd exit_alt_seq ;
             Unix.tcdrain t.tty_out_fd)
       with _ -> ()
     else
       try
         with_write_lock t (fun () ->
             write_all_string t.tty_out_fd "\n" ;
             Unix.tcdrain t.tty_out_fd)
       with _ -> ()) ;
    (* Step 2: Restore terminal settings *)
    leave_raw t ;
    (* Step 3: Print saved screen content (if any) for debugging.
       Write directly to /dev/tty to avoid shell interference (ble.sh, etc.).
       Skipped in inline mode — the live frame is already in scrollback. *)
    (if t.use_alt_screen then
       match t.exit_screen_dump with
       | Some dump -> (
           try
             with_write_lock t (fun () ->
                 let clear_seq = "\027[2J\027[H" in
                 write_all_string t.tty_out_fd clear_seq ;
                 write_all_string t.tty_out_fd dump ;
                 write_all_string t.tty_out_fd "\n" ;
                 Unix.tcdrain t.tty_out_fd)
           with _ -> ())
       | None -> ()) ;
    (* Step 4: Show cursor, reset style *)
    let final_seq = "\027[?25h\027[0m" in
    try
      with_write_lock t (fun () ->
          (print_string
          [@allow_forbidden "terminal driver writes escape sequences"])
            final_seq ;
          Stdlib.flush stdout)
    with _ -> ()
  end ;
  (* THEN disable mouse tracking - terminal is now in normal mode *)
  disable_mouse t

let write t s =
  with_write_lock t (fun () ->
      try write_all_string t.tty_out_fd s
      with _ -> (
        try
          (print_string
          [@allow_forbidden "terminal driver writes escape sequences"])
            s ;
          Stdlib.flush stdout
        with _ -> ()))

(* Size detection using stty - direct method without System capability *)
let detect_size_direct () =
  let run_stty ?stdin_fd argv =
    try
      let pipe_read, pipe_write = Unix.pipe () in
      let stdin_fd =
        match stdin_fd with
        | Some fd -> fd
        | None -> Unix.descr_of_in_channel Stdlib.stdin
      in
      (* Redirect stderr to /dev/null to suppress stty error messages *)
      let dev_null = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
      let pid =
        Fun.protect
          ~finally:(fun () -> Unix.close dev_null)
          (fun () ->
            Unix.create_process "stty" argv stdin_fd pipe_write dev_null)
      in
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
  in
  let try_stty argv =
    let tty_fd =
      try Some (Unix.openfile "/dev/tty" [Unix.O_RDONLY] 0) with _ -> None
    in
    let res =
      match tty_fd with
      | Some fd ->
          Fun.protect
            ~finally:(fun () -> Unix.close fd)
            (fun () -> run_stty ~stdin_fd:fd argv)
      | None -> run_stty argv
    in
    res
  in
  match try_stty [|"stty"; "size"; "-F"; "/proc/self/fd/1"|] with
  | Some s -> Some s
  | None -> (
      match try_stty [|"stty"; "size"; "-F"; "/dev/tty"|] with
      | Some s -> Some s
      | None -> try_stty [|"stty"; "size"|])

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

(* [install_signals'] uses an async-signal-safe handler: the first exit
   signal only sets [exit_flag] and writes one wake byte to the self-pipe
   (see [signal_read_fd]) — no mutex, no cleanup call, no [exit]. This lets
   a fiber blocked on another fd (e.g. a reader parked in
   [Eio_unix.await_readable]) wake up promptly by also watching the
   self-pipe's read end, then run its own graceful shutdown (stop
   readers/render loop, clean up the terminal, exit 130) from ordinary
   fiber context instead of from inside the signal handler.

   A second signal received while [exit_flag] is already set is treated as
   "already shutting down, or stuck" and force-exits unconditionally: it
   does NOT call [on_exit] (which, via [Terminal_raw.cleanup], acquires
   [t.write_mutex] — exactly the kind of blocking operation that may have
   wedged the graceful path this is meant to escape from calling it here
   would let the escape hatch itself deadlock on the same lock). Instead it
   writes a best-effort, mutex-free terminal-reset sequence directly to the
   tty fd (a single unlocked [Unix.write], errors swallowed) and then calls
   [Unix._exit] rather than [Stdlib.exit], since [Stdlib.exit] runs
   [at_exit] callbacks — including the very [Terminal_raw.cleanup] callback
   that takes the mutex — which would reintroduce the same deadlock risk on
   the way out. *)
let install_signals' t ~on_resize ~on_exit ?(handle_sigint = true) () =
  ignore on_exit ;
  let exit_flag = Atomic.make false in
  let sigwinch = 28 in
  (* Install resize handler *)
  (try
     Sys.set_signal
       sigwinch
       (Sys.Signal_handle
          (fun _ ->
            invalidate_size_cache t ;
            Atomic.set t.resize_pending true ;
            on_resize ()))
   with _ -> ()) ;
  let _read_fd, write_fd = ensure_signal_pipe t in
  let write_wake_byte () =
    try ignore (Unix.write write_fd (Bytes.make 1 '\000') 0 1) with _ -> ()
  in
  (* Mutex-free, best-effort emergency terminal restore for the second-
     signal escape hatch: exit alt-screen, disable mouse tracking, show
     cursor, reset style. Deliberately a single unlocked [Unix.write] (no
     [with_write_lock], no retry loop) — this path exists specifically for
     when the normal, mutex-guarded cleanup may be stuck. *)
  let emergency_restore () =
    let seq =
      "\027[?1049l"
      ^ "\027[?1006l\027[?1015l\027[?1005l\027[?1003l\027[?1002l\027[?1000l"
      ^ "\027[?25h\027[0m"
    in
    try
      ignore
        (Unix.write t.tty_out_fd (Bytes.of_string seq) 0 (String.length seq))
    with _ -> ()
  in
  let set_exit_handler sigv =
    try
      Sys.set_signal
        sigv
        (Sys.Signal_handle
           (fun _ ->
             if Atomic.get exit_flag then (
               emergency_restore () ;
               Unix._exit 130)
             else (
               Atomic.set exit_flag true ;
               write_wake_byte ())))
    with _ -> ()
  in
  if handle_sigint then set_exit_handler Sys.sigint
  else Sys.set_signal Sys.sigint Sys.Signal_ignore ;
  set_exit_handler Sys.sigterm ;
  (try set_exit_handler Sys.sighup with _ -> ()) ;
  (try set_exit_handler Sys.sigquit with _ -> ()) ;
  exit_flag

(* Classic (non-self-pipe) signal installation. Both terminal drivers now
   use {!install_signals'}; the only remaining consumer is the (currently
   uncalled) [Matrix_terminal.install_signals] wrapper — candidate for
   removal in a follow-up. WARNING: cleanup here runs synchronously inside
   the signal handler and takes [write_mutex]; if another domain holds the
   mutex at signal time the handler deadlocks. Kept only until the last
   wrapper is deleted, exactly as before this plan's
   Matrix-driver-focused self-pipe rework; deliberately not unified with
   {!install_signals'} to avoid changing an already-working, differently-
   shaped consumer without an interactive terminal available to verify
   signal behavior end-to-end.

   This does NOT make the in-handler cleanup safe — it is still running
   arbitrary terminal I/O (including acquiring [t.write_mutex] via
   [Terminal_raw.cleanup]) from inside a signal handler. If another domain
   holds [write_mutex] when the signal arrives, [on_exit ()] here blocks
   until that domain releases it, which can deadlock the handler (and thus
   the process, since nothing else runs [exit 130] on this path). The
   lambda-term driver's bounded-sleep polling of [exit_flag] only bounds
   how promptly a *different*, non-blocked consumer notices the flag; it
   does nothing to prevent this handler itself from wedging. This known
   risk is deliberately left as-is here and deferred to the same
   structural-debt package as the self-pipe rework for this path — fixing
   it properly needs the mutex-free/self-pipe treatment {!install_signals'}
   already has, applied to this path's consumers, which is out of scope for
   this conservative, non-unifying change. *)
let install_signals t ~on_resize ~on_exit =
  let exit_flag = Atomic.make false in
  let sigwinch = 28 in
  (try
     Sys.set_signal
       sigwinch
       (Sys.Signal_handle
          (fun _ ->
            invalidate_size_cache t ;
            Atomic.set t.resize_pending true ;
            on_resize ()))
   with _ -> ()) ;
  let set_exit_handler sigv =
    try
      Sys.set_signal
        sigv
        (Sys.Signal_handle
           (fun _ ->
             (try on_exit () with _ -> ()) ;
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
