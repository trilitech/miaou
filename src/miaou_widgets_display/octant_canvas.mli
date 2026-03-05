(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Octant canvas for Unicode 16 sub-pixel rendering.

    Uses Unicode 16 block octant characters (U+1CD00 range) to provide
    2×4 sub-pixel resolution per terminal cell, identical to Braille but
    with per-cell fg+bg color support.

    Bit layout within each cell (row-major, left→right):
    {v
      bit 0 (0x01): (row 0, col 0)  bit 1 (0x02): (row 0, col 1)
      bit 2 (0x04): (row 1, col 0)  bit 3 (0x08): (row 1, col 1)
      bit 4 (0x10): (row 2, col 0)  bit 5 (0x20): (row 2, col 1)
      bit 6 (0x40): (row 3, col 0)  bit 7 (0x80): (row 3, col 1)
    v}

    Colors are ANSI SGR payload strings, e.g. ["32"] (green), ["38;5;214"]
    (256-color orange). Only [fg] color is tracked per cell; [bg] defaults to
    the terminal background. *)

type t

(** Create a blank octant canvas with the given cell dimensions. *)
val create : width:int -> height:int -> t

(** [(cell_width, cell_height)] — dimensions in terminal cells. *)
val get_dimensions : t -> int * int

(** [(dot_width, dot_height)] = [(cell_width * 2, cell_height * 4)]. *)
val get_dot_dimensions : t -> int * int

(** Set the sub-pixel at dot coordinates [(x, y)].  Out-of-bounds writes are
    silently ignored.  The cell's foreground color is updated to [color] when
    [color] is [Some _]. *)
val set_dot : t -> x:int -> y:int -> color:string option -> unit

(** Clear the sub-pixel at [(x, y)]. *)
val clear_dot : t -> x:int -> y:int -> unit

(** [true] if the sub-pixel at [(x, y)] is set. *)
val get_dot : t -> x:int -> y:int -> bool

(** Reset all cells to blank (pattern 0, no color). *)
val clear : t -> unit

(** Draw a Bresenham line between dot coordinates [(x0,y0)] and [(x1,y1)]. *)
val draw_line :
  t -> x0:int -> y0:int -> x1:int -> y1:int -> color:string option -> unit

(** OR [bits] into the pattern of cell [(cell_x, cell_y)].  Used for
    efficient bulk filling (e.g., bar chart columns). *)
val add_cell_bits :
  t -> cell_x:int -> cell_y:int -> bits:int -> color:string option -> unit

(** Render the canvas to a newline-separated ANSI string.  Each cell is
    emitted as [ESC[38;5;Nm<octant_char>ESC[0m] when colored, or as the bare
    octant character when uncolored. *)
val render : t -> string

(** Return the UTF-8 string for the given 8-bit octant bit pattern.
    Pattern [0x00] → space; [0xFF] → [U+2588] FULL BLOCK;
    other patterns → [U+1CD00 + pattern]. *)
val glyph_of_pattern : int -> string
