(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Lambda-term backend for the TUI runner.

    Handles terminal setup/cleanup, key decoding, resize tracking, and the
    render loop for the classic (non-Matrix) terminal driver. This is the
    public entry point the runner executables ([runner_tui.ml],
    [runner_native.ml], [runner_web.ml]) select via their [available]/[run]
    driver record. *)

(** [true] iff this backend can be selected on the current platform. Always
    [true] for the lambda-term driver. *)
val available : bool

(** [run initial_page] runs the lambda-term driver's main loop starting on
    [initial_page] until the page stack signals it should quit, navigate
    back past the root, or switch to a named page one level up. *)
val run :
  (module Miaou_core.Tui_page.PAGE_SIG) -> [`Quit | `Back | `SwitchTo of string]

(** Deterministic test entry point: runs with an injected key source instead
    of real TTY input (see {!Term_test_runner.run_with_key_source}). Kept
    for parity/headless-style tests of this driver; not used by the runner
    executables. *)
val run_with_key_source_for_tests :
  read_key:(unit -> Term_test_runner.driver_key) ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  [`Quit | `Back | `SwitchTo of string]
