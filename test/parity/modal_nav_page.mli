(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Shared page fixture for {!Modal_nav_scenario}: starts with a modal that
    commits (navigating to ["NEXT"]) on ["Enter"] or cancels (no navigation)
    on ["Esc"]. Any other key is bubbled to the modal (if active) or ignored
    by the underlying page. Pure module code, no top-level mutable state of
    its own; interaction with {!Miaou_core.Modal_manager} (a process-global
    singleton) is why term and matrix instantiations run in separate test
    executables rather than sharing a process. *)
module Dummy_page : Miaou_core.Tui_page.PAGE_SIG with type state = unit
