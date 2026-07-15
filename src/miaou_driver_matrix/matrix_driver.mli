(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Terminal backend for the Matrix driver.

    Handles terminal-specific lifecycle (setup, raw mode, signals, cleanup)
    and delegates the main loop to [Matrix_main_loop]. This is the public
    entry point the runner executables ([runner_tui.ml], [runner_native.ml],
    [runner_web.ml]) select via their [available]/[run] driver record. *)

(** [true] iff this backend can be selected on the current platform. Always
    [true] for the Matrix driver (terminal-based, no optional native
    dependency). *)
val available : bool

(** [run_with_cleanup ~cleanup f] runs [f ()], always invoking [cleanup ()]
    afterwards — whether [f] returns normally or raises. Unlike
    [Fun.protect ~finally:cleanup f]:
    - a failure inside [cleanup] itself is swallowed rather than wrapped in
      [Finally_raised];
    - an exception raised by [f] is re-raised with its original backtrace
      preserved (via [Printexc.raise_with_backtrace]) instead of being
      masked.

    This lets a crashing page still leave the terminal in a restored,
    usable state: [cleanup] is expected to internally guard each of its own
    steps so one failing step (e.g. a write to an already-closed fd)
    doesn't skip the rest. Exposed for the cleanup-ordering regression test
    ([test_matrix_driver_cleanup.ml]); not otherwise part of the driver
    selection API (see [run] below for that). *)
val run_with_cleanup : cleanup:(unit -> unit) -> (unit -> 'a) -> 'a

(** [run ?config initial_page] runs the Matrix driver's main loop starting
    on [initial_page] until the page stack signals it should quit,
    navigate back past the root, or switch to a named page one level up.
    [config] defaults to {!Matrix_config.load}'s result (environment-variable
    driven) when omitted. *)
val run :
  ?config:Matrix_config.t option ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  [`Quit | `Back | `SwitchTo of string]
