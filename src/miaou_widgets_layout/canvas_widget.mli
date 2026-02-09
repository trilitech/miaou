(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Canvas_widget — an embeddable drawing surface for layouts.

    Wraps a {!Miaou_canvas.Canvas.t} with automatic resizing and provides
    a standard widget render function compatible with flex/grid layouts,
    panes, and vsections.

    {2 Usage}

    {[
      (* In your page state *)
      type state = { cw : Canvas_widget.t; ... }

      (* Initialize *)
      let init () = { cw = Canvas_widget.create (); ... }

      (* Draw in refresh (runs once per tick, not per render) *)
      let refresh ps =
        let s = ps.Navigation.s in
        let canvas = Canvas_widget.canvas s.cw in
        Canvas.clear canvas;
        Canvas.draw_text canvas ~row:0 ~col:0 ~style "Hello";
        ps

      (* Embed in a flex layout *)
      let view ps ~focus ~size =
        Flex_layout.render
          (Flex_layout.create ~direction:Column [
            { render = Canvas_widget.render ps.s.cw; basis = Fill; cross = None };
          ])
          ~size
    ]}

    The canvas is automatically created/resized to match the allocated slot
    when {!render} is called. If the size changes, a fresh canvas is created
    (the page should redraw on its next refresh cycle). *)

(** The canvas widget state. *)
type t

(** [create ()] creates a canvas widget with no initial canvas.
    The inner canvas is allocated on the first call to {!render}. *)
val create : unit -> t

(** [canvas t] returns the inner canvas for drawing into.

    Returns [None] if {!render} has not been called yet (the canvas has
    not been allocated). After the first render, this always returns
    [Some canvas]. *)
val canvas : t -> Miaou_canvas.Canvas.t option

(** [canvas_exn t] returns the inner canvas, raising [Invalid_argument]
    if it has not been allocated yet. *)
val canvas_exn : t -> Miaou_canvas.Canvas.t

(** [ensure t ~rows ~cols] ensures the inner canvas exists and has the
    given dimensions. If the canvas doesn't exist or the size differs,
    a new canvas is created. Returns the (possibly updated) widget.

    This is useful when the page needs to draw into the canvas before
    the first render call (e.g., in [init]). *)
val ensure : t -> rows:int -> cols:int -> t

(** [clear t] clears the inner canvas contents, if any.
    Returns the widget unchanged (the canvas is mutated in place). *)
val clear : t -> t

(** [render t] returns a render function compatible with flex/grid layouts.

    The returned function has signature [size:LTerm_geom.size -> string].
    On each call it ensures the canvas matches the allocated size, then
    returns {!Miaou_canvas.Canvas.to_ansi}.

    {b Note:} If the size changes between calls, a fresh (empty) canvas
    is created. The page should redraw on its next refresh cycle. *)
val render : t -> size:LTerm_geom.size -> string

(** [rows t] returns the current canvas height, or [0] if not allocated. *)
val rows : t -> int

(** [cols t] returns the current canvas width, or [0] if not allocated. *)
val cols : t -> int
