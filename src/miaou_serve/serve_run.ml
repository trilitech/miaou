(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

module Fibers = Miaou_helpers.Fiber_runtime

exception Bind_refused of string

let run ?auth_token ?auth_file ?(port = Serve_config.default.port)
    ?(bind = Serve_config.default.bind)
    ?(max_sessions = Serve_config.default.max_sessions)
    ?(idle_timeout = Serve_config.default.idle_timeout)
    ?(insecure_allow_plaintext_external = false)
    (initial_page : (module Miaou_core.Tui_page.PAGE_SIG)) : unit =
  let has_auth = Option.is_some auth_token || Option.is_some auth_file in
  (match
     Serve_policy.check ~bind ~has_auth ~insecure_allow_plaintext_external
   with
  | Ok () -> ()
  | Error refusal -> raise (Bind_refused (Serve_policy.refusal_message refusal))) ;
  if insecure_allow_plaintext_external then
    Printf.eprintf
      "[miaou serve] WARNING: --insecure-allow-plaintext-external set; binding \
       %s without a reverse proxy. See docs/serve.md.\n\
       %!"
      bind ;
  Printf.eprintf
    "[miaou serve] max_sessions=%d idle_timeout=%.0fs (Slice 1: single worker, \
     both values recorded but not yet enforced — Slice 4 wires limits/timeout)\n\
     %!"
    max_sessions
    idle_timeout ;
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Fibers.init ~env ~sw ;
  let token = Serve_token.generate ~env ~role:Serve_token.Controller in
  let token_str = Serve_token.to_string token in
  (* Interim bridge (see .mli): reuse Web_driver's query-param password
     mechanism as the token carrier until Slice 2's [run_on] seam lands
     path-based [/s/<token>] routing. *)
  let url = Printf.sprintf "http://%s:%d/?password=%s" bind port token_str in
  Printf.eprintf "[miaou serve] session ready: %s\n%!" url ;
  let auth =
    Miaou_driver_web.Web_driver.
      {controller_password = Some token_str; viewer_password = None}
  in
  ignore
    (Miaou_driver_web.Web_driver.run ~port ~auth initial_page
      : [`Quit | `Back | `SwitchTo of string])
