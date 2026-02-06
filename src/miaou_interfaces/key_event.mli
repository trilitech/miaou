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

(** [to_bool Handled] is [true], [to_bool Bubble] is [false]. *)
val to_bool : result -> bool

(** [of_bool true] is [Handled], [of_bool false] is [Bubble]. *)
val of_bool : bool -> result

(** Alias for [Handled]. *)
val handled : result

(** Alias for [Bubble]. *)
val bubble : result

(** Convert to polymorphic variant for backward compat with Focus_ring. *)
val to_poly : result -> [`Handled | `Bubble]

(** Convert from polymorphic variant. *)
val of_poly : [`Handled | `Bubble] -> result
