(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Mouse event parsing utilities for widgets.

    Provides helpers to parse mouse key strings dispatched by drivers
    (e.g., ["Mouse:5:10"], ["MouseDrag:3:7"], ["WheelUp"], ["WheelDown"]).

    {2 Usage}

    {[
      let handle_key t ~key =
        if Mouse.is_wheel_up key then
          scroll_up t Mouse.wheel_scroll_lines
        else if Mouse.is_wheel_down key then
          scroll_down t Mouse.wheel_scroll_lines
        else
          match Mouse.parse_click key with
          | Some {row; col} -> handle_click t ~row ~col
          | None -> (* not a mouse event *) t
    ]}
*)

(** Mouse click/drag event with terminal coordinates (1-indexed). *)
type mouse_event = {row : int; col : int}

(** Parse a ["Mouse:row:col"], ["DoubleClick:row:col"], ["TripleClick:row:col"],
    or ["MouseDrag:row:col"] key string.
    @return [Some {row; col}] if valid, [None] otherwise. *)
val parse_click : string -> mouse_event option

(** Check if key is a mouse click event (["Mouse:..."]). *)
val is_click : string -> bool

(** Check if key is a double-click event (["DoubleClick:..."]). *)
val is_double_click : string -> bool

(** Check if key is a triple-click event (["TripleClick:..."]). *)
val is_triple_click : string -> bool

(** Check if key is a mouse drag event (["MouseDrag:..."]). *)
val is_drag : string -> bool

(** Check if key is a wheel up event (["WheelUp"]). *)
val is_wheel_up : string -> bool

(** Check if key is a wheel down event (["WheelDown"]). *)
val is_wheel_down : string -> bool

(** Check if key is any wheel event (up or down). *)
val is_wheel : string -> bool

(** Check if key is any mouse-related event (click, drag, or wheel). *)
val is_mouse_event : string -> bool

(** Default scroll amount for wheel events (number of lines).
    Currently set to 3. *)
val wheel_scroll_lines : int

(** Translate mouse coordinates by subtracting offsets.
    Used to convert screen-absolute coordinates to widget-relative coordinates.
    For click/drag events: subtracts [row_offset] from row and [col_offset] from col.
    For non-mouse or wheel events: returns the key unchanged.

    {2 Example}
    {[
      (* Modal is at row 5, col 10 on screen *)
      let modal_row = 5 in
      let modal_col = 10 in
      (* Screen click at row 8, col 15 becomes widget-relative row 3, col 5 *)
      let relative_key = Mouse.translate_key ~row_offset:modal_row ~col_offset:modal_col "Mouse:8:15" in
      (* relative_key = "Mouse:3:5" *)
    ]}
*)
val translate_key : row_offset:int -> col_offset:int -> string -> string
