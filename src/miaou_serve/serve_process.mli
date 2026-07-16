(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Worker-process mechanics shared by {!Serve_session} (per-session lazy
    spawn) and {!Serve_supervisor} (the bootstrap session, socket
    directory lifecycle, signal handling). Split out as its own leaf
    module so both can depend on it without a dependency cycle between
    them (a session needs to spawn/reap a worker; the supervisor needs to
    build a session table) — this module itself depends on neither.

    Plain-Eio module: no {!Miaou_helpers.Fiber_runtime}, no
    {!Miaou_core.Registry}/{!Miaou_core.Modal_manager}, no
    [Domain.spawn] — those globals belong entirely to a worker's own app
    instance, in its own process. *)

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

(** Best-effort startup hygiene: sweeps [miaou-serve-<pid>/] directories
    under {!socket_dir}'s root left behind by earlier supervisor
    invocations that were killed abruptly (their pid is no longer alive).
    Never raises. *)
val sweep_stale_dirs : unit -> unit

(** [cleanup_dir ~dir ()] best-effort removes every file inside [dir]
    (every session's worker socket file that may still exist there) and
    then [dir] itself. Never raises. *)
val cleanup_dir : dir:string -> unit -> unit

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
    the zombie-reaping mechanism (FR-015): it should run unconditionally
    right after {!spawn_worker}, independent of whether a proxy
    connection to the worker is currently open, so a worker that crashes,
    is killed, or exits cleanly is always reaped. *)
val reap :
  sw:Eio.Switch.t -> worker -> on_exit:(Eio.Process.exit_status -> unit) -> unit

(** [kill worker] sends [SIGTERM] to [worker] (FR-014's minimum
    operator-facing explicit-kill admin surface). Does not itself wait
    for exit; combine with a {!reap}'d [on_exit] callback to observe
    completion. *)
val kill : worker -> unit

(** Renders an {!Eio.Process.exit_status} for a log line. *)
val string_of_exit_status : Eio.Process.exit_status -> string

(** ["localhost"] must resolve the same way {!Serve_policy.is_loopback}
    already treats it (already-trusted, no auth required) — otherwise
    [--bind localhost] would pass the fail-closed check and then crash
    with an uncaught [Failure] the moment we try to actually bind it,
    since {!Unix.inet_addr_of_string} only accepts numeric IP literals.
    Any other non-numeric host is a genuine usage error and still fails,
    but with a clear message. *)
val ipaddr_of_host : string -> Eio.Net.Ipaddr.v4v6

(** ["0.0.0.0"] (all interfaces) is not itself a usable client-facing
    address — resolves to a loopback address a browser can actually
    connect to instead of an address that only makes sense as a bind
    target. *)
val display_host : string -> string

(** Set by {!install_signal_handler}'s [SIGTERM]/[SIGINT] handler;
    polled by a fiber rather than acted on directly inside the signal
    handler (running arbitrary Eio operations from inside a raw signal
    handler is not something this module relies on being safe). *)
val stop_requested : bool Atomic.t

(** Installs a [SIGTERM]/[SIGINT] handler that sets {!stop_requested}. *)
val install_signal_handler : unit -> unit
