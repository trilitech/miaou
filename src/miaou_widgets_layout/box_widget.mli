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

type border_style = Single | Double | Rounded | Ascii | Heavy

type padding = {left : int; right : int; top : int; bottom : int}

val render :
  ?title:string ->
  ?style:border_style ->
  ?padding:padding ->
  ?height:int ->
  ?color:int ->
  width:int ->
  string ->
  string
