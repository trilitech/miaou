(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
(* Mock Net implementation for examples and tests. *)

let slurp_file path =
  try
    let ic = open_in path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n ;
    close_in ic ;
    Ok (Bytes.to_string buf)
  with _ -> Error (Printf.sprintf "Failed to read %s" path)

let http_get_url ~env:_ ~rpc_addr:_ ~app_bin_dir:_ url =
  (* Very small, sync stub: try to read from local file when url starts with file://,
     otherwise return an error indicating network not available. *)
  if String.length url >= 7 && String.sub url 0 7 = "file://" then
    let path = String.sub url 7 (String.length url - 7) in
    slurp_file path
  else Error (Printf.sprintf "No network in mock for %s" url)

let http_get_string = http_get_url

let register () =
  Miaou.Net.register (Miaou.Net.create ~http_get_string ~http_get_url)
