(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Shared helpers for MIAOU's test suite: substring assertions, ANSI
    stripping, and boilerplate defaults for [PAGE_SIG] test stubs. *)

(** [contains_substring s sub] is [true] iff [sub] occurs somewhere in [s]. *)
val contains_substring : string -> string -> bool

(** [strip_ansi s] removes ANSI CSI escape sequences (e.g. color codes) from
    [s], leaving only the visible text. *)
val strip_ansi : string -> string

(** Minimal signature for {!Stub_page_defaults}: the page's own [state] type
    and the navigation-wrapped [pstate] built from it. *)
module type STATE = sig
  type state

  type pstate = state Miaou_core.Navigation.t
end

(** Default no-op implementations for the legacy/deprecated and
    rarely-varying members of {!Miaou_core.Tui_page.PAGE_SIG}
    ([move], [refresh], [service_select], [service_cycle], [back],
    [has_modal], [key_hints], [handle_modal_key], [on_modal_key]).

    Test stub pages that implement [PAGE_SIG] typically only care about
    [init], [update], [view], [handle_key] / [on_key], and sometimes
    [keymap] / [handled_keys]; the rest is identical boilerplate across
    stubs. [include Stub_page_defaults (struct ... end)] in a stub module to
    pull in the defaults, then override anything that needs different
    behavior. *)
module Stub_page_defaults (S : STATE) : sig
  val move : S.pstate -> int -> S.pstate

  val refresh : S.pstate -> S.pstate

  val service_select : S.pstate -> int -> S.pstate

  val service_cycle : S.pstate -> int -> S.pstate

  val back : S.pstate -> S.pstate

  val has_modal : S.pstate -> bool

  val key_hints : S.pstate -> Miaou_core.Tui_page.key_hint list

  val handle_modal_key : S.pstate -> string -> size:LTerm_geom.size -> S.pstate

  val on_modal_key :
    S.pstate ->
    Miaou_core.Keys.t ->
    size:LTerm_geom.size ->
    S.pstate * Miaou_interfaces.Key_event.result
end
