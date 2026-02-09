(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Canvas — a driver-agnostic, cell-level 2D surface for TUI rendering.

    A canvas is a mutable grid of cells, where each cell holds a UTF-8
    grapheme cluster and a style (foreground/background color, bold, dim,
    underline, reverse).

    Canvases can be rendered to ANSI strings via {!to_ansi} for use with the
    existing [view] pipeline, or iterated over via {!iter} so that a driver
    can transfer cells to its own buffer format (e.g. the matrix driver's
    [Matrix_buffer]). *)

(** {1 Types} *)

(** Visual style for a single cell.

    Colors use 256-color palette indices: [-1] means "default terminal
    color", [0]–[255] are the standard 256-color palette values. *)
type style = {
  fg : int;  (** Foreground color, [-1] = default *)
  bg : int;  (** Background color, [-1] = default *)
  bold : bool;
  dim : bool;
  underline : bool;
  reverse : bool;
}

(** A single cell in the canvas grid. *)
type cell = {char : string; style : style}

(** A mutable 2D grid of cells. *)
type t

(** Border drawing styles for {!draw_box}. *)
type border_style = Single | Double | Rounded | Ascii | Heavy

(** Border character set used by {!draw_box}. Exposed so callers can supply
    custom border glyphs via {!draw_box_with_chars}. *)
type border_chars = {
  tl : string;
  tr : string;
  bl : string;
  br : string;
  h : string;
  v : string;
}

(** {1 Constants} *)

(** The default style: no colors ([-1]), no attributes. *)
val default_style : style

(** An empty cell: a single space with {!default_style}. *)
val empty_cell : cell

(** {1 Creation} *)

(** [create ~rows ~cols] allocates a canvas filled with {!empty_cell}.

    @raise Invalid_argument if [rows] or [cols] is negative. *)
val create : rows:int -> cols:int -> t

(** {1 Dimensions} *)

val rows : t -> int

val cols : t -> int

(** {1 Cell access} *)

(** [set_char t ~row ~col ~char ~style] sets the cell at [(row, col)].
    Out-of-bounds writes are silently ignored. *)
val set_char : t -> row:int -> col:int -> char:string -> style:style -> unit

(** [get_cell t ~row ~col] returns the cell at [(row, col)].

    @raise Invalid_argument if the coordinates are out of bounds. *)
val get_cell : t -> row:int -> col:int -> cell

(** {1 Drawing primitives} *)

(** [fill_rect t ~row ~col ~width ~height ~char ~style] fills a rectangular
    region. Out-of-bounds portions are clipped. *)
val fill_rect :
  t ->
  row:int ->
  col:int ->
  width:int ->
  height:int ->
  char:string ->
  style:style ->
  unit

(** [clear t] resets every cell to {!empty_cell}. *)
val clear : t -> unit

(** [draw_text t ~row ~col ~style text] writes a plain-text string
    horizontally starting at [(row, col)]. Each UTF-8 grapheme cluster
    occupies one cell. The text must not contain ANSI escape sequences.
    Out-of-bounds portions are clipped. *)
val draw_text : t -> row:int -> col:int -> style:style -> string -> unit

(** [draw_hline t ~row ~col ~len ~char ~style] draws a horizontal line. *)
val draw_hline :
  t -> row:int -> col:int -> len:int -> char:string -> style:style -> unit

(** [draw_vline t ~row ~col ~len ~char ~style] draws a vertical line. *)
val draw_vline :
  t -> row:int -> col:int -> len:int -> char:string -> style:style -> unit

(** [draw_box t ~row ~col ~width ~height ~border ~style] draws a rectangular
    border. The border occupies 1 cell on each side, so the interior is
    [(width - 2) x (height - 2)]. Boxes smaller than 2x2 are silently
    ignored. *)
val draw_box :
  t ->
  row:int ->
  col:int ->
  width:int ->
  height:int ->
  border:border_style ->
  style:style ->
  unit

(** [draw_box_with_chars t ~row ~col ~width ~height ~chars ~style] draws a
    box using custom border characters. *)
val draw_box_with_chars :
  t ->
  row:int ->
  col:int ->
  width:int ->
  height:int ->
  chars:border_chars ->
  style:style ->
  unit

(** {1 Composition} *)

(** [blit ~src ~dst ~row ~col] copies non-empty cells from [src] onto [dst]
    at offset [(row, col)]. Only cells whose [char] is not [" "] (space) are
    copied, making spaces transparent. Out-of-bounds portions are clipped. *)
val blit : src:t -> dst:t -> row:int -> col:int -> unit

(** [blit_all ~src ~dst ~row ~col] copies all cells from [src] onto [dst]
    at offset [(row, col)], including spaces. Out-of-bounds portions are
    clipped. *)
val blit_all : src:t -> dst:t -> row:int -> col:int -> unit

(** {1 Output} *)

(** [to_ansi t] renders the canvas to an ANSI-escaped string suitable for
    terminal display. Rows are separated by newlines. Style changes are
    tracked so that SGR codes are only emitted when the style actually
    changes between cells. *)
val to_ansi : t -> string

(** {1 Iteration} *)

(** [iter t ~f] calls [f ~row ~col cell] for every cell in row-major
    order. This is the primary integration point for drivers: iterate
    the canvas and transfer cells to the driver's own buffer format. *)
val iter : t -> f:(row:int -> col:int -> cell -> unit) -> unit

(** {1 Border utilities} *)

(** [border_chars_of_style style] returns the character set for a given
    border style. *)
val border_chars_of_style : border_style -> border_chars
