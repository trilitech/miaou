(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Plain-Eio module: no Miaou_helpers.Fiber_runtime, no Miaou_core.Registry,
   no Miaou_core.Modal_manager, no Domain.spawn. Single-domain by
   construction — this is the supervisor half of the process-per-session
   design; the worker (Serve_worker) is where the full app runtime lives.
   Worker-process mechanics (spawn/reap/kill, socket-directory lifecycle)
   live in the leaf module {!Serve_process}, re-exported below unchanged
   so existing callers (including tests) matching [Serve_supervisor.*]
   are unaffected by {!Serve_session} also needing those same primitives
   (a session/supervisor dependency cycle would otherwise result, since
   the supervisor's [run] also builds a {!Serve_session.table}). *)

exception Bind_refused of string

let socket_dir = Serve_process.socket_dir

let ensure_socket_dir = Serve_process.ensure_socket_dir

type worker = Serve_process.worker = {
  pid : int;
  socket_path : string;
  await : unit -> Eio.Process.exit_status;
  signal : int -> unit;
}

let spawn_worker = Serve_process.spawn_worker

let wait_ready = Serve_process.wait_ready

let reap = Serve_process.reap

let kill = Serve_process.kill

(* Shared accept loop (Slice 3): forks {!Serve_proxy.handle_connection}
   per accepted connection against [sessions], routed and role-checked by
   the session table rather than a single hardcoded token. Exposed
   ({!accept_loop}) so tests can drive the same production dispatch path
   against a session table they build themselves (e.g. the multi-session
   isolation test), rather than duplicating routing logic.

   FR-090: this is also the mechanism that stops accepting new
   connections during graceful shutdown. [run] closes [listening] once
   it observes {!Serve_process.stop_requested}; a pending
   [Eio.Net.accept] on a closed listening socket raises, which this loop
   catches — if [stop_requested] is set, that is the expected shutdown
   signal, and the loop simply returns instead of re-raising or looping
   again; any *other* accept failure (a genuine, unrelated I/O error)
   still propagates, unchanged from pre-S7 behavior. *)
let rec accept_loop ~sw ~env ~sessions ~max_sessions ~allowed_origins listening
    =
  match Eio.Net.accept ~sw listening with
  | conn, _addr ->
      Eio.Fiber.fork ~sw (fun () ->
          Serve_proxy.handle_connection
            ~sw
            ~env
            ~sessions
            ~max_sessions
            ~allowed_origins
            ~conn) ;
      accept_loop ~sw ~env ~sessions ~max_sessions ~allowed_origins listening
  | exception exn ->
      if Atomic.get Serve_process.stop_requested then () else raise exn

let idle_kill_grace_seconds = 5.0

let idle_scan_interval_seconds = 5.0

let run ?auth_token ?auth_file ?(port = Serve_config.default.port)
    ?(bind = Serve_config.default.bind)
    ?(max_sessions = Serve_config.default.max_sessions)
    ?(idle_timeout = Serve_config.default.idle_timeout)
    ?(insecure_allow_plaintext_external = false)
    ?(allowed_origins = Serve_config.default.allowed_origins)
    (_page : (module Miaou_core.Tui_page.PAGE_SIG)) : unit =
  (* [_page] is accepted (not used directly): the supervisor never runs
     an app instance itself. It exists only so {!Serve_run.run}'s
     signature is uniform across the worker/supervisor branches — the
     worker re-exec, running the very same host [main] a second time,
     is what actually threads [_page] into {!Serve_worker.run}. *)
  let has_auth = Option.is_some auth_token || Option.is_some auth_file in
  (match
     Serve_policy.check ~bind ~has_auth ~insecure_allow_plaintext_external
   with
  | Ok () -> ()
  | Error refusal -> raise (Bind_refused (Serve_policy.refusal_message refusal))) ;
  if insecure_allow_plaintext_external then
    Printf.eprintf
      "[miaou serve] WARNING: --insecure-allow-plaintext-external set; binding \
       %s without a reverse proxy. See docs/serve.md.\n\
       %!"
      bind ;
  Printf.eprintf
    "[miaou serve] max_sessions=%d idle_timeout=%.0fs (both enforced)\n%!"
    max_sessions
    idle_timeout ;
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let pid = Unix.getpid () in
  Serve_process.sweep_stale_dirs () ;
  let dir = Serve_process.socket_dir ~pid in
  Serve_process.ensure_socket_dir dir ;
  (* Last-resort net: covers any exit path that doesn't go through the
     explicit cleanup calls below (an uncaught exception unwinding out
     of [Eio_main.run], for instance). [Stdlib.exit] — including the one
     called by the runtime's own uncaught-exception handler — always
     runs [at_exit] callbacks; only a raw signal kill of *this* process
     (not any worker) would skip it, which is why each worker's own
     reap callback (installed inside {!Serve_session.ensure_worker})
     also cleans up its own socket file independently of this. *)
  at_exit (Serve_process.cleanup_dir ~dir) ;
  (* Slice 3 still prints exactly one session URL at startup (an
     unchanged UX from Slice 2), but the session table itself is a
     general structure that can — and, in the multi-session isolation
     test, does — hold more than one entry; this bootstrap session's
     worker is not spawned here, only on its first controller-role
     request ({!Serve_session.ensure_worker}, FR-010). *)
  let sessions = Serve_session.create_table () in
  let bootstrap_session =
    Serve_session.create
      ~env
      ~socket_path:(Filename.concat dir "worker-0.sock")
      ~now:(Eio.Time.now env#clock)
  in
  Serve_session.add sessions bootstrap_session ;
  let session_url token =
    Printf.sprintf
      "http://%s:%d/s/%s/"
      (Serve_process.display_host bind)
      port
      token
  in
  let url =
    session_url (Serve_session.controller_token_string bootstrap_session)
  in
  let viewer_url =
    session_url (Serve_session.viewer_token_string bootstrap_session)
  in
  Printf.eprintf "[miaou serve] session ready: %s\n%!" url ;
  Printf.eprintf "[miaou serve] read-only viewer link: %s\n%!" viewer_url ;
  Serve_process.install_signal_handler () ;
  let listen_addr = `Tcp (Serve_process.ipaddr_of_host bind, port) in
  let listening =
    Eio.Net.listen env#net ~sw ~reuse_addr:true ~backlog:16 listen_addr
  in
  (* FR-090 (graceful shutdown): stop accepting new connections first —
     closing [listening] makes {!accept_loop}'s pending [Eio.Net.accept]
     raise, and it checks {!Serve_process.stop_requested} and returns
     instead of looping again (see {!accept_loop}'s own doc comment) —
     then drain every currently-known session's worker with a bounded
     grace period before escalating to [SIGKILL]
     ({!Serve_session.kill_worker_escalating}, the same FR-013
     idle-timeout mechanism, reused here for its identical
     grace-then-escalate shape), waiting until every worker has actually
     been reaped (not merely signaled) before removing the socket
     directory and exiting — so no worker ever outlives its supervisor. *)
  Eio.Fiber.fork ~sw (fun () ->
      let rec watch () =
        if Atomic.get Serve_process.stop_requested then begin
          let live_sessions =
            List.filter
              Serve_session.has_worker
              (Serve_session.to_list sessions)
          in
          Printf.eprintf
            "[miaou serve] shutdown requested: draining %d session(s)\n%!"
            (List.length live_sessions) ;
          (try Eio.Net.close listening with _ -> ()) ;
          List.iter
            (fun s ->
              (* FR-080: a shutdown-triggered drain is, in spirit, the
                 same "explicit (non-idle-driven) kill" event as FR-014's
                 operator-facing admin kill ({!Serve_session.kill_worker}
                 — not called here directly, since that function only
                 sends [SIGTERM] with no grace/escalation); logged
                 directly at this call site instead of inside
                 {!Serve_session.kill_worker_escalating} itself, which is
                 also reused by the FR-013 idle-timeout reaper for its
                 own, distinctly-named [Idle_kill] event. *)
              Serve_audit.log
                Serve_audit.Explicit_kill
                ~token:(Serve_session.controller_token_string s) ;
              Serve_session.kill_worker_escalating
                s
                ~sw
                ~clock:env#clock
                ~grace:idle_kill_grace_seconds)
            live_sessions ;
          let deadline =
            Eio.Time.now env#clock +. idle_kill_grace_seconds +. 2.0
          in
          let rec wait_drained () =
            let still_alive =
              List.exists
                Serve_session.has_worker
                (Serve_session.to_list sessions)
            in
            if still_alive && Eio.Time.now env#clock < deadline then begin
              Eio.Time.sleep env#clock 0.1 ;
              wait_drained ()
            end
          in
          wait_drained () ;
          Printf.eprintf "[miaou serve] shutdown complete, exiting\n%!" ;
          Serve_process.cleanup_dir ~dir () ;
          exit 0
        end
        else begin
          Eio.Time.sleep env#clock 0.2 ;
          watch ()
        end
      in
      watch ()) ;
  (* FR-013: periodically reap idle sessions (no controller attached for
     longer than [idle_timeout]). A fixed, short scan interval
     ({!idle_scan_interval_seconds}) independent of [idle_timeout]'s own
     magnitude — see that value's doc comment. *)
  Eio.Fiber.fork ~sw (fun () ->
      let rec scan () =
        if not (Atomic.get Serve_process.stop_requested) then begin
          Serve_session.reap_idle_sessions
            ~sw
            ~clock:env#clock
            ~sessions
            ~idle_timeout
            ~grace:idle_kill_grace_seconds
            ~now:(Eio.Time.now env#clock) ;
          Eio.Time.sleep env#clock idle_scan_interval_seconds ;
          scan ()
        end
      in
      scan ()) ;
  (* FR-045: the same-origin-as-bind default is always in the allow-list,
     in addition to (not replaced by) any operator-supplied
     [--allowed-origin] values — a reverse-proxy operator adding their
     public origin must not lose the ability to also test/use the
     server directly at its bind address. *)
  let effective_allowed_origins =
    Serve_origin.default_allowed ~bind ~port @ allowed_origins
  in
  accept_loop
    ~sw
    ~env
    ~sessions
    ~max_sessions
    ~allowed_origins:effective_allowed_origins
    listening
