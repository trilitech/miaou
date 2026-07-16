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
      (** Set by {!controller_detach}; consulted by {!is_idle}. Its
          initial value ([neg_infinity]) is never itself observable as
          "idle", since {!is_idle} also requires [not controller_live]
          — true only after at least one attach+detach cycle — so a
          brand new session can never be idle-reaped before its first
          detach regardless of this placeholder. *)
  mutable dead : bool;
      (** Set once by {!kill_worker_escalating} (FR-013); never reset —
          see {!is_dead}. *)
}

let create ~env ~socket_path =
  {
    controller_token = Serve_token.generate ~env ~role:Serve_token.Controller;
    viewer_token = Serve_token.generate ~env ~role:Serve_token.Viewer;
    socket_path;
    worker_state = Not_spawned;
    controller_live = false;
    last_activity = neg_infinity;
    dead = false;
  }

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
   not worth relying on) case of overlapping spawn/reap cycles. *)
let reap_and_log t ~sw (worker : Serve_process.worker) =
  Serve_process.reap ~sw worker ~on_exit:(fun status ->
      Printf.eprintf
        "[miaou serve] worker pid=%d exited: %s\n%!"
        worker.Serve_process.pid
        (Serve_process.string_of_exit_status status) ;
      (try Sys.remove worker.Serve_process.socket_path with _ -> ()) ;
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
  match t.worker_state with
  | Spawned worker -> Serve_process.kill worker
  | Not_spawned | Spawning _ -> ()

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
      if is_idle t ~now ~idle_timeout then
        kill_worker_escalating t ~sw ~clock ~grace)
    (to_list sessions)
