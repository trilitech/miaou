(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Pixel-level framebuffer widget for TUI rendering.

    Holds a mutable RGB pixel buffer and renders it to the terminal using the
    best available sub-pixel mode (detected via {!Terminal_caps.detect}).

    {1 Render mode priority}

    {v Sixel → Octant → Sextant → Half_block → Braille v}

    Set [MIAOU_PIXEL_MODE] to override (see {!Terminal_caps}).

    {1 Usage}

    {[
      let fb = Framebuffer_widget.create () in
      (* Draw some pixels *)
      Framebuffer_widget.clear fb ~r:0 ~g:0 ~b:0 ;
      Framebuffer_widget.fill_rect fb ~x:4 ~y:4 ~w:8 ~h:8 ~r:255 ~g:100 ~b:0 ;
      (* Render into 40 cols × 10 rows *)
      print_string (Framebuffer_widget.render fb ~cols:40 ~rows:10)
    ]}
*)

type t

(** Create a framebuffer. The pixel buffer is allocated lazily on first render. *)
val create : unit -> t

(** Set a single pixel in the buffer (0-based, clamped to current dimensions). *)
val set_pixel : t -> x:int -> y:int -> r:int -> g:int -> b:int -> unit

(** Replace the pixel buffer with [src] (flat RGB, stride = [width * 3]).
    The buffer is resized to [width × height] pixels. *)
val blit : t -> src:bytes -> width:int -> height:int -> unit

(** Fill the entire pixel buffer with the given color. *)
val clear : t -> r:int -> g:int -> b:int -> unit

(** Fill a rectangle with the given color (clamped to buffer bounds). *)
val fill_rect :
  t -> x:int -> y:int -> w:int -> h:int -> r:int -> g:int -> b:int -> unit

(** Render the framebuffer into [cols × rows] terminal cells.

    The pixel buffer is (re)sized to match the sub-pixel resolution for the
    selected render mode:
    - Octant / Braille: [cols*2 × rows*4] pixels
    - Sextant: [cols*2 × rows*3] pixels
    - Half_block: [cols*1 × rows*2] pixels
    - Sixel: uses physical cell pixel size if available, else [cols*8 × rows*16]

    Output is cached; re-encoding only occurs when the buffer is dirty or
    the size changes. *)
val render : t -> cols:int -> rows:int -> string
