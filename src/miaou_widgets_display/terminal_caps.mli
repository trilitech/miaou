(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Terminal pixel rendering capability detection.

    Detects the best available sub-pixel rendering mode based on environment
    variables and terminal identification, using a priority chain:
    Sixel > Octant > Sextant > Half_block > Braille.

    Override with [MIAOU_PIXEL_MODE=sixel|octant|sextant|half_block|braille]. *)

type render_mode =
  | Sixel
      (** DCS-based pixel graphics (Phase 2 — not yet implemented in matrix driver). *)
  | Octant
      (** Unicode 16 2×4 block octants (U+1CD00 range) with fg+bg color per cell.
          Requires VTE ≥ 7800, foot, WezTerm, or Kitty. *)
  | Sextant
      (** Unicode 13 2×3 sextant blocks (U+1FB00 range) with fg+bg color.
          Supported by most modern terminals. *)
  | Half_block
      (** Standard Unicode half-block (▀/▄) with fg+bg — universal fallback. *)
  | Braille  (** Unicode Braille patterns — monochrome, 2×4 dots per cell. *)

(** Detect the best available rendering mode. Result is cached after the first
    call, so subsequent calls are O(1). *)
val detect : unit -> render_mode

(** Invalidate the detection cache so the next [detect ()] re-evaluates the
    environment.  Useful when [MIAOU_PIXEL_MODE] is changed at runtime. *)
val reset_cache : unit -> unit

(** Query physical cell dimensions via [CSI 16 t]. Returns
    [(cell_width_px, cell_height_px)] if the terminal responds, or [None].
    Currently returns [None] (Phase 2 — requires raw terminal I/O). *)
val cell_pixel_size : unit -> (int * int) option
