(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Lightweight key token module for TUI key bindings. *)
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

val of_string : string -> t option

val to_string : t -> string

val equal : t -> t -> bool

val to_label : t -> string
