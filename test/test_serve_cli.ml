(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Serve_cli = Miaou_serve.Serve_cli
module Serve_config = Miaou_serve.Serve_config

let test_roundtrip () =
  let argv =
    [|
      "miaou";
      "--app";
      "octez-manager";
      "--port";
      "9999";
      "--bind";
      "0.0.0.0";
      "--auth-token";
      "s3cr3t";
      "--max-sessions";
      "42";
      "--idle-timeout";
      "60.5";
      "--insecure-allow-plaintext-external";
    |]
  in
  match Serve_cli.parse_argv argv with
  | Error msg -> fail (Printf.sprintf "expected Ok, got Error %s" msg)
  | Ok (cfg : Serve_config.t) ->
      check (option string) "app" (Some "octez-manager") cfg.app ;
      check int "port" 9999 cfg.port ;
      check string "bind" "0.0.0.0" cfg.bind ;
      check (option string) "auth_token" (Some "s3cr3t") cfg.auth_token ;
      check int "max_sessions" 42 cfg.max_sessions ;
      check (float 0.001) "idle_timeout" 60.5 cfg.idle_timeout ;
      check bool "insecure flag" true cfg.insecure_allow_plaintext_external

let test_defaults_when_no_flags () =
  match Serve_cli.parse_argv [|"miaou"|] with
  | Error msg -> fail (Printf.sprintf "expected Ok, got Error %s" msg)
  | Ok (cfg : Serve_config.t) ->
      check (option string) "app" None cfg.app ;
      check int "port" Serve_config.default.port cfg.port ;
      check string "bind" Serve_config.default.bind cfg.bind ;
      check (option string) "auth_token" None cfg.auth_token ;
      check
        bool
        "insecure flag defaults false"
        false
        cfg.insecure_allow_plaintext_external

let test_auth_file_roundtrip () =
  match
    Serve_cli.parse_argv [|"miaou"; "--auth-file"; "/etc/miaou/serve.token"|]
  with
  | Error msg -> fail (Printf.sprintf "expected Ok, got Error %s" msg)
  | Ok (cfg : Serve_config.t) ->
      check
        (option string)
        "auth_file"
        (Some "/etc/miaou/serve.token")
        cfg.auth_file ;
      check
        bool
        "has_auth is true from --auth-file alone (no --auth-token)"
        true
        (Serve_config.has_auth cfg)

let test_help_does_not_crash () =
  match Serve_cli.parse_argv [|"miaou"; "--help=plain"|] with
  | Error _ -> ()
  | Ok _ -> fail "expected --help to short-circuit parsing"

let () =
  run
    "serve_cli"
    [
      ( "flags",
        [
          test_case "round-trips all flags" `Quick test_roundtrip;
          test_case "defaults with no flags" `Quick test_defaults_when_no_flags;
          test_case "--auth-file round-trips" `Quick test_auth_file_roundtrip;
          test_case "--help short-circuits" `Quick test_help_does_not_crash;
        ] );
    ]
