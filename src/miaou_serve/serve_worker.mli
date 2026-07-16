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

(** The exit code {!run} uses when the app itself reaches a genuine
    terminal outcome (Quit / Back-to-empty-stack / SwitchTo-not-found —
    see {!Miaou_driver_web.Web_driver.run_on}'s [on_session_end]), as
    opposed to any other termination (a crash, a signal, an idle-timeout
    kill). {!Serve_session.reap_and_log} recognizes this specific code to
    mark the session permanently dead (FR-050: "reconnect-after-quit =
    dead token") rather than self-healing by spawning a fresh worker on
    the next attach — the distinction that lets a deliberate app-quit
    behave differently from an ordinary crash-and-recover. *)
val quit_exit_code : int

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
    {!Miaou_driver_web.Web_driver.run_on}.

    S6 (FR-050, reconnect): a controller WebSocket closing — cleanly or
    abruptly — no longer ends this call; {!Web_driver.run_on} parks that
    session instead (main loop and render domain keep running), and a
    later connection to the same socket's [/ws] reattaches to it, resuming
    the same in-process page/navigation state. This function only
    actually returns/exits once the app itself reaches a genuine terminal
    outcome, at which point it calls [exit quit_exit_code] — so, unlike
    pre-S6, [run] ends the whole process rather than looping to accept a
    fresh, unrelated controller session on the same socket. *)
val run : socket_path:string -> (module Miaou_core.Tui_page.PAGE_SIG) -> unit
