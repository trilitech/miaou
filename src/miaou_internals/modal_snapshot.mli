(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Max width specification for dynamic modal sizing *)
type max_width_spec =
  | Fixed of int
  | Ratio of float
  | Clamped of {ratio : float; min : int; max : int}

(** Resolve a max_width_spec to actual columns given terminal width *)
val resolve_max_width : max_width_spec -> cols:int -> int option

val set_provider :
  (unit ->
  (string
  * int option
  * max_width_spec option
  * bool
  * (LTerm_geom.size -> string))
  list) ->
  unit

val get_stack_snapshot :
  unit ->
  (string
  * int option
  * max_width_spec option
  * bool
  * (LTerm_geom.size -> string))
  list

(** Store the last rendered modal position for click coordinate translation.
    Called by modal_renderer after computing the actual modal position. *)
val set_rendered_position : top:int -> left:int -> unit

(** Get the last rendered modal position (content_top_row, content_left_col).
    Returns None if no modal has been rendered. *)
val get_rendered_position : unit -> (int * int) option

(** Clear the stored position (call when modal stack is empty). *)
val clear_rendered_position : unit -> unit
