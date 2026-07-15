(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Serve_token = Miaou_serve.Serve_token

let with_env f = Eio_main.run @@ fun env -> f env

let test_length_and_charset () =
  with_env @@ fun env ->
  let t = Serve_token.generate ~env ~role:Serve_token.Controller in
  let s = Serve_token.to_string t in
  (* 32 bytes of entropy hex-encoded is 64 characters (FR-030: >= 128 bits;
     this token carries 256). *)
  check int "token length" (Serve_token.entropy_bytes * 2) (String.length s) ;
  let is_hex_char c =
    match c with '0' .. '9' | 'a' .. 'f' -> true | _ -> false
  in
  check bool "charset is lowercase hex" true (String.for_all is_hex_char s)

let test_role_bound_at_issuance () =
  with_env @@ fun env ->
  let c = Serve_token.generate ~env ~role:Serve_token.Controller in
  let v = Serve_token.generate ~env ~role:Serve_token.Viewer in
  check bool "controller role" true (Serve_token.role c = Serve_token.Controller) ;
  check bool "viewer role" true (Serve_token.role v = Serve_token.Viewer)

let test_matches_constant_time_semantics () =
  with_env @@ fun env ->
  let t = Serve_token.generate ~env ~role:Serve_token.Controller in
  let s = Serve_token.to_string t in
  check bool "matches own string" true (Serve_token.matches t ~candidate:s) ;
  check
    bool
    "rejects wrong-length candidate"
    false
    (Serve_token.matches t ~candidate:"deadbeef") ;
  check
    bool
    "rejects same-length-different candidate"
    false
    (Serve_token.matches t ~candidate:(String.make (String.length s) 'a'))

let test_no_collision_across_10k () =
  with_env @@ fun env ->
  let tbl = Hashtbl.create 10_000 in
  for _ = 1 to 10_000 do
    let t = Serve_token.generate ~env ~role:Serve_token.Controller in
    let s = Serve_token.to_string t in
    check
      bool
      (Printf.sprintf "no collision for %s" s)
      false
      (Hashtbl.mem tbl s) ;
    Hashtbl.add tbl s ()
  done

let () =
  run
    "serve_token"
    [
      ( "token",
        [
          test_case "length and charset" `Quick test_length_and_charset;
          test_case "role bound at issuance" `Quick test_role_bound_at_issuance;
          test_case
            "constant-time-safe matches"
            `Quick
            test_matches_constant_time_semantics;
          test_case
            "no collision across 10k generations"
            `Quick
            test_no_collision_across_10k;
        ] );
    ]
