(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Cmdliner

let app_arg =
  let doc = "App name to serve, resolved via the page registry." in
  Arg.(value & opt (some string) None & info ["app"] ~docv:"NAME" ~doc)

let port_arg =
  let doc = "TCP port to listen on." in
  Arg.(
    value & opt int Serve_config.default.port & info ["port"] ~docv:"PORT" ~doc)

let bind_arg =
  let doc =
    "Address to bind to. Non-loopback requires an auth mechanism (fail-closed \
     default, FR-003)."
  in
  Arg.(
    value
    & opt string Serve_config.default.bind
    & info ["bind"] ~docv:"HOST" ~doc)

let auth_token_arg =
  let doc = "Shared secret that satisfies the fail-closed bind policy." in
  Arg.(value & opt (some string) None & info ["auth-token"] ~docv:"TOKEN" ~doc)

let auth_file_arg =
  let doc =
    "Path to a file containing the auth token (alternative to --auth-token)."
  in
  Arg.(value & opt (some string) None & info ["auth-file"] ~docv:"PATH" ~doc)

let max_sessions_arg =
  let doc = "Maximum number of concurrent sessions (FR-070)." in
  Arg.(
    value
    & opt int Serve_config.default.max_sessions
    & info ["max-sessions"] ~docv:"N" ~doc)

let idle_timeout_arg =
  let doc =
    "Idle timeout in seconds before an unattached session is killed (FR-013)."
  in
  Arg.(
    value
    & opt float Serve_config.default.idle_timeout
    & info ["idle-timeout"] ~docv:"SECONDS" ~doc)

let insecure_arg =
  let doc =
    "Acknowledge and accept binding a non-loopback address without a reverse \
     proxy/TLS (FR-060)."
  in
  Arg.(value & flag & info ["insecure-allow-plaintext-external"] ~doc)

let allowed_origin_arg =
  let doc =
    "Additional Origin value accepted at WebSocket upgrade (FR-045), beyond \
     the same-origin-as---bind default. Repeatable; needed when a reverse \
     proxy's public origin differs from --bind (e.g. TLS termination, a \
     different host/port)."
  in
  Arg.(value & opt_all string [] & info ["allowed-origin"] ~docv:"ORIGIN" ~doc)

let config_term =
  let build app port bind auth_token auth_file max_sessions idle_timeout
      insecure allowed_origins : Serve_config.t =
    {
      app;
      port;
      bind;
      auth_token;
      auth_file;
      max_sessions;
      idle_timeout;
      insecure_allow_plaintext_external = insecure;
      allowed_origins;
    }
  in
  Term.(
    const build $ app_arg $ port_arg $ bind_arg $ auth_token_arg $ auth_file_arg
    $ max_sessions_arg $ idle_timeout_arg $ insecure_arg $ allowed_origin_arg)

let serve_info =
  Cmd.info
    "serve"
    ~doc:"Serve a MIAOU app over HTTP/WebSocket (xterm.js in the browser)."

let parse_argv argv =
  let probe = Cmd.v serve_info config_term in
  match Cmd.eval_value ~argv probe with
  | Ok (`Ok config) -> Ok config
  | Ok `Help -> Error "help requested"
  | Ok `Version -> Error "version requested"
  | Error _ -> Error "invalid arguments"

let run_action (config : Serve_config.t) : unit =
  match config.app with
  | None -> Printf.eprintf "miaou serve: --app <name> is required\n%!"
  | Some name -> (
      match Miaou_core.Registry.find name with
      | None -> Printf.eprintf "miaou serve: no app registered as %S\n%!" name
      | Some page ->
          Serve_run.run
            ?auth_token:config.auth_token
            ?auth_file:config.auth_file
            ~port:config.port
            ~bind:config.bind
            ~max_sessions:config.max_sessions
            ~idle_timeout:config.idle_timeout
            ~insecure_allow_plaintext_external:
              config.insecure_allow_plaintext_external
            ~allowed_origins:config.allowed_origins
            page)

let cmd = Cmd.v serve_info Term.(const run_action $ config_term)
