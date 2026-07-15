(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Narrow-seam parity scenario: modal dispatch + navigation resolution.

    {b Honest scope}: this exercises the small piece of logic every real
    driver loop (term, matrix, ...) relies on to resolve a key press into
    either "the active modal consumed it" or "the page handled it", and then
    to resolve any pending navigation request into [`Quit] / [`Back] /
    [`SwitchTo _]. It does {b not} exercise a full driver loop: it is not
    connected to a real terminal, to [Eio_unix.Stdenv.base], or to a real
    [Domain] — full-loop parity between the term and matrix drivers remains
    blocked on term-driver consolidation (post-G3; see kb/risks.md).

    Both the term and matrix instantiations of this scenario ({!Modal_nav_page},
    driven from separate test executables to avoid cross-test interference
    via the {!Miaou_core.Modal_manager} global singleton) share this single
    implementation, so a regression in the shared modal/navigation seam is
    caught identically regardless of which driver's key shapes triggered it. *)

(** A scripted key event: either a specific key string dispatched to the page
    (or to the active modal, if one is open), or an explicit end-of-script
    quit signal. *)
type key = Key of string | Quit

(** [run ~read_key (module Page)] repeatedly pulls keys from [read_key] and
    dispatches them: to the active modal via
    {!Miaou_core.Modal_manager.handle_key} if one is open, otherwise to
    [Page.handle_key]. After each dispatch, any pending navigation request
    set by a modal's [on_close] callback is resolved and, if present, ends
    the scenario. [read_key] returning [Quit] ends the scenario immediately. *)
val run :
  read_key:(unit -> key) ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  [`Quit | `Back | `SwitchTo of string]

(** A scripted key source that reads from a fixed list in order, and returns
    [Quit] once the list is exhausted (so a scenario never loops forever on
    an unresolved navigation). *)
val script : key list -> unit -> key
