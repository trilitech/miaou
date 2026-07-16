(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** The [miaou serve] supervisor (Slice 2).

    The supervisor is a plain-Eio process: it MUST NOT call
    {!Miaou_helpers.Fiber_runtime.init} or otherwise touch
    {!Miaou_core.Registry}/{!Miaou_core.Modal_manager} — those globals
    belong entirely to the worker's app instance. This is a structural
    invariant (per the binding design), not just a style preference: the
    supervisor owns the public listener and spawns/reaps worker
    processes; a worker owns exactly one app instance's global state, in
    its own address space, by OS process isolation. Nothing in this
    module spawns an OS thread {!Domain.spawn} either — the supervisor is
    single-domain by construction. *)

(** Raised when {!run} refuses the requested bind (FR-003) — the same
    exception previously defined by {!Miaou_serve.Serve_run}; re-exported
    there via [exception Bind_refused = Serve_supervisor.Bind_refused] so
    existing callers matching [Miaou_serve.Bind_refused] are unaffected. *)
exception Bind_refused of string

(** [socket_dir ~pid] is [$XDG_RUNTIME_DIR/miaou-serve-<pid>/] (falling
    back to a temp directory if [XDG_RUNTIME_DIR] is unset — documented,
    not silently wrong: the fallback is still a private per-process
    directory, just not under the XDG runtime root). Does not create the
    directory — see {!ensure_socket_dir}. *)
val socket_dir : pid:int -> string

(** [ensure_socket_dir dir] creates [dir] with mode [0o700] if it does
    not already exist. If [dir] already exists (expected only when a
    recycled pid collides with a stale leftover), it is reused only
    after verifying it is a real directory owned by the current user —
    not a symlink, not another user's directory — otherwise this raises
    rather than silently chmod'ing and reusing a foreign path (relevant
    on the shared, world-writable [$TMPDIR] fallback used when
    [$XDG_RUNTIME_DIR] is unset). Idempotent on repeated calls that pass
    this check. *)
val ensure_socket_dir : string -> unit

(** A supervised worker process. Fields are exposed (not abstracted)
    because tests need [pid] to simulate an external crash
    ([Unix.kill pid Sys.sigkill], the FR-015 "kill -9 a worker directly"
    scenario) and [socket_path] to attempt direct connections. *)
type worker = {
  pid : int;
  socket_path : string;
  await : unit -> Eio.Process.exit_status;
      (** Blocks until the worker exits and reports how. Calling this
          performs the actual [waitpid]-equivalent reap; {!reap} wraps it
          in a background fiber so a caller doesn't have to block
          inline. *)
  signal : int -> unit;  (** Send a Unix signal number to the worker. *)
}

(** [spawn_worker ~sw ~proc_mgr ~socket_path ()] re-execs
    [Sys.executable_name] with [Sys.argv] unchanged plus {!Serve_worker.env_var}
    set to [socket_path] in the child's environment — the worker's own
    [main] must therefore be idempotent up to the point it calls
    {!Miaou_serve.run} (see [serve_run.mli]'s entry contract). The child's
    stdin is the read end of a fresh pipe whose write end is held open by
    [sw]; when [sw] finishes (supervisor exit, crash, or explicit
    release), the write end closes and the worker's own stdin-EOF orphan
    guard ({!Serve_worker.watch_stdin_orphan_guard}) exits it — a
    worker's socket path is otherwise unreachable and unreapable once its
    supervisor is gone. Never uses [Unix.fork] directly (would fork the
    whole multi-domain runtime); always {!Eio.Process.spawn}. *)
val spawn_worker :
  sw:Eio.Switch.t ->
  proc_mgr:_ Eio.Process.mgr ->
  socket_path:string ->
  unit ->
  worker

(** [wait_ready ~sw ~net ~clock ~socket_path ~retries ~delay] attempts to
    connect to [socket_path] up to [retries] times, sleeping [delay]
    seconds between attempts (a worker takes a little time to bind after
    spawn). Returns [true] on the first successful connect (closed
    immediately — this is only a readiness probe), [false] if every
    attempt failed. Bounded: never retries forever. *)
val wait_ready :
  sw:Eio.Switch.t ->
  net:_ Eio.Net.t ->
  clock:_ Eio.Time.clock ->
  socket_path:string ->
  retries:int ->
  delay:float ->
  bool

(** [reap ~sw worker ~on_exit] forks a fiber on [sw] that blocks on
    [worker.await] and calls [on_exit] with the resulting status. This is
    the supervisor's zombie-reaping mechanism (FR-015): it runs
    unconditionally after {!spawn_worker}, independent of whether a proxy
    connection to the worker is currently open, so a worker that crashes,
    is killed, or exits cleanly is always reaped. *)
val reap :
  sw:Eio.Switch.t -> worker -> on_exit:(Eio.Process.exit_status -> unit) -> unit

(** [kill worker] sends [SIGTERM] to [worker] (FR-014's minimum
    operator-facing explicit-kill admin surface — the production {!run}
    also installs a supervisor-level [SIGTERM] handler that calls this on
    its single current worker). Does not itself wait for exit; combine
    with a {!reap}'d [on_exit] callback to observe completion. *)
val kill : worker -> unit

(** [accept_loop ~sw ~env ~sessions ~max_sessions listening] forks
    {!Serve_proxy.handle_connection} for each connection accepted on
    [listening], dispatched against [sessions] (Slice 3's session table)
    rather than a single hardcoded token, with [max_sessions] enforced
    per-connection (FR-070). Never returns on its own (loops until [sw]
    is cancelled). Exposed so a test can drive the same production
    routing/role-enforcement path against a session table it builds
    directly (e.g. two sessions, to prove process isolation), without
    going through {!run}'s single-bootstrap-session convenience wrapper. *)
val accept_loop :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  sessions:Serve_session.table ->
  max_sessions:int ->
  _ Eio.Net.listening_socket ->
  'a

(** Grace period (seconds) between an idle-timeout kill's [SIGTERM] and
    its [SIGKILL] escalation ({!Serve_session.kill_worker_escalating}).
    A worker's default signal disposition terminates it on [SIGTERM]
    alone, well within this window; the escalation exists only for a
    worker that is somehow ignoring or slow to act on [SIGTERM]. *)
val idle_kill_grace_seconds : float

(** How often (seconds) {!run}'s background fiber re-scans the session
    table for idle sessions ({!Serve_session.reap_idle_sessions}). A
    fixed, short interval regardless of [idle_timeout]: the scan itself
    is a cheap linear pass bounded by [max_sessions], so scanning far
    more often than the (typically minutes-scale) idle timeout costs
    little and keeps reap latency low and independent of the configured
    timeout's own magnitude. *)
val idle_scan_interval_seconds : float

(** [run ?auth_token ?auth_file ?port ?bind ?max_sessions ?idle_timeout
    ?insecure_allow_plaintext_external page] is the supervisor entry
    point: enforces the fail-closed bind policy (FR-003), creates the
    [0700] socket directory, builds a session table (Slice 3) seeded with
    one bootstrap session — its controller/viewer token pair generated
    up front (FR-030/FR-032), its worker spawned lazily on first
    controller-role request rather than eagerly ({!Serve_session.ensure_worker},
    FR-010) — prints the [/s/<token>/] session URL, and serves the public
    TCP listener as a byte proxy ({!accept_loop}) until the process is
    signaled to stop. As of Slice 4, [max_sessions] is enforced by
    {!accept_loop} on every connection (FR-070) and [idle_timeout] is
    enforced by a background fiber that periodically calls
    {!Serve_session.reap_idle_sessions} (FR-013). *)
val run :
  ?auth_token:string ->
  ?auth_file:string ->
  ?port:int ->
  ?bind:string ->
  ?max_sessions:int ->
  ?idle_timeout:float ->
  ?insecure_allow_plaintext_external:bool ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  unit
