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
}

let create ~env ~socket_path =
  {
    controller_token = Serve_token.generate ~env ~role:Serve_token.Controller;
    viewer_token = Serve_token.generate ~env ~role:Serve_token.Viewer;
    socket_path;
    worker_state = Not_spawned;
    controller_live = false;
  }

let controller_token_string t = Serve_token.to_string t.controller_token

let viewer_token_string t = Serve_token.to_string t.viewer_token

let match_role t ~candidate =
  if Serve_token.matches t.controller_token ~candidate then Some Controller
  else if Serve_token.matches t.viewer_token ~candidate then Some Viewer
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

let controller_detach t = t.controller_live <- false

let kill_worker t =
  match t.worker_state with
  | Spawned worker -> Serve_process.kill worker
  | Not_spawned | Spawning _ -> ()

type table = {mutable sessions : t list}

let create_table () = {sessions = []}

let add table t = table.sessions <- t :: table.sessions

let find table ~candidate =
  List.find_map
    (fun t ->
      match match_role t ~candidate with
      | Some role -> Some (t, role)
      | None -> None)
    table.sessions
