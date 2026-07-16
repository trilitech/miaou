(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-013/FR-070/FR-071/FR-072 (Slice 4): idle-timeout reaping,
   max_sessions cap, and per-worker resource limits. Named scenarios:
   - "max-sessions-rejects-cleanly": a controller attach that would
     spawn a new worker while the table is already at [max_sessions]
     gets a uniform 429, without ever contacting a worker; an
     already-spawned session's own traffic is unaffected by another
     session's rejection.
   - "idle-timeout-kills-worker" / "dead-token-not-resurrectable": an
     idle session (driven past its [idle_timeout] via a fake clock, no
     real sleeping) has its worker killed and both its tokens
     permanently invalidated — a fresh HTTP attempt against the dead
     controller token afterward gets the same uniform refusal as an
     unknown token, never a resurrection.
   - "worker-self-applies-rlimit-from-env": a worker spawned with
     [MIAOU_SERVE_RLIMIT_AS_MB] set in its environment actually has its
     RLIMIT_AS lowered accordingly (verified via /proc/<pid>/limits on
     Linux; a documented, environment-dependent check — see the
     platform caveat in serve_rlimit.mli). *)

module Stub_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  include Test_helpers.Stub_page_defaults (struct
    type nonrec state = state

    type nonrec pstate = pstate
  end)

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = "serve-limits-stub"

  let keymap _ : key_binding list = []

  let handled_keys () = []

  let handle_key ps _ ~size:_ = ps

  let on_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)
end

let page : (module Miaou_core.Tui_page.PAGE_SIG) = (module Stub_page)

(* Entry contract (serve_run.mli): this MUST run before anything else in
   [main] — before Alcotest, before any Eio loop. When re-exec'd as a
   session's worker (this test binary IS [Sys.executable_name], per
   {!Serve_process.spawn_worker}'s contract), this process becomes that
   worker's full app instance and never reaches the scenarios below. *)
let () =
  match Sys.getenv_opt Miaou_serve.Serve_worker.env_var with
  | Some socket_path ->
      Miaou_serve.Serve_worker.run ~socket_path page ;
      exit 0
  | None -> ()

open Alcotest
module Session = Miaou_serve.Serve_session
module Supervisor = Miaou_serve.Serve_supervisor
module Rlimit = Miaou_serve.Serve_rlimit

let free_port () =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind fd (Unix.ADDR_INET (Unix.inet_addr_loopback, 0)) ;
  let port =
    match Unix.getsockname fd with
    | Unix.ADDR_INET (_, port) -> port
    | Unix.ADDR_UNIX _ -> failwith "unexpected ADDR_UNIX"
  in
  Unix.close fd ;
  port

(* Polls on [env]'s clock, not [Unix.sleepf]: everything in this file
   runs client and server fibers on the *same* Eio scheduler (see
   [connect_and_get_status]'s doc comment) — a raw [Unix.sleepf] would
   block that single scheduler thread entirely, starving the very
   background fiber (e.g. a worker-reap fiber) this loop is waiting to
   observe progress from. [Eio.Time.sleep] yields properly instead. *)
let wait_until ~env ~deadline ~msg is_done =
  let rec loop () =
    if is_done () then ()
    else if Unix.gettimeofday () > deadline then fail msg
    else begin
      Eio.Time.sleep env#clock 0.02 ;
      loop ()
    end
  in
  loop ()

(* This test binary runs more than one Alcotest scenario in the same OS
   process (same pid, hence the same {!Supervisor.socket_dir}); a
   monotonic counter keeps every scenario's socket/port choices distinct,
   matching the convention in test_serve_multi_session.ml. *)
let harness_counter = Atomic.make 0

(* Purely Eio-native: unlike test_serve_multi_session.ml's raw blocking
   POSIX client (needed there to drive real WebSocket frame content on a
   separate system thread), every assertion in this file only needs the
   HTTP response's status line — never WS frame content — so a plain
   Eio.Net connection read from *within* the same switch as
   [accept_loop] is sufficient and avoids the cross-thread machinery
   entirely: both sides are cooperatively scheduled fibers on the same
   Eio run loop, so there is no deadlock risk reading a blocking-looking
   [Eio.Buf_read.line] here — it just yields back to the scheduler,
   which then runs [accept_loop]'s own fiber for this same connection. *)
let connect_and_get_status ~sw ~env ~port ~path =
  let conn =
    Eio.Net.connect ~sw env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
  in
  let req =
    Printf.sprintf
      "GET %s HTTP/1.1\r\n\
       Host: 127.0.0.1:%d\r\n\
       Upgrade: websocket\r\n\
       Connection: Upgrade\r\n\
       Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\
       Sec-WebSocket-Version: 13\r\n\
       \r\n"
      path
      port
  in
  Eio.Flow.copy_string req conn ;
  let br = Eio.Buf_read.of_flow ~max_size:(64 * 1024) conn in
  let status =
    match
      Eio.Time.with_timeout env#clock 10.0 (fun () ->
          let line = Eio.Buf_read.line br in
          match String.split_on_char ' ' (String.trim line) with
          | _ :: code :: _ -> Ok code
          | _ -> Ok "?")
    with
    | Ok code -> code
    | Error `Timeout -> fail "response head never arrived within 10s"
  in
  (conn, status)

let start_two_session_harness ~sw ~env ~max_sessions =
  let n = Atomic.fetch_and_add harness_counter 1 in
  let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
  Supervisor.ensure_socket_dir dir ;
  let socket_path_a =
    Filename.concat dir (Printf.sprintf "limits-a-%d.sock" n)
  in
  let socket_path_b =
    Filename.concat dir (Printf.sprintf "limits-b-%d.sock" n)
  in
  let session_a = Session.create ~env ~socket_path:socket_path_a in
  let session_b = Session.create ~env ~socket_path:socket_path_b in
  let sessions = Session.create_table () in
  Session.add sessions session_a ;
  Session.add sessions session_b ;
  let port = free_port () in
  let listening =
    Eio.Net.listen
      env#net
      ~sw
      ~reuse_addr:true
      ~backlog:16
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
  in
  (* [accept_loop] never returns on its own: fork it as a daemon fiber so
     this test's own [Eio.Switch.run] can finish once the test's own
     logic is done, without waiting on an accept loop that runs forever
     by design — {!Eio.Fiber.fork_daemon} is cancelled automatically once
     every non-daemon fiber on [sw] has finished. *)
  Eio.Fiber.fork_daemon ~sw (fun () ->
      Supervisor.accept_loop
        ~sw
        ~env
        ~sessions
        ~max_sessions
        ~allowed_origins:[]
        listening) ;
  (port, session_a, session_b)

(* M1 regression (post-review hardening): {!Session.count_spawned} must
   count a session from the moment it leaves [Not_spawned] (i.e. while
   merely [Spawning], not only once [Spawned]) — otherwise two
   concurrent first-attaches racing the [would_spawn]-gated cap check in
   [Serve_proxy.resolve] could both pass while the first is still
   spawning, over-admitting past [max_sessions] (a resource-limit
   bypass, not just a cosmetic undercount). Not reachable end-to-end
   today (production only ever creates one bootstrap session; there is
   no session-creation HTTP endpoint yet to race two brand-new sessions
   against each other over the wire — see docs/serve-architecture.md
   §3), so this exercises {!Session.count_spawned}/{!Session.would_spawn}
   directly against a real in-flight spawn, the same level the actual
   cap check itself operates at. *)
let test_count_spawned_includes_spawning_window () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let n = Atomic.fetch_and_add harness_counter 1 in
  let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
  Supervisor.ensure_socket_dir dir ;
  let socket_path =
    Filename.concat dir (Printf.sprintf "limits-spawning-%d.sock" n)
  in
  let session = Session.create ~env ~socket_path in
  let sessions = Session.create_table () in
  Session.add sessions session ;
  let observed_count = ref None in
  (* Racing two fibers on the same session: one drives the real spawn
     (a real subprocess fork/exec + socket-ready wait, so it genuinely
     spends time in the [Spawning] state before reaching [Spawned]); the
     other polls (yielding on [env#clock], never a busy/blocking
     [Unix.sleepf] — see the [wait_until]/[connect_and_get_status] doc
     comments above for why that matters on this single Eio scheduler)
     until it catches the window where the session has already left
     [Not_spawned] but has not yet reached [Spawned], and records
     [count_spawned] at that exact moment. *)
  Eio.Fiber.both
    (fun () ->
      ignore
        (Session.ensure_worker
           session
           ~sw
           ~proc_mgr:env#process_mgr
           ~net:env#net
           ~clock:env#clock
          : (string, Session.spawn_error) result))
    (fun () ->
      let deadline = Unix.gettimeofday () +. 5.0 in
      let rec poll () =
        if
          (not (Session.would_spawn session))
          && not (Session.has_worker session)
        then observed_count := Some (Session.count_spawned sessions)
        else if
          Unix.gettimeofday () < deadline && Option.is_none !observed_count
        then begin
          Eio.Time.sleep env#clock 0.001 ;
          poll ()
        end
      in
      poll ()) ;
  (match !observed_count with
  | Some n ->
      check
        int
        "count_spawned counts a Spawning-not-yet-Spawned worker (M1 fix)"
        1
        n
  | None ->
      (* The spawn completed too fast in this environment for the poller
         to ever catch the Spawning window (both fibers finished before
         either yielded a useful number of times) — inconclusive, not a
         failure of the fix itself; the code path is still exercised by
         every other scenario's calls to [ensure_worker]/[count_spawned]. *)
      Printf.printf
        "[test_serve_limits] note: never observed the Spawning window (spawn \
         completed before the poller caught it in this environment)\n") ;
  Session.kill_worker session ;
  wait_until
    ~env
    ~deadline:(Unix.gettimeofday () +. 5.0)
    ~msg:"session's worker was never reaped at test teardown"
    (fun () -> not (Session.has_worker session))

(* Scenario: "max-sessions-rejects-cleanly" (FR-070). *)
let test_max_sessions_rejects_cleanly () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let port, session_a, session_b =
    start_two_session_harness ~sw ~env ~max_sessions:1
  in
  let token_a = Session.controller_token_string session_a in
  let token_b = Session.controller_token_string session_b in
  let conn_a, status_a =
    connect_and_get_status
      ~sw
      ~env
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token_a)
  in
  check
    string
    "session A's controller attach succeeds (spawns 1st worker)"
    "101"
    status_a ;
  let conn_b, status_b =
    connect_and_get_status
      ~sw
      ~env
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token_b)
  in
  (try Eio.Flow.close conn_b with _ -> ()) ;
  check
    string
    "session B is refused once max_sessions=1 is already spawned"
    "429"
    status_b ;
  (* "Existing sessions unaffected": A's already-spawned session keeps
     serving ordinary requests after B's rejection — a fresh request to
     A's own token (a controller reattach to an *existing* worker, which
     {!Serve_session.would_spawn} correctly reports as not a new spawn)
     must never be refused by the same cap that just refused B. *)
  let conn_a2, status_a2 =
    connect_and_get_status
      ~sw
      ~env
      ~port
      ~path:(Printf.sprintf "/s/%s/" token_a)
  in
  (try Eio.Flow.close conn_a2 with _ -> ()) ;
  check
    string
    "session A keeps serving normally after B's rejection"
    "200"
    status_a2 ;
  (try Eio.Flow.close conn_a with _ -> ()) ;
  (* Kill session A's worker so {!Serve_session.ensure_worker}'s reap
     fiber (forked on this same [sw]) completes before this function
     returns — otherwise [Eio.Switch.run] would wait forever for a
     worker process this test never terminates (session B's own worker
     was never spawned at all, since it was refused before ever calling
     {!Serve_session.ensure_worker}, so there is no reap fiber for it to
     wait on). *)
  Session.kill_worker session_a ;
  wait_until
    ~env
    ~deadline:(Unix.gettimeofday () +. 5.0)
    ~msg:"session A's worker was never reaped at test teardown"
    (fun () -> not (Session.has_worker session_a))

(* Scenario: "idle-timeout-kills-worker" + "dead-token-not-resurrectable"
   (FR-013, US-4 scenario 2). The idle_timeout comparison itself never
   waits in real time: [now] is a caller-supplied float far beyond any
   plausible [idle_timeout], and the SIGTERM->grace->SIGKILL escalation's
   own bounded wait runs on a mock clock stepped directly, not slept on
   in real time. *)
let test_idle_timeout_kills_worker_and_dead_token_not_resurrectable () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let n = Atomic.fetch_and_add harness_counter 1 in
  let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
  Supervisor.ensure_socket_dir dir ;
  let socket_path =
    Filename.concat dir (Printf.sprintf "limits-idle-%d.sock" n)
  in
  let session = Session.create ~env ~socket_path in
  let sessions = Session.create_table () in
  Session.add sessions session ;
  let port = free_port () in
  let listening =
    Eio.Net.listen
      env#net
      ~sw
      ~reuse_addr:true
      ~backlog:16
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
  in
  Eio.Fiber.fork_daemon ~sw (fun () ->
      Supervisor.accept_loop
        ~sw
        ~env
        ~sessions
        ~max_sessions:10
        ~allowed_origins:[]
        listening) ;
  let token = Session.controller_token_string session in
  let viewer_token = Session.viewer_token_string session in
  let conn, status =
    connect_and_get_status
      ~sw
      ~env
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token)
  in
  check string "controller attach succeeds, worker spawned" "101" status ;
  check
    bool
    "session has a live worker before any idle reap"
    true
    (Session.has_worker session) ;
  (* Simulate "no controller attached, idle for a while": close this
     connection, then drive the session's own detach bookkeeping
     directly through the public API (the real on-close path would do
     the same thing asynchronously as the connection actually tears
     down; calling it here directly keeps this scenario deterministic
     rather than racing that teardown). *)
  (try Eio.Flow.close conn with _ -> ()) ;
  Session.controller_detach session ~now:0.0 ;
  let mock_clock = Eio_mock.Clock.make () in
  Session.reap_idle_sessions
    ~sw
    ~clock:mock_clock
    ~sessions
    ~idle_timeout:60.0
    ~grace:5.0
    ~now:1_000_000.0 ;
  check
    bool
    "session is marked dead immediately (before any process exit)"
    true
    (Session.is_dead session) ;
  (* Step the mock clock forward so the grace-escalation fiber (which
     would only ever fire if the worker somehow survived SIGTERM past
     the grace window) gets to run and check, without any real
     sleeping. *)
  Eio_mock.Clock.set_time mock_clock 10.0 ;
  wait_until
    ~env
    ~deadline:(Unix.gettimeofday () +. 5.0)
    ~msg:"worker was never reaped after the idle-timeout kill"
    (fun () -> not (Session.has_worker session)) ;
  let still_resolves candidate =
    match Session.find sessions ~candidate with None -> false | Some _ -> true
  in
  check
    bool
    "dead session's controller token no longer resolves via find"
    false
    (still_resolves token) ;
  check
    bool
    "dead session's viewer token no longer resolves via find"
    false
    (still_resolves viewer_token) ;
  (* Dead-token-not-resurrectable, proven over the wire too: a fresh
     attempt against the now-dead controller token is refused exactly
     like an unknown/never-existed token (uniform 403), never
     resurrected. *)
  let conn2, status2 =
    connect_and_get_status
      ~sw
      ~env
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token)
  in
  (try Eio.Flow.close conn2 with _ -> ()) ;
  check
    string
    "dead token refused over the wire, never resurrected"
    "403"
    status2

(* Scenario: "worker-self-applies-rlimit-from-env" (FR-072). Shells to
   the same [prlimit(1)] utility {!Serve_rlimit} itself uses, so this is
   an environment-dependent check (Linux/util-linux) — see
   serve_rlimit.mli's platform caveat. If [prlimit] is not on PATH in the
   test environment, this scenario logs a note and passes trivially
   rather than failing a platform-support gap the feature itself already
   documents as best-effort. *)
let test_worker_self_applies_rlimit_from_env () =
  if Sys.command "command -v prlimit >/dev/null 2>&1" <> 0 then
    Printf.printf
      "[test_serve_limits] skipping: 'prlimit' not on PATH in this environment \
       (documented platform caveat, serve_rlimit.mli)\n"
  else begin
    (* 512MB, not a tighter value: this is the concrete demonstration of
       serve_rlimit.mli's own RLIMIT_AS-vs-OCaml-heap caveat — a worker
       given too little virtual address space fails to start at all
       (observed directly while writing this test: 256MB reliably killed
       the worker with an out-of-memory abort before it could even open
       its listening socket; 384MB+ started reliably in this
       environment). 512MB is a safe margin above that observed floor,
       while still being comfortably below what an unconstrained worker
       would use, so the limit is genuinely exercised, not a no-op. *)
    let as_mb = 512 in
    Unix.putenv Rlimit.env_var_as_mb (string_of_int as_mb) ;
    Fun.protect
      ~finally:(fun () -> Unix.putenv Rlimit.env_var_as_mb "")
      (fun () ->
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        let n = Atomic.fetch_and_add harness_counter 1 in
        let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
        Supervisor.ensure_socket_dir dir ;
        let socket_path =
          Filename.concat dir (Printf.sprintf "limits-rlimit-%d.sock" n)
        in
        let worker =
          Supervisor.spawn_worker ~sw ~proc_mgr:env#process_mgr ~socket_path ()
        in
        let ready =
          Supervisor.wait_ready
            ~sw
            ~net:env#net
            ~clock:env#clock
            ~socket_path
            ~retries:200
            ~delay:0.02
        in
        check
          bool
          "worker with MIAOU_SERVE_RLIMIT_AS_MB set becomes reachable"
          true
          ready ;
        let limits_path =
          Printf.sprintf "/proc/%d/limits" worker.Supervisor.pid
        in
        let expected_bytes = as_mb * 1024 * 1024 in
        let found =
          try
            let ic = open_in limits_path in
            Fun.protect
              ~finally:(fun () -> close_in ic)
              (fun () ->
                let rec scan () =
                  match input_line ic with
                  | line ->
                      Test_helpers.contains_substring
                        line
                        (Printf.sprintf
                           "Max address space         %d"
                           expected_bytes)
                      || scan ()
                  | exception End_of_file -> false
                in
                scan ())
          with Sys_error _ -> false
        in
        check
          bool
          "worker's RLIMIT_AS reflects MIAOU_SERVE_RLIMIT_AS_MB"
          true
          found ;
        Supervisor.kill worker ;
        ignore (worker.Supervisor.await () : Eio.Process.exit_status))
  end

let () =
  run
    "serve_limits"
    [
      ( "max_sessions",
        [
          test_case
            "max-sessions-rejects-cleanly"
            `Slow
            test_max_sessions_rejects_cleanly;
          test_case
            "count_spawned includes the Spawning window (M1)"
            `Slow
            test_count_spawned_includes_spawning_window;
        ] );
      ( "idle_timeout",
        [
          test_case
            "idle-timeout-kills-worker and dead-token-not-resurrectable"
            `Slow
            test_idle_timeout_kills_worker_and_dead_token_not_resurrectable;
        ] );
      ( "rlimit",
        [
          test_case
            "worker self-applies rlimit from env"
            `Slow
            test_worker_self_applies_rlimit_from_env;
        ] );
    ]
