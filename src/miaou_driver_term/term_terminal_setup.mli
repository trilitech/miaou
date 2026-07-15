(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Returns (terminal, fd, enter_raw, cleanup, install_signal_handlers,
    signal_exit_flag).

    [terminal] is the single {!Miaou_driver_common.Terminal_raw.t} session
    handle — pass it to [Term_size_detection.detect_size] /
    [Term_size_detection.invalidate_cache] instead of opening a second
    [/dev/tty] handle.

    @param on_resize Called on SIGWINCH, after the session's size cache has
      already been invalidated (see
      {!Miaou_driver_common.Terminal_raw.install_signals'}). Use this to
      also flip a driver-local "resize pending" flag — both effects must
      happen from a single signal installer, since a second
      [Sys.set_signal] call on the same signal would silently replace this
      one instead of composing with it.
    @param handle_sigint If false, SIGINT (Ctrl+C) is not intercepted,
      allowing the app to receive it as a key event. Default: true.

    Signals are installed via
    {!Miaou_driver_common.Terminal_raw.install_signals'}: an exit signal
    only flips [signal_exit_flag] and wakes the session's self-pipe (see
    {!Miaou_driver_common.Terminal_raw.signal_read_fd}) rather than running
    cleanup or exiting from inside the handler. Callers must poll
    [signal_exit_flag] (and may watch the self-pipe fd for a prompter
    wake-up) and perform their own graceful shutdown from fiber context. *)
val setup_and_cleanup :
  ?on_resize:(unit -> unit) ->
  ?handle_sigint:bool ->
  unit ->
  Miaou_driver_common.Terminal_raw.t
  * Unix.file_descr
  * (unit -> unit)
  * (unit -> unit)
  * (unit -> unit)
  * bool Atomic.t
