(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type direction = Row | Column

type align_items = Start | Center | End | Stretch

type justify = Start | Center | End | Space_between | Space_around

type spacing = {h : int; v : int}

type padding = {left : int; right : int; top : int; bottom : int}

type basis = Auto | Px of int | Ratio of float | Percent of float | Fill

type size_hint = {width : int option; height : int option}

type child = {
  render : size:LTerm_geom.size -> string;  (** Render for the provided slot. *)
  basis : basis;
      (** Main-axis size request. [Auto]/[Fill] participate in even splitting of the remaining
          space. [Px] is fixed, [Percent] is relative to the available main size (after padding),
          and [Ratio] distributes the remaining space proportionally across all ratio-based items. *)
  cross : size_hint option;
      (** Optional cross-axis size hint; [None] uses the parent slot. *)
}

type child_constraint = {
  index : int;  (** 0-based child index. *)
  min_size : int option;  (** Minimum main-axis size in cells. *)
  max_size : int option;  (** Maximum main-axis size in cells. *)
}

type t

(** Create a flex container.

    - [direction]: main axis, [Row] (horizontal) or [Column] (vertical).
    - [align_items]: cross-axis placement of each child ([Start]/[Center]/[End]/[Stretch]).
    - [justify]: distribution on the main axis (start/center/end/space_between/space_around).
    - [gap]: horizontal/vertical spacing between children.
    - [padding]: surrounding padding inside the container.
    - [constraints]: optional per-child min/max size constraints (by index).

    Children are rendered in order; strings longer than their slot are visually truncated. *)
val create :
  ?direction:direction ->
  ?align_items:align_items ->
  ?justify:justify ->
  ?gap:spacing ->
  ?padding:padding ->
  ?constraints:child_constraint list ->
  child list ->
  t

(** Render the flex container into a newline-separated string sized to [size].

    {[
    let open Miaou_widgets_layout.Flex_layout in
    let row =
      create ~direction:Row ~gap:{h = 1; v = 0}
        [ {render = (fun ~size:_ -> "A"); basis = Px 1; cross = None};
          {render = (fun ~size:_ -> "wide"); basis = Percent 50.; cross = None};
          {render = (fun ~size:_ -> "fill"); basis = Fill; cross = None} ]
    in
    print_string (render row ~size:{cols = 30; rows = 1})
    ]}
*)
val render : t -> size:LTerm_geom.size -> string
