(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
open Rresult

let http_get_string ~rpc_addr:_ ~app_bin_dir:_ path : (string, string) result =
  try
    let open Lwt.Infix in
    let fetch uri =
      Cohttp_lwt_unix.Client.get (Uri.of_string uri) >>= fun (_resp, body) ->
      Cohttp_lwt.Body.to_string body
    in
    Ok (Lwt_main.run (fetch path))
  with exn -> Error (Printexc.to_string exn)

let http_get_url ~rpc_addr:_ ~app_bin_dir:_ url : (string, string) result =
  (* Same implementation as http_get_string; kept separate for clarity. *)
  http_get_string ~rpc_addr:"" ~app_bin_dir:"" url

let try_register () =
  try
    let _ =
      (* Create and register the provider *)
      Net.register (Net.create ~http_get_string ~http_get_url)
    in
    Ok ()
  with exn -> Error (Printexc.to_string exn)
