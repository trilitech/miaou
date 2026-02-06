(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Unified key event result type for all widgets and pages.

    This eliminates the inconsistency where:
    - Focus_ring returned [`Handled | `Bubble]
    - Button returned bool
    - Checkbox returned just t

    All key handlers now return [t * result] where result indicates
    whether the key was consumed. *)

type result =
  | Handled  (** Key was consumed by this handler *)
  | Bubble  (** Key was not handled, should propagate to parent *)

let to_bool = function Handled -> true | Bubble -> false

let of_bool b = if b then Handled else Bubble

let handled = Handled

let bubble = Bubble

let to_poly = function Handled -> `Handled | Bubble -> `Bubble

let of_poly = function `Handled -> Handled | `Bubble -> Bubble
