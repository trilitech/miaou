(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Shared utilities for chart widgets. *)

val bounds : float list -> float * float
(** Find min and max in a list of floats. Returns (min, max).
    Returns (0., 0.) for empty list. *)

val scale :
  value:float -> min_val:float -> max_val:float -> display_max:int -> int
(** Scale a value from data range [min_val, max_val] to display range [0, display_max].
    Returns 0 if range is zero. *)

val format_value : float -> string
(** Format a float for display with smart precision.
    - Large values (>= 1000): no decimal places
    - Medium values (>= 10): 1 decimal place
    - Small values: 2 decimal places *)

val format_label : value:float -> unit_:string -> string
(** Format axis label with units.
    Example: format_label ~value:42.5 ~unit_:"MB" = "42.5MB" *)

val tick_positions : count:int -> max:int -> int list
(** Generate evenly-spaced tick positions.
    Example: tick_positions ~count:5 ~max:100 = [0; 25; 50; 75; 100] *)

val nice_number : float -> round_up:bool -> float
(** Round to nice numbers for axis labels (1, 2, 5, 10, 20, 50, 100, etc.).
    - [round_up]: if true, round up; otherwise round to nearest. *)
