(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* This module file intentionally contains no definitions. The page signature
  is declared in the corresponding mli file `tui_page.mli`. Keeping this
  .ml file minimal prevents duplicate module-type definitions and helps the
  build stay consistent. *)

[@@@warning "-32-34-37-69"]

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

  val keymap : state -> (string * (state -> state) * string) list

  val handled_keys : unit -> Keys.t list

  (* When a modal is active, pages can handle raw key strings here *)
  val handle_modal_key : state -> string -> size:LTerm_geom.size -> state

  val handle_key : state -> string -> size:LTerm_geom.size -> state

  (* If Some page name is returned, the driver should switch to that page *)
  val next_page : state -> string option

  (* Return true if the page currently has an active modal overlay that
    should consume most input. When true, the driver will avoid routing
    navigation keys (Up/Down/Left/Right/NextPage) to the background page. *)
  val has_modal : state -> bool
end
