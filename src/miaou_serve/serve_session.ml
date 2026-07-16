(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

type role = Controller | Viewer

type worker_state =
  | Not_spawned
  | Spawning of (Serve_process.worker, string) result Eio.Promise.t
  | Spawned of Serve_process.worker

type t = {
  controller_token : Serve_token.t;
  viewer_token : Serve_token.t;
  socket_path : string;
  mutable worker_state : worker_state;
  mutable controller_live : bool;
  mutable last_activity : float;
      (** Set by {!controller_detach}; consulted by {!is_idle}. Initialized
          by {!create} to the session's own creation time (the caller's
          clock reading) rather than an unbounded sentinel — see
          {!create}'s doc comment for why: a session whose worker is
          spawned by a non-[/ws] request (e.g. a plain page fetch) before
          its controller ever completes the [/ws] upgrade must not look
          idle within seconds regardless of [--idle-timeout], but a
          session that spawns a worker and then *never* completes that
          upgrade must still eventually be reaped (the worker-leak
          backstop) — using the creation time as the initial baseline
          gives both: [now - last_activity] only exceeds [idle_timeout]
          once that much real time has actually elapsed since creation. *)
  mutable dead : bool;
      (** Set once by {!kill_worker_escalating} (FR-013); never reset —
          see {!is_dead}. *)
}

(* Regression (post-S7-review): a session whose worker is spawned by any
   controller-role request that needs forwarding — not only a [/ws]
   upgrade; {!Serve_proxy.resolve}'s [Controller] branch calls
   {!ensure_worker} unconditionally, so a plain [GET /] for the
   controller HTML already does this — used to initialize
   [last_activity] to [neg_infinity]. [controller_live] is only flipped
   [true] by the [/ws]-specific {!controller_attach}, so such a session
   satisfied {!is_idle} ([now -. neg_infinity > idle_timeout] is always
   true) from the very moment its worker became [Spawned], and could be
   killed by the very next idle-scan tick (every
   {!Serve_supervisor.idle_scan_interval_seconds}, a few seconds) —
   regardless of the configured [--idle-timeout]. A real browser's
   ordinary flow (page load, *then* the WS upgrade) could race this and
   lose. Seeding [last_activity] with [now] (the session's own creation
   time) instead fixes this: {!is_idle} then only fires once
   [idle_timeout] worth of real time has elapsed since creation, which
   is ample for a page load + WS upgrade, while still eventually
   reaping a worker whose controller never shows up at all (the
   worker-leak backstop this field exists for in the first place). *)
let create ~env ~socket_path ~now =
  let t =
    {
      controller_token = Serve_token.generate ~env ~role:Serve_token.Controller;
      viewer_token = Serve_token.generate ~env ~role:Serve_token.Viewer;
      socket_path;
      worker_state = Not_spawned;
      controller_live = false;
      last_activity = now;
      dead = false;
    }
  in
  (* FR-080: logged here, not by callers, so every session (production's
     one bootstrap session today; any future dynamic session-creation
     endpoint tomorrow) is audited uniformly regardless of call site. *)
  Serve_audit.log
    Serve_audit.Create
    ~token:(Serve_token.to_string t.controller_token) ;
  t

let controller_token_string t = Serve_token.to_string t.controller_token

let viewer_token_string t = Serve_token.to_string t.viewer_token

(* FR-031: both of [t]'s tokens are always compared, regardless of
   whether the first comparison already matched — avoids a
   same-session timing difference between "matched the controller
   token" (one Eqaf.equal call) and "matched neither" (two calls) that
   an early-exit [if ... else if ...] would otherwise introduce. *)
let match_role t ~candidate =
  let is_controller = Serve_token.matches t.controller_token ~candidate in
  let is_viewer = Serve_token.matches t.viewer_token ~candidate in
  if is_controller then Some Controller
  else if is_viewer then Some Viewer
  else None

type spawn_error = Unreachable

(* Reap unconditionally (FR-015 applies per-session, same as Slice 2):
   log the exit, best-effort remove just this worker's own socket file
   (never the shared session directory itself — other sessions' worker
   sockets may still live there; the whole directory is only removed at
   supervisor exit), and — critically — reset [t.worker_state] back to
   [Not_spawned] so a later [ensure_worker] call self-heals by spawning a
   fresh worker instead of forever returning this now-dead worker's
   socket path (which would otherwise make every future controller
   attach fail at the proxy's connect step with no way to recover). The
   physical-equality guard ([w == worker]) only resets the state if it
   still refers to *this* worker — guards against this stale callback
   clobbering a newer [Spawned] state in the (currently unreachable, but
   not worth relying on) case of overlapping spawn/reap cycles.

   S6 (FR-050): a worker that exited with
   {!Serve_worker.quit_exit_code} did so because the app itself reached a
   genuine terminal outcome (see [Web_driver.run_on]'s [on_session_end]
   hook, wired up in {!Serve_worker.run}) — not a crash. Unlike an
   ordinary crash-recovery reap (which self-heals: the next
   {!ensure_worker} call spawns a fresh worker for the very same token),
   a deliberate app-quit must be a dead end: [t] is marked permanently
   dead ({!is_dead}), same as an idle-timeout kill, so a reconnect
   attempt after quitting finds no session at all rather than silently
   landing on a brand-new page instance. *)
let reap_and_log t ~sw (worker : Serve_process.worker) =
  Serve_process.reap ~sw worker ~on_exit:(fun status ->
      Printf.eprintf
        "[miaou serve] worker pid=%d exited: %s\n%!"
        worker.Serve_process.pid
        (Serve_process.string_of_exit_status status) ;
      (try Sys.remove worker.Serve_process.socket_path with _ -> ()) ;
      (match status with
      | `Exited code when code = Serve_worker.quit_exit_code ->
          t.dead <- true ;
          Serve_audit.log
            Serve_audit.Session_end
            ~token:(Serve_token.to_string t.controller_token)
      | `Exited _ | `Signaled _ -> ()) ;
      match t.worker_state with
      | Spawned w when w == worker -> t.worker_state <- Not_spawned
      | Not_spawned | Spawning _ | Spawned _ -> ())

(* Spawns are serialized without any lock primitive: the check of
   [t.worker_state] and its transition to [Spawning promise] happen with
   no intervening Eio operation (no yield point), so two fibers cannot
   both observe [Not_spawned] and both proceed to spawn — this module
   runs entirely within the supervisor's single Eio domain. *)
let ensure_worker t ~sw ~proc_mgr ~net ~clock =
  match t.worker_state with
  | Spawned worker -> Ok worker.Serve_process.socket_path
  | Spawning promise -> (
      match Eio.Promise.await promise with
      | Ok worker -> Ok worker.Serve_process.socket_path
      | Error _ -> Error Unreachable)
  | Not_spawned ->
      let promise, resolver = Eio.Promise.create () in
      t.worker_state <- Spawning promise ;
      let worker =
        Serve_process.spawn_worker ~sw ~proc_mgr ~socket_path:t.socket_path ()
      in
      let ready =
        Serve_process.wait_ready
          ~sw
          ~net
          ~clock
          ~socket_path:t.socket_path
          ~retries:150
          ~delay:0.02
      in
      if ready then begin
        reap_and_log t ~sw worker ;
        t.worker_state <- Spawned worker ;
        Eio.Promise.resolve resolver (Ok worker) ;
        Ok worker.Serve_process.socket_path
      end
      else begin
        Serve_process.kill worker ;
        t.worker_state <- Not_spawned ;
        Eio.Promise.resolve resolver (Error "worker did not become reachable") ;
        Error Unreachable
      end

let worker_pid t =
  match t.worker_state with
  | Spawned worker -> Some worker.Serve_process.pid
  | Not_spawned | Spawning _ -> None

let has_worker t =
  match t.worker_state with
  | Spawned _ -> true
  | Not_spawned | Spawning _ -> false

let controller_attach t =
  if t.controller_live then `Downgrade
  else begin
    t.controller_live <- true ;
    `Attach
  end

let controller_detach t ~now =
  t.controller_live <- false ;
  t.last_activity <- now

let kill_worker t =
  (match t.worker_state with
  | Spawned worker -> Serve_process.kill worker
  | Not_spawned | Spawning _ -> ()) ;
  (* FR-014/FR-080: logged unconditionally (even the no-worker-yet
     no-op case) — the audited event is "an explicit kill was
     requested", not "a worker was actually terminated"; every call
     site (an operator-facing admin kill, and {!Serve_supervisor.run}'s
     graceful-shutdown drain, which reuses this same vocabulary) means
     exactly that. *)
  Serve_audit.log
    Serve_audit.Explicit_kill
    ~token:(Serve_token.to_string t.controller_token)

let is_dead t = t.dead

let is_idle t ~now ~idle_timeout =
  has_worker t && (not t.controller_live) && (not t.dead)
  && now -. t.last_activity > idle_timeout

let would_spawn t =
  match t.worker_state with
  | Not_spawned -> true
  | Spawning _ | Spawned _ -> false

(* Marking [t.dead] happens first, unconditionally, before anything else
   below runs — including before checking whether a worker even exists —
   so a session killed while [Not_spawned] (already reaped from a prior
   crash, or never spawned) is still permanently excluded from {!find}.
   No lock is needed for this ordering: the supervisor is single-domain
   (module-level invariant documented in Serve_supervisor), so there is
   no intervening Eio yield between setting [t.dead] and the SIGTERM
   send below that a concurrent attach could land inside. *)
let kill_worker_escalating t ~sw ~clock ~grace =
  t.dead <- true ;
  match t.worker_state with
  | Spawned worker ->
      Serve_process.kill worker (* SIGTERM *) ;
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Time.sleep clock grace ;
          match t.worker_state with
          | Spawned w when w == worker ->
              (* Still the same, not-yet-reaped worker after the grace
                 window: it did not act on SIGTERM in time. Escalate. *)
              w.Serve_process.signal Sys.sigkill
          | Not_spawned | Spawning _ | Spawned _ ->
              (* Already reaped (the ordinary case: the worker's default
                 SIGTERM disposition terminates it well within [grace]),
                 or — the currently-unreachable overlap case guarded
                 against elsewhere in this module — replaced by a
                 different [Spawned] worker. Either way, nothing to
                 escalate. *)
              ())
  | Not_spawned | Spawning _ -> ()

type table = {mutable sessions : t list}

let create_table () = {sessions = []}

let add table t = table.sessions <- t :: table.sessions

let to_list table = table.sessions

(* Counts a session as occupying a slot from the moment [ensure_worker]
   synchronously transitions it out of [Not_spawned] (i.e. [Spawning] or
   [Spawned]), not just once it reaches [Spawned] — that transition
   happens with no intervening Eio yield (see {!ensure_worker}'s own
   comment), so a racing [would_spawn]-gated check that runs after it is
   guaranteed to observe the updated count. Counting only [Spawned]
   (M1 fix) would leave a window, for the whole duration of one worker's
   spawn+ready-wait, during which a second concurrent first-attach could
   also pass the cap check and over-admit past [max_sessions] — a
   resource-limit bypass, not just a cosmetic undercount. *)
let count_spawned table =
  List.fold_left
    (fun acc t -> if not (would_spawn t) then acc + 1 else acc)
    0
    table.sessions

(* FR-031: every session in the table is scanned (via [List.fold_left],
   which never short-circuits), even after an earlier session's tokens
   already matched — [List.find_map]'s early exit would otherwise make a
   match near the front of [table.sessions] cost less work (and less
   wall-clock time) than a total miss or a match near the back, a table-
   position timing oracle on top of the uniform-miss guarantee
   {!match_role} itself already gives per-session. *)
let find table ~candidate =
  List.fold_left
    (fun acc t ->
      let hit =
        if t.dead then None
        else
          match match_role t ~candidate with
          | Some role -> Some (t, role)
          | None -> None
      in
      match acc with Some _ -> acc | None -> hit)
    None
    table.sessions

let reap_idle_sessions ~sw ~clock ~sessions ~idle_timeout ~grace ~now =
  List.iter
    (fun t ->
      if is_idle t ~now ~idle_timeout then begin
        (* FR-013/FR-080: logged here (not inside
           {!kill_worker_escalating} itself, which is also reused by
           {!Serve_supervisor.run}'s graceful-shutdown drain for an
           unrelated event) so this call site's own event name
           ([Idle_kill]) never leaks into that other reuse. *)
        Serve_audit.log
          Serve_audit.Idle_kill
          ~token:(Serve_token.to_string t.controller_token) ;
        kill_worker_escalating t ~sw ~clock ~grace
      end)
    (to_list sessions)
