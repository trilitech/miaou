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

(** [create ~env ~socket_path ~now] mints a fresh controller/viewer token
    pair (FR-030, FR-032) for a session whose worker — once spawned —
    will listen on [socket_path]. No worker is started yet. [now] (the
    caller's clock reading, e.g. [Eio.Time.now env#clock] in production
    or a fake clock's reading in a test — never read internally, so the
    clock stays fully injectable) seeds {!is_idle}'s last-activity
    baseline at creation time rather than an unbounded sentinel: a
    session whose worker is spawned by a non-[/ws] request before its
    controller completes the [/ws] upgrade must not look idle within
    seconds regardless of [--idle-timeout], but a session that never
    completes that upgrade at all must still eventually be reaped (see
    {!is_idle}'s doc comment for the full reasoning). Emits one
    {!Serve_audit.Create} audit line (FR-080), hashing the new
    controller token — never logging it raw. *)
val create :
  env:< secure_random : Eio.Flow.source_ty Eio.Resource.t ; .. > ->
  socket_path:string ->
  now:float ->
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

(** [controller_detach t ~now] clears the "a controller connection is
    live" flag (call this once the proxied byte-copy for an [`Attach]-ed
    controller connection ends, for any reason) and records [now] (the
    caller's clock reading, e.g. [Eio.Time.now env#clock] in production
    or a fake clock's reading in a test — never read internally, so the
    clock stays fully injectable per FR-013's test requirement) as [t]'s
    last-activity timestamp, consulted by {!is_idle}. Idempotent. *)
val controller_detach : t -> now:float -> unit

(** [kill_worker t] sends [SIGTERM] to [t]'s worker (FR-014) if one has
    been spawned; a no-op otherwise. Does not wait for exit — the reaper
    installed by {!ensure_worker} observes it independently. Unlike
    {!kill_worker_escalating}, this does not mark [t] dead: an
    operator-facing explicit kill (FR-014) is expected to be followed by
    an ordinary crash-recovery reap ({!ensure_worker} self-heals on the
    next attach), whereas an idle-timeout kill (FR-013) must not
    resurrect. Emits one {!Serve_audit.Explicit_kill} audit line
    (FR-080) unconditionally, even when there was no worker to signal —
    the audited event is "an explicit kill was requested", not "a
    worker was terminated". *)
val kill_worker : t -> unit

(** [true] iff [t] has been killed by {!kill_worker_escalating} (an
    idle-timeout reap, FR-013). Once dead, [t] is permanently excluded
    from {!find} — its tokens never match again, even though the token
    values themselves are unchanged in memory (FR-013/US-4 scenario 2:
    "a dead token must never resurrect"). There is no path back from
    [true] to [false]. *)
val is_dead : t -> bool

(** [is_idle t ~now ~idle_timeout] is [true] iff [t] currently has a
    spawned worker, no controller is currently attached, [t] is not
    already {!is_dead}, and more than [idle_timeout] seconds have
    elapsed (per the caller's [now]) since the last {!controller_detach}
    call, {b or}, if no {!controller_detach} has ever happened yet,
    since {!create} was called — the FR-013 idle-reap predicate. A
    session with no worker yet, with a live controller, or already dead,
    is never idle regardless of how much time has passed — the
    [not (is_dead t)] guard specifically stops a scan from re-issuing
    [SIGTERM] and forking a second escalation fiber against a session
    whose reap is already in flight (a slow-dying worker would otherwise
    be re-killed on every subsequent scan pass until it finally exits).

    The "or since {!create}" half matters because a worker can be
    spawned by *any* controller-role request that needs forwarding, not
    only a [/ws] upgrade ({!Serve_proxy.resolve}'s [Controller] branch
    calls {!ensure_worker} unconditionally) — so a plain page fetch,
    before the browser's WS upgrade even starts, already has
    [has_worker t = true] while [controller_live] is still [false]
    (only the [/ws]-specific {!controller_attach} sets it). Using
    {!create}'s own [~now] as the pre-attach baseline (instead of an
    unbounded sentinel) means such a session is not idle-eligible until
    a full [idle_timeout] has elapsed since its own creation — ample for
    an ordinary page-load-then-upgrade flow — while a session whose
    controller never shows up at all is still eventually reaped (the
    worker-leak backstop this predicate exists for). *)
val is_idle : t -> now:float -> idle_timeout:float -> bool

(** [true] iff [t] currently has no spawned worker (a fresh session, or
    one whose worker has since exited/been reaped) — the next
    {!ensure_worker} call on [t] would spawn a brand new worker process,
    which is the FR-070 resource-consumption event [max_sessions] must
    bound. A session whose worker is already [Spawned] (or mid-[Spawning])
    costs nothing new to keep serving, so it is never itself refused by
    the cap. *)
val would_spawn : t -> bool

(** [kill_worker_escalating t ~sw ~clock ~grace] is the FR-013
    idle-timeout reap: marks [t] permanently dead ({!is_dead}) *before*
    sending anything, so no concurrent attach can race in ahead of the
    kill (both run in the supervisor's single Eio domain, so this
    ordering is deterministic, not merely likely); sends [t]'s worker
    [SIGTERM] (a no-op if no worker is spawned); then, on [clock] (fully
    injectable — a test can use a mock clock and step it directly rather
    than sleeping in real time), forks a fiber that waits [grace] seconds
    and sends [SIGKILL] only if the worker is still the same, not-yet-reaped
    process at that point (a worker that already exited during the grace
    window — the ordinary case — is left alone; {!ensure_worker}'s
    installed reap callback independently observes and logs the actual
    exit either way). Does not itself unlink the socket file or wait for
    exit — {!ensure_worker}'s reap callback does both, unconditionally,
    for any exit reason. *)
val kill_worker_escalating :
  t -> sw:Eio.Switch.t -> clock:_ Eio.Time.clock -> grace:float -> unit

(** A collection of sessions, looked up by token. *)
type table

val create_table : unit -> table

val add : table -> t -> unit

(** Every session currently in [table], in unspecified order. Exposed so
    the supervisor's idle-reap scan ({!reap_idle_sessions}, or a caller
    building its own scan loop) can iterate without [table]'s
    representation being otherwise public. *)
val to_list : table -> t list

(** The number of sessions in [table] currently occupying a slot — i.e.
    [not (would_spawn t)], true from the moment {!ensure_worker}
    synchronously transitions a session out of [Not_spawned] (into
    [Spawning] or [Spawned]), not only once it reaches [Spawned] — the
    live count {!would_spawn}-gated call sites compare against
    [max_sessions] (FR-070). Counting only [Spawned] would leave a
    window, for a whole spawn+ready-wait duration, during which a second
    concurrent first-attach could also pass the cap check and over-admit
    past [max_sessions]; since that [Not_spawned -> Spawning] transition
    happens with no intervening Eio yield, a racing check that runs
    after it is guaranteed to observe the updated count (no lock
    needed). Linear in the number of sessions, which [max_sessions]
    itself bounds. *)
val count_spawned : table -> int

(** [find table ~candidate] returns the (session, role) pair whose
    controller or viewer token matches [candidate], scanning every
    session's both tokens with a constant-time compare per comparison
    (linear in the number of sessions, which {!Serve_config}'s
    [max_sessions] bounds) — [None] if no session's tokens match, {b and}
    [None] for a session that {!is_dead} even if its token strings still
    match (FR-013's "dead token never resurrects" guarantee is enforced
    here, the single chokepoint every attach request passes through). *)
val find : table -> candidate:string -> (t * role) option

(** [reap_idle_sessions ~sw ~clock ~sessions ~idle_timeout ~grace ~now]
    scans every session in [sessions] ({!to_list}) and calls
    {!kill_worker_escalating} on each one for which {!is_idle} (using
    [now] and [idle_timeout]) is [true]. [now] and [clock] are both
    caller-supplied so this is fully driveable by a fake clock in tests
    (no real sleeping required to prove an idle session gets reaped) —
    production callers pass [Eio.Time.now env#clock] and [env#clock].
    Emits one {!Serve_audit.Idle_kill} audit line (FR-080) per session
    reaped this way. *)
val reap_idle_sessions :
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.clock ->
  sessions:table ->
  idle_timeout:float ->
  grace:float ->
  now:float ->
  unit
