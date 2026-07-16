(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Worker-side entry point (Slice 2 — process-per-session supervisor).

    A worker is a re-exec of [Sys.executable_name] running exactly
    today's single-global-controller {!Miaou_driver_web.Web_driver} code,
    unmodified, listening on a private Unix domain socket instead of a
    public TCP port. {!Serve_run} detects {!env_var} in the environment
    *before* starting Eio and dispatches here instead of the supervisor
    path — see [serve_run.mli] for the full app-side entry contract. *)

(** The environment variable {!Serve_run} checks to decide worker vs.
    supervisor mode. Its value, when set, is the Unix domain socket path
    the worker must listen on. *)
val env_var : string

(** [run ~socket_path page] starts this process as a worker: applies any
    {!Serve_rlimit.apply_from_env} resource limits (FR-072, first — before
    anything else runs), initializes
    the Eio/Fiber runtime (full {!Miaou_helpers.Fiber_runtime},
    {!Miaou_core.Registry}, {!Miaou_core.Modal_manager} — untouched,
    exactly as a directly-run app would use them), installs the
    stdin-EOF orphan guard (exits the process if its stdin pipe closes,
    which happens when the supervisor that spawned it dies — an orphaned
    worker's socket path is otherwise unreachable and unreapable), then
    serves [page] on the Unix domain socket at [socket_path] via
    {!Miaou_driver_web.Web_driver.run_on}. Blocks until the app quits. *)
val run : socket_path:string -> (module Miaou_core.Tui_page.PAGE_SIG) -> unit
