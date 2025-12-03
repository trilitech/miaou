(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type t =
  | Up
  | Down
  | Left
  | Right
  | Tab
  | ShiftTab
  | Enter
  | Backspace
  | Char of string
  | Control of string

let to_string = function
  | Up -> "Up"
  | Down -> "Down"
  | Left -> "Left"
  | Right -> "Right"
  | Tab -> "Tab"
  | ShiftTab -> "Shift-Tab"
  | Enter -> "Enter"
  | Backspace -> "Backspace"
  | Char s -> s
  | Control s -> "C-" ^ s

let of_string s =
  match s with
  | "Up" -> Some Up
  | "Down" -> Some Down
  | "Left" -> Some Left
  | "Right" -> Some Right
  | "Tab" -> Some Tab
  | "Shift-Tab" -> Some ShiftTab
  | "Enter" -> Some Enter
  | "Backspace" -> Some Backspace
  | _ when String.length s = 2 && String.get s 0 = 'C' && String.get s 1 = '-'
    ->
      Some (Control (String.sub s 2 (String.length s - 2)))
  | _ -> Some (Char s)

let equal a b = to_string a = to_string b

let to_label = function
  | Up -> "↑"
  | Down -> "↓"
  | Left -> "←"
  | Right -> "→"
  | Tab -> "Tab"
  | ShiftTab -> "Shift-Tab"
  | Enter -> "Enter"
  | Backspace -> "Backspace"
  | Char s -> s
  | Control s -> "C-" ^ String.uppercase_ascii s
