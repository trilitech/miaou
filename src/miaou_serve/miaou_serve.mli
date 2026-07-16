(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Library entry point — re-exports {!Serve_run} (the [run] function and
    [Bind_refused] exception) plus the library's other public modules.
    See {!Serve_run} for the full entry-contract documentation (binding
    design decisions). *)

include module type of Serve_run

module Serve_token = Serve_token
module Serve_policy = Serve_policy
module Serve_config = Serve_config
module Serve_cli = Serve_cli

(** The worker half of Slice 2's process-per-session supervisor — see
    {!Serve_run}'s entry contract documentation. Exposed for the named
    session-lifecycle test to drive worker startup directly. *)
module Serve_worker = Serve_worker

(** The supervisor half of Slice 2 — see {!Serve_run}'s entry contract
    documentation. Exposed for the named session-lifecycle test
    (spawn/kill/reap) and for advanced embedders that want the
    supervisor's primitives directly rather than through {!run}. *)
module Serve_supervisor = Serve_supervisor

(** The supervisor's byte proxy — exposed so its pure path/token rewrite
    logic ({!Serve_proxy.strip_session_prefix}) can be unit-tested
    without opening any sockets. *)
module Serve_proxy = Serve_proxy
