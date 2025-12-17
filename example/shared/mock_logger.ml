(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* Mock Logger implementation for examples and tests. *)

let logf _lvl s = Printf.printf "%s\n" s

let set_enabled _ = ()

let set_logfile _ = Ok ()

let register () =
  let module L = Miaou_interfaces.Logger_capability in
  L.set {L.logf; set_enabled; set_logfile}
