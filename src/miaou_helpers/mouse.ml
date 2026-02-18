(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Mouse event parsing utilities for widgets.

    Provides helpers to parse mouse key strings dispatched by drivers
    (e.g., "Mouse:5:10", "MouseDrag:3:7", "WheelUp", "WheelDown"). *)

(** Mouse click/drag event with coordinates. *)
type mouse_event = {row : int; col : int}

(** Parse a "Mouse:row:col", "DoubleClick:row:col", "TripleClick:row:col",
    or "MouseDrag:row:col" key string.
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
  | None -> (
      match try_parse "DoubleClick:" with
      | Some ev -> Some ev
      | None -> (
          match try_parse "TripleClick:" with
          | Some ev -> Some ev
          | None -> try_parse "MouseDrag:"))

(** Check if key is a mouse click event ("Mouse:..."). *)
let is_click key = String.length key > 6 && String.sub key 0 6 = "Mouse:"

(** Check if key is a double-click event ("DoubleClick:..."). *)
let is_double_click key =
  String.length key > 12 && String.sub key 0 12 = "DoubleClick:"

(** Check if key is a triple-click event ("TripleClick:..."). *)
let is_triple_click key =
  String.length key > 12 && String.sub key 0 12 = "TripleClick:"

(** Check if key is a mouse drag event ("MouseDrag:..."). *)
let is_drag key = String.length key > 10 && String.sub key 0 10 = "MouseDrag:"

(** Check if key is a wheel up event. *)
let is_wheel_up key = key = "WheelUp"

(** Check if key is a wheel down event. *)
let is_wheel_down key = key = "WheelDown"

(** Check if key is any wheel event. *)
let is_wheel key = is_wheel_up key || is_wheel_down key

(** Check if key is any mouse-related event. *)
let is_mouse_event key =
  is_click key || is_double_click key || is_triple_click key || is_drag key
  || is_wheel key

(** Scroll amount for wheel events (number of lines). *)
let wheel_scroll_lines = 3

(** Translate mouse coordinates by subtracting offsets.
    Used to convert screen-absolute coordinates to widget-relative coordinates.
    For click/drag events: subtracts [row_offset] from row and [col_offset] from col.
    For non-mouse or wheel events: returns the key unchanged. *)
let translate_key ~row_offset ~col_offset key =
  match parse_click key with
  | Some {row; col} ->
      let new_row = row - row_offset in
      let new_col = col - col_offset in
      let prefix =
        if is_double_click key then "DoubleClick:"
        else if is_triple_click key then "TripleClick:"
        else if is_drag key then "MouseDrag:"
        else "Mouse:"
      in
      Printf.sprintf "%s%d:%d" prefix new_row new_col
  | None -> key
