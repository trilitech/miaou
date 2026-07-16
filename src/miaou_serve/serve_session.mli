(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Multi-session state (Slice 3).

    A session couples a controller-role token with a viewer-role token
    (FR-032: role is bound to the token value at issuance, never
    self-selected by the client) and a worker process that is spawned
    lazily, on the first request that carries the session's controller
    token (FR-010) — not eagerly at session-creation time, unlike Slice
    2's single hardcoded session. Detaching the controller connection
    does not kill the worker (FR-012); it only clears the "a controller
    is currently live" flag consulted by {!controller_attach} for the
    FR-011 second-controller-becomes-viewer downgrade. *)

(** The role a matched token grants, mirroring {!Serve_token.role}. *)
type role = Controller | Viewer

type t

(** [create ~env ~socket_path] mints a fresh controller/viewer token pair
    (FR-030, FR-032) for a session whose worker — once spawned — will
    listen on [socket_path]. No worker is started yet. *)
val create :
  env:< secure_random : Eio.Flow.source_ty Eio.Resource.t ; .. > ->
  socket_path:string ->
  t

(** The controller token's string form, for building the session's
    printed attach URL ([/s/<token>/]). *)
val controller_token_string : t -> string

(** The viewer token's string form, for building the session's printed
    read-only attach URL — distinct from {!controller_token_string}
    (FR-032: a fully separate token, not a variant/derivation of the
    controller token). *)
val viewer_token_string : t -> string

(** [match_role t ~candidate] is [Some role] if [candidate] equals either
    of [t]'s two token strings (constant-time per {!Serve_token.matches}),
    identifying which role it grants; [None] if it matches neither. *)
val match_role : t -> candidate:string -> role option

(** Reason {!ensure_worker} failed to make the session's worker
    reachable. *)
type spawn_error = Unreachable

(** [ensure_worker t ~sw ~proc_mgr ~net ~clock] lazily spawns [t]'s worker
    process on the first call (FR-010), waiting (bounded) for it to
    become reachable on its private Unix socket; subsequent calls reuse
    the already-spawned worker without spawning again (FR-012 — the
    worker survives a detach). Concurrent first calls (two fibers racing
    to attach before any worker exists) are serialized so exactly one
    spawn happens; the others block on the same outcome. Reaping
    (zombie-free exit, socket-file cleanup, and resetting [t] back to
    "no worker" so a later call self-heals by spawning a fresh one
    instead of forever returning a dead worker's now-unreachable socket
    path) is wired up internally via {!Serve_process.reap}. Note this
    means a successful past call is not a durable guarantee: if the
    worker has since crashed and been reaped, the *next* call to
    [ensure_worker] spawns a brand new one rather than reporting failure
    — recovery, not just detection. *)
val ensure_worker :
  t ->
  sw:Eio.Switch.t ->
  proc_mgr:_ Eio.Process.mgr ->
  net:_ Eio.Net.t ->
  clock:_ Eio.Time.clock ->
  (string, spawn_error) result

(** The OS pid of [t]'s currently-spawned worker, if one exists right
    now ([None] both before the first spawn and after a worker has
    exited and been reaped — see {!ensure_worker}'s self-healing note).
    Exposed for tests that need to assert two sessions produced two
    distinct worker processes (the process-isolation proof). *)
val worker_pid : t -> int option

(** [true] iff [t] currently has a live, spawned worker record (i.e. a
    prior {!ensure_worker} call succeeded and that worker has not since
    exited/been reaped — reaping resets this back to [false], so this is
    "a worker exists right now", not "one ever existed"). Used by the
    proxy to distinguish "no worker currently exists for this session"
    (a viewer request must be refused — there is nothing to view) from
    "a worker exists" (a viewer may attach to it). *)
val has_worker : t -> bool

(** [controller_attach t] records a new controller-role connection
    attempt (FR-011): [`Attach] if no controller connection is currently
    live for [t] (this is the first, or a reconnect after a prior
    detach) — the caller should proceed to forward this connection to
    the worker's [/ws] controller endpoint unmodified. [`Downgrade] if a
    controller connection is already live — the caller must instead
    route this connection to the worker's [/ws/viewer] endpoint (the
    worker's own single-controller-slot 409 remains a backstop against
    any race). *)
val controller_attach : t -> [`Attach | `Downgrade]

(** [controller_detach t] clears the "a controller connection is live"
    flag (call this once the proxied byte-copy for an [`Attach]-ed
    controller connection ends, for any reason). Idempotent. *)
val controller_detach : t -> unit

(** [kill_worker t] sends [SIGTERM] to [t]'s worker (FR-014) if one has
    been spawned; a no-op otherwise. Does not wait for exit — the reaper
    installed by {!ensure_worker} observes it independently. *)
val kill_worker : t -> unit

(** A collection of sessions, looked up by token. *)
type table

val create_table : unit -> table

val add : table -> t -> unit

(** [find table ~candidate] returns the (session, role) pair whose
    controller or viewer token matches [candidate], scanning every
    session's both tokens with a constant-time compare per comparison
    (linear in the number of sessions, which {!Serve_config}'s
    [max_sessions] bounds) — [None] if no session's tokens match. *)
val find : table -> candidate:string -> (t * role) option
