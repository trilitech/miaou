(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Terminal setup for lambda-term driver - thin wrapper around Terminal_raw. *)

module Raw = Miaou_driver_common.Terminal_raw

(* Keep the same interface for backward compatibility with lambda_term_driver.ml *)
let setup_and_cleanup ?(on_resize = fun () -> ()) ?(handle_sigint = true) () =
  let t = Raw.setup () in
  let fd = Raw.fd t in
  let enter_raw () = Raw.enter_raw t in
  let cleanup () = Raw.cleanup t in
  let signal_exit_flag =
    (* Self-pipe / exit-flag installer (see [Terminal_raw.install_signals']):
       the exit-signal handler only sets [signal_exit_flag] and wakes the
       self-pipe — it does not run [cleanup] or call [exit] itself, so
       there is no risk of the handler wedging on [t.write_mutex] the way
       the classic [Raw.install_signals] path could. Graceful shutdown
       (stop the reader, restore the terminal, preserve the 130 exit code)
       happens from ordinary fiber context in [Lambda_term_driver.run],
       mirroring the Matrix driver's boundary check.
       [Raw.install_signals'] already invalidates the session's size cache
       on SIGWINCH before calling [on_resize]; a second, independent
       [Sys.set_signal] on the caller's side would silently replace this
       installer instead of composing with it, so any extra resize
       book-keeping the driver needs must flow through [on_resize]. *)
    Raw.install_signals' t ~on_resize ~on_exit:(fun () -> ()) ~handle_sigint ()
  in
  let install_signal_handlers () =
    (* Signals already installed by Raw.install_signals', this is a no-op *)
    ()
  in
  (t, fd, enter_raw, cleanup, install_signal_handlers, signal_exit_flag)
