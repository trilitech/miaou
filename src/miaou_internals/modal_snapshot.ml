(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

type max_width_spec =
  | Fixed of int
  | Ratio of float
  | Clamped of {ratio : float; min : int; max : int}

let resolve_max_width spec ~cols =
  match spec with
  | Fixed n -> Some n
  | Ratio r -> Some (int_of_float (float_of_int cols *. r))
  | Clamped {ratio; min; max} ->
      let scaled = int_of_float (float_of_int cols *. ratio) in
      Some (Stdlib.max min (Stdlib.min max scaled))

let provider :
    (unit ->
    (string
    * int option
    * max_width_spec option
    * bool
    * (LTerm_geom.size -> string))
    list)
    option
    ref =
  ref None

let set_provider f = provider := Some f

let get_stack_snapshot () = match !provider with Some f -> f () | None -> []

(** Last rendered modal geometry, stored by modal_renderer for use by click handling.
    Contains (content_top_row, content_left_col) where content starts (1-indexed). *)
let last_rendered_position : (int * int) option ref = ref None

let set_rendered_position ~top ~left = last_rendered_position := Some (top, left)

let get_rendered_position () = !last_rendered_position

let clear_rendered_position () = last_rendered_position := None
