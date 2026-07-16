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

(** Per-worker OS resource limits (FR-072) — exposed so a test can drive
    {!Serve_rlimit.apply_from_env} or inspect its environment-variable
    names directly. *)
module Serve_rlimit = Serve_rlimit

(** The worker half of Slice 2's process-per-session supervisor — see
    {!Serve_run}'s entry contract documentation. Exposed for the named
    session-lifecycle test to drive worker startup directly. *)
module Serve_worker = Serve_worker

(** Worker-process mechanics (spawn/reap/kill, socket-directory
    lifecycle) shared by {!Serve_session} and {!Serve_supervisor}. *)
module Serve_process = Serve_process

(** Multi-session state (Slice 3): the session table keyed by
    controller/viewer token pairs, lazy per-session worker spawn, and
    the FR-011 second-controller-becomes-viewer downgrade. Exposed for
    the named multi-session isolation and viewer-readonly tests, which
    build a session table directly and drive
    {!Serve_supervisor.accept_loop} against it. *)
module Serve_session = Serve_session

(** The supervisor half of Slice 2/3 — see {!Serve_run}'s entry contract
    documentation. Exposed for the named session-lifecycle,
    multi-session, and viewer-readonly tests (spawn/kill/reap,
    {!Serve_supervisor.accept_loop}) and for advanced embedders that want
    the supervisor's primitives directly rather than through {!run}. *)
module Serve_supervisor = Serve_supervisor

(** The supervisor's byte proxy — exposed so its pure path-splitting
    logic ({!Serve_proxy.split_session_path}) can be unit-tested without
    opening any sockets. *)
module Serve_proxy = Serve_proxy
