(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type event =
  | Key of string
  | MousePress of int * int * int
      (** Mouse button pressed at (row, col, button). button: 0=left, 1=middle, 2=right *)
  | Mouse of int * int * int
      (** Mouse button released (click) at (row, col, button). button: 0=left, 1=middle, 2=right *)
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
