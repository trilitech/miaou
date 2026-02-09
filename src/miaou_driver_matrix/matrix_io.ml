(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type event =
  | Key of string
  | Mouse of int * int
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
