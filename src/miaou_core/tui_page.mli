(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
module type PAGE_SIG = sig
  type state

  type msg

  val init : unit -> state

  val update : state -> msg -> state

  val view : state -> focus:bool -> size:LTerm_geom.size -> string

  (* Driver-callable helpers, keeping msg abstract *)
  val move : state -> int -> state

  val refresh : state -> state

  val enter : state -> state

  val service_select : state -> int -> state

  val service_cycle : state -> int -> state

  val back : state -> state

  (* Unified keymap: pure description for stack-based dispatcher.
     Each entry: (key, state transformer, short help). *)
  val keymap : state -> (string * (state -> state) * string) list

  (* When a modal is active, pages can handle raw key strings here (e.g., "a", "Backspace", "Left"). *)
  val handle_modal_key : state -> string -> size:LTerm_geom.size -> state

  (* Generic fallback key handler for unbound keys (keeps backward compatibility). *)
  val handle_key : state -> string -> size:LTerm_geom.size -> state

  (* If Some page name is returned, the driver should switch to that page *)
  val next_page : state -> string option

  (* Return true if the page currently has an active modal overlay that
	   should consume most input. When true, the driver should avoid routing
	   navigation keys (Up/Down/Left/Right/NextPage) to the background page. *)
  val has_modal : state -> bool
end
