(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
type t = {
  http_get_string : string -> string -> string -> (string, string) result;
  http_get_url : string -> string -> string -> (string, string) result;
}

let key : t Miaou_interfaces.Capability.key =
  Miaou_interfaces.Capability.create ~name:"miaou.net"

let create ~http_get_string ~http_get_url =
  let wrap f = fun rpc_addr app_bin_dir path -> f ~rpc_addr ~app_bin_dir path in
  {http_get_string = wrap http_get_string; http_get_url = wrap http_get_url}

let register v = Miaou_interfaces.Capability.set key v

let get () = Miaou_interfaces.Capability.get key

let require () = Miaou_interfaces.Capability.require key

let http_get_string t ~rpc_addr ~app_bin_dir path =
  t.http_get_string rpc_addr app_bin_dir path

let http_get_url t ~rpc_addr ~app_bin_dir path =
  t.http_get_url rpc_addr app_bin_dir path
