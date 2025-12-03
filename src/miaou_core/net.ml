(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* (c) 2025 Nomadic Labs <contact@nomadic-labs.com> *)
[@@@warning "-32-34-37-69"]

type t = {get_url : url:string -> (string, string) result}

module Capability = Miaou_interfaces.Capability

let key : t Capability.key = Capability.create ~name:"Net"

let set v = Capability.set key v

let get () = Capability.get key

let require () = Capability.require key
