(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** CSS Grid-style 2D layout.

    Define rows and columns with track sizes, place children into cells
    (optionally spanning multiple rows/columns), and render the grid into
    a newline-separated string.

    {[
    let grid = Grid_layout.create
      ~rows:[Px 3; Fr 1.; Px 1]
      ~cols:[Px 20; Fr 1.]
      ~col_gap:1
      [
        span ~row:0 ~col:0 ~row_span:1 ~col_span:2 render_header;
        cell ~row:1 ~col:0 render_sidebar;
        cell ~row:1 ~col:1 render_main;
        span ~row:2 ~col:0 ~row_span:1 ~col_span:2 render_footer;
      ]
    in
    Grid_layout.render grid ~size
    ]} *)

(** Track sizing for rows and columns. *)
type track =
  | Px of int  (** Fixed size in cells. *)
  | Fr of float  (** Fractional unit — shares remaining space proportionally. *)
  | Percent of float  (** Percentage of total available space. *)
  | Auto  (** Equal share of remaining space (same as [Fr 1.]). *)
  | MinMax of int * int  (** Clamped: at least [min], at most [max]. *)

(** Where a child sits in the grid. *)
type placement = {
  row : int;  (** 0-based row index. *)
  col : int;  (** 0-based column index. *)
  row_span : int;  (** Number of rows to span (default 1). *)
  col_span : int;  (** Number of columns to span (default 1). *)
}

(** A child element placed in the grid. *)
type grid_child = {
  render : size:LTerm_geom.size -> string;
  placement : placement;
}

type t

(** Create a grid container.

    @param rows Track definitions for each row.
    @param cols Track definitions for each column.
    @param row_gap Vertical gap between rows (default 0).
    @param col_gap Horizontal gap between columns (default 0).
    @param padding Surrounding padding inside the container. *)
val create :
  rows:track list ->
  cols:track list ->
  ?row_gap:int ->
  ?col_gap:int ->
  ?padding:Flex_layout.padding ->
  grid_child list ->
  t

(** Render the grid into a newline-separated string sized to [size]. *)
val render : t -> size:LTerm_geom.size -> string

(** Place a child at [(row, col)] with span 1x1. *)
val cell : row:int -> col:int -> (size:LTerm_geom.size -> string) -> grid_child

(** Place a child with explicit row/column span. *)
val span :
  row:int ->
  col:int ->
  row_span:int ->
  col_span:int ->
  (size:LTerm_geom.size -> string) ->
  grid_child
