(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Mouse event parsing utilities for widgets.

    Provides helpers to parse mouse key strings dispatched by drivers
    (e.g., "Mouse:5:10", "MouseDrag:3:7", "WheelUp", "WheelDown"). *)

(** Mouse click/drag event with coordinates. *)
type mouse_event = {row : int; col : int}

(** Parse a "Mouse:row:col" or "MouseDrag:row:col" key string.
    Returns [Some {row; col}] if valid, [None] otherwise. *)
let parse_click key =
  let try_parse prefix =
    let plen = String.length prefix in
    if String.length key > plen && String.sub key 0 plen = prefix then
      let rest = String.sub key plen (String.length key - plen) in
      match String.split_on_char ':' rest with
      | [row_s; col_s] -> (
          try Some {row = int_of_string row_s; col = int_of_string col_s}
          with Failure _ -> None)
      | _ -> None
    else None
  in
  match try_parse "Mouse:" with
  | Some ev -> Some ev
  | None -> try_parse "MouseDrag:"

(** Check if key is a mouse click event ("Mouse:..."). *)
let is_click key = String.length key > 6 && String.sub key 0 6 = "Mouse:"

(** Check if key is a mouse drag event ("MouseDrag:..."). *)
let is_drag key = String.length key > 10 && String.sub key 0 10 = "MouseDrag:"

(** Check if key is a wheel up event. *)
let is_wheel_up key = key = "WheelUp"

(** Check if key is a wheel down event. *)
let is_wheel_down key = key = "WheelDown"

(** Check if key is any wheel event. *)
let is_wheel key = is_wheel_up key || is_wheel_down key

(** Check if key is any mouse-related event. *)
let is_mouse_event key = is_click key || is_drag key || is_wheel key

(** Scroll amount for wheel events (number of lines). *)
let wheel_scroll_lines = 3
