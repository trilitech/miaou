(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let split_header_line line =
  match String.index_opt line ':' with
  | None -> None
  | Some i ->
      let name = String.trim (String.sub line 0 i) in
      let value =
        String.trim (String.sub line (i + 1) (String.length line - i - 1))
      in
      Some (name, value)

let header_value header_lines ~name =
  List.find_map
    (fun line ->
      match split_header_line line with
      | Some (n, v) when String.lowercase_ascii n = String.lowercase_ascii name
        ->
          Some v
      | Some _ | None -> None)
    header_lines

let is_websocket_upgrade header_lines =
  match header_value header_lines ~name:"Upgrade" with
  | Some v -> String.lowercase_ascii v = "websocket"
  | None -> false

let default_allowed ~bind ~port =
  [Printf.sprintf "http://%s:%d" (Serve_process.display_host bind) port]

let is_allowed ~allowed ~origin =
  match origin with
  | None -> true
  | Some o ->
      let o = String.lowercase_ascii o in
      List.exists (fun a -> String.lowercase_ascii a = o) allowed
