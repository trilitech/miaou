(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** {1 Key Hints} *)

(** Display-only key hint for help footer. Unlike the old [key_binding] type,
    this has no action - it's purely for showing users what keys are available.
    All actual key handling goes through [on_key]. *)
type key_hint = {
  key : string;  (** Display string, e.g., "Tab/S-Tab", "Enter", "Esc" *)
  help : string;  (** Description, e.g., "Navigate fields", "Submit" *)
}

(** {1 Legacy Key Binding (deprecated)} *)

(** @deprecated Use [key_hint] for display and [on_key] for handling. *)
type 'state key_binding_desc = {
  key : string;
  action : 'state Navigation.t -> 'state Navigation.t;
  help : string;
  display_only : bool;
}

type 'state key_binding = 'state key_binding_desc

(** {1 Page Signature} *)

module type PAGE_SIG = sig
  (** The page's own state type. *)
  type state

  type msg

  (** @deprecated Use [key_hint] instead. *)
  type key_binding = state key_binding_desc

  (** Wrapped state with navigation support.
      Pages use [Navigation.goto], [Navigation.back], [Navigation.quit]
      to navigate, and [Navigation.update] to modify inner state. *)
  type pstate = state Navigation.t

  val init : unit -> pstate

  val update : pstate -> msg -> pstate

  val view : pstate -> focus:bool -> size:LTerm_geom.size -> string

  (** {2 Key Handling - New API} *)

  (** Primary key handler. Most keys go through this method.
      Returns the updated state and whether the key was handled.
      Use [Navigation.goto/back/quit] for navigation.

      Note: Mouse events (["Mouse:row:col"]) currently go through the legacy
      [handle_key] as [Keys.of_string] cannot parse them. This may change
      in a future release. *)
  val on_key :
    pstate ->
    Keys.t ->
    size:LTerm_geom.size ->
    pstate * Miaou_interfaces.Key_event.result

  (** Modal key handler. Called when [has_modal] returns true. *)
  val on_modal_key :
    pstate ->
    Keys.t ->
    size:LTerm_geom.size ->
    pstate * Miaou_interfaces.Key_event.result

  (** Display-only key hints for footer/help display.
      These are never dispatched - all handling goes through [on_key]. *)
  val key_hints : pstate -> key_hint list

  (** {2 Key Handling - Legacy API (deprecated)} *)

  (** @deprecated Use [on_key] instead. Kept for backward compatibility. *)
  val handle_key : pstate -> string -> size:LTerm_geom.size -> pstate

  (** @deprecated Use [on_modal_key] instead. *)
  val handle_modal_key : pstate -> string -> size:LTerm_geom.size -> pstate

  (** @deprecated Use [key_hints] instead. Actions are ignored by modern drivers. *)
  val keymap : pstate -> key_binding list

  (** {2 Lifecycle} *)

  val refresh : pstate -> pstate

  (** Return true if the page currently has an active modal overlay that
      should consume most input. When true, the driver routes keys to
      [on_modal_key] instead of [on_key]. *)
  val has_modal : pstate -> bool

  (** {2 Legacy Methods (deprecated)} *)

  (** @deprecated Rarely used. Will be removed in future version. *)
  val move : pstate -> int -> pstate

  (** @deprecated Rarely used. Will be removed in future version. *)
  val service_select : pstate -> int -> pstate

  (** @deprecated Rarely used. Will be removed in future version. *)
  val service_cycle : pstate -> int -> pstate

  (** @deprecated Use [Navigation.back] in [on_key] instead. *)
  val back : pstate -> pstate

  (** @deprecated Not used by modern drivers. *)
  val handled_keys : unit -> Keys.t list
end
