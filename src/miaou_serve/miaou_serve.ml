(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Dune's library-wrapping rule requires the module sharing the library's
   name to be the one thing every other module may be depended on by, never
   the reverse — so [run] itself lives in [Serve_run] (a leaf module
   [Serve_cli] can depend on) and is re-exported here via [include].
   Sibling modules are re-exported as aliases so callers/tests can still
   reach [Miaou_serve.Serve_token], etc. directly, matching how
   [Miaou_driver_web] exposes [Web_driver]/[Web_websocket]. *)
include Serve_run
module Serve_token = Serve_token
module Serve_policy = Serve_policy
module Serve_config = Serve_config
module Serve_cli = Serve_cli
module Serve_rlimit = Serve_rlimit
module Serve_worker = Serve_worker
module Serve_process = Serve_process
module Serve_session = Serve_session
module Serve_origin = Serve_origin
module Serve_supervisor = Serve_supervisor
module Serve_proxy = Serve_proxy
