(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
val set_provider :
  (unit -> (string * int option * int option * bool * (unit -> string)) list) ->
  unit

val get_stack_snapshot :
  unit -> (string * int option * int option * bool * (unit -> string)) list
