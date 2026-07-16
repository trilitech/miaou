(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* [exception Bind_refused = Serve_supervisor.Bind_refused] re-exports the
   very same exception (not a new one) so existing callers matching
   [Miaou_serve.Bind_refused] (e.g. test_serve_auth_default.ml) keep
   working unchanged now that the fail-closed check lives in
   {!Serve_supervisor}, a leaf module {!Serve_run} depends on rather than
   the reverse. *)
exception Bind_refused = Serve_supervisor.Bind_refused

let run ?auth_token ?auth_file ?port ?bind ?max_sessions ?idle_timeout
    ?insecure_allow_plaintext_external
    (initial_page : (module Miaou_core.Tui_page.PAGE_SIG)) : unit =
  (* Entry contract (see .mli): this check MUST run before any Eio event
     loop starts, so a re-exec'd worker never pays for (or accidentally
     re-runs) supervisor setup, and a supervisor never pays for
     Fiber_runtime/Registry/Modal_manager initialization it must not
     touch. *)
  match Sys.getenv_opt Serve_worker.env_var with
  | Some socket_path -> Serve_worker.run ~socket_path initial_page
  | None ->
      Serve_supervisor.run
        ?auth_token
        ?auth_file
        ?port
        ?bind
        ?max_sessions
        ?idle_timeout
        ?insecure_allow_plaintext_external
        initial_page
