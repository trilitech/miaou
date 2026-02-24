(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Box widget: decorative border around content.

    Wraps string content in a Unicode/ASCII box with an optional title,
    configurable padding, and border styling.

    {[
      let box = Box_widget.render
        ~title:"Greeting"
        ~padding:{ left = 1; right = 1; top = 0; bottom = 0 }
        ~width:30
        "Hello, world!"
    ]}

    Output:
    {v
    +- Greeting -----------------+
    | Hello, world!              |
    +----------------------------+
    v} *)

type border_style = None_ | Single | Double | Rounded | Ascii | Heavy

type padding = {left : int; right : int; top : int; bottom : int}

(** Per-side border colors.

    Allows different colors for horizontal (top/bottom) and vertical
    (left/right) borders. Useful for indicating multiple states, e.g.,
    selection on top/left and status on bottom/right.

    When [border_colors] is provided, it takes precedence over [color]. *)
type border_colors = {
  c_top : int option;
  c_bottom : int option;
  c_left : int option;
  c_right : int option;
}

val render :
  ?title:string ->
  ?style:border_style ->
  ?padding:padding ->
  ?height:int ->
  ?color:int ->
  ?border_colors:border_colors ->
  ?bg:int ->
  width:int ->
  string ->
  string
