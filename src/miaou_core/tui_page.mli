(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
module type PAGE_SIG = sig
  (** The page's own state type (no next_page field needed). *)
  type state

  type msg

  (** Wrapped state with navigation support.
      Pages use [Navigation.goto], [Navigation.back], [Navigation.quit]
      to navigate, and [Navigation.update] to modify inner state. *)
  type pstate = state Navigation.t

  val init : unit -> pstate

  val update : pstate -> msg -> pstate

  val view : pstate -> focus:bool -> size:LTerm_geom.size -> string

  (* Driver-callable helpers, keeping msg abstract *)
  val move : pstate -> int -> pstate

  val refresh : pstate -> pstate

  val service_select : pstate -> int -> pstate

  val service_cycle : pstate -> int -> pstate

  val back : pstate -> pstate

  (* Unified keymap: pure description for stack-based dispatcher.
     Each entry: (key, state transformer, short help). *)
  val keymap : pstate -> (string * (pstate -> pstate) * string) list

  (* Declare which keys this page handles (for conflict detection).
     Pages should list all keys they handle, using Keys.t variants.
     This enables compile-time checking and auto-generated help. *)
  val handled_keys : unit -> Keys.t list

  (* When a modal is active, pages can handle raw key strings here (e.g., "a", "Backspace", "Left"). *)
  val handle_modal_key : pstate -> string -> size:LTerm_geom.size -> pstate

  (* Generic key handler - includes Enter, Esc, and all other keys.
     Use Navigation.goto/back/quit for navigation. *)
  val handle_key : pstate -> string -> size:LTerm_geom.size -> pstate

  (* Return true if the page currently has an active modal overlay that
     should consume most input. When true, the driver should avoid routing
     navigation keys (Up/Down/Left/Right/NextPage) to the background page. *)
  val has_modal : pstate -> bool
end
