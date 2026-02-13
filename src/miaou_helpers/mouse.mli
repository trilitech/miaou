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

(** Parse a ["Mouse:row:col"] or ["MouseDrag:row:col"] key string.
    @return [Some {row; col}] if valid, [None] otherwise. *)
val parse_click : string -> mouse_event option

(** Check if key is a mouse click event (["Mouse:..."]). *)
val is_click : string -> bool

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
