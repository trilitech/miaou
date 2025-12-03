(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
let provider :
    (unit -> (string * int option * int option * bool * (unit -> string)) list)
    option
    ref =
  ref None

let set_provider f = provider := Some f

let get_stack_snapshot () = match !provider with Some f -> f () | None -> []
