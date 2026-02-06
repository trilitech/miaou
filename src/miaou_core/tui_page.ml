(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

(** Display-only key hint for help footer. *)
type key_hint = {key : string; help : string}

(** Legacy key binding type. Deprecated - use [key_hint] for display
    and [on_key] for handling. *)
type 'state key_binding_desc = {
  key : string;
  action : 'state Navigation.t -> 'state Navigation.t;
  help : string;
  display_only : bool;
}

type 'state key_binding = 'state key_binding_desc

module type PAGE_SIG = sig
  type state

  type msg

  type key_binding = state key_binding_desc

  type pstate = state Navigation.t

  val init : unit -> pstate

  val update : pstate -> msg -> pstate

  val view : pstate -> focus:bool -> size:LTerm_geom.size -> string

  (* New key handling API *)
  val on_key :
    pstate ->
    Keys.t ->
    size:LTerm_geom.size ->
    pstate * Miaou_interfaces.Key_event.result

  val on_modal_key :
    pstate ->
    Keys.t ->
    size:LTerm_geom.size ->
    pstate * Miaou_interfaces.Key_event.result

  val key_hints : pstate -> key_hint list

  (* Legacy key handling API (deprecated) *)
  val handle_key : pstate -> string -> size:LTerm_geom.size -> pstate

  val handle_modal_key : pstate -> string -> size:LTerm_geom.size -> pstate

  val keymap : pstate -> key_binding list

  (* Lifecycle *)
  val refresh : pstate -> pstate

  val has_modal : pstate -> bool

  (* Legacy methods (deprecated) *)
  val move : pstate -> int -> pstate

  val service_select : pstate -> int -> pstate

  val service_cycle : pstate -> int -> pstate

  val back : pstate -> pstate

  val handled_keys : unit -> Keys.t list
end
