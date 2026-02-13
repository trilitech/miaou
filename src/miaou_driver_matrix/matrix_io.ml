(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type event =
  | Key of string
  | MousePress of int * int  (** Mouse button pressed at (row, col) *)
  | Mouse of int * int  (** Mouse button released (click) at (row, col) *)
  | MouseDrag of int * int  (** Mouse motion while button held *)
  | Resize
  | Refresh
  | Idle
  | Quit

type t = {
  write : string -> unit;
  drain : unit -> event list;
  size : unit -> int * int;
  invalidate_size_cache : unit -> unit;
}
