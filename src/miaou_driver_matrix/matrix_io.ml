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
  poll : timeout_ms:int -> event;
  drain_nav_keys : event -> int;
  drain_esc_keys : unit -> int;
  size : unit -> int * int;
  invalidate_size_cache : unit -> unit;
}
