(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Responsive layout selection by terminal width.

    A small utility for choosing between several layouts based on the current
    terminal width. The layouts themselves are values of any type — typically
    a {!Flex_layout.t} or {!Grid_layout.t}, but any type is fine.

    Order breakpoints by ascending [max_width]. {!pick} walks the list and
    returns the first layout whose [max_width] is greater than or equal to
    the current width; if none match (the terminal is wider than every
    breakpoint), [default] is returned.

    {b Typical usage}:
    {[
      let layout =
        Responsive.pick
          ~width:size.cols
          ~default:wide_layout
          [
            { max_width = 60; layout = narrow_layout };
            { max_width = 120; layout = medium_layout };
          ]
      in
      ...
    ]}
*)

(** A single layout choice keyed by an inclusive maximum width. *)
type 'a breakpoint = {
  max_width : int;  (** Apply [layout] when [width <= max_width]. *)
  layout : 'a;
}

(** Pick the layout matching the current width.

    Walks [breakpoints] in order. Returns the [layout] of the first entry
    whose [max_width >= width]. If no entry matches, returns [default].

    Tip: order breakpoints from narrowest to widest so the narrow case
    "wins" first, matching CSS's mobile-first ordering. *)
val pick : 'a breakpoint list -> default:'a -> width:int -> 'a
