(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-010, FR-014, FR-015 (Slice 2 scope only — multi-session scenarios
   wait for Slice 3): drives Miaou_serve.Serve_supervisor's spawn/kill/reap
   primitives directly against a real re-exec'd worker process (this very
   test binary, re-invoked with MIAOU_SERVE_WORKER_SOCKET set — the
   binding re-exec contract documented in serve_run.mli). Three named
   scenarios: "create", "explicit-kill", "worker-crash-no-zombie". *)

module Stub_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = "serve-session-lifecycle-stub"

  let move ps _ = ps

  let refresh ps = ps

  let service_select ps _ = ps

  let service_cycle ps _ = ps

  let back ps = ps

  let keymap _ : key_binding list = []

  let handled_keys () = []

  let handle_modal_key ps _ ~size:_ = ps

  let handle_key ps _ ~size:_ = ps

  let on_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)

  let on_modal_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)

  let key_hints _ = []

  let has_modal _ = false
end

let page : (module Miaou_core.Tui_page.PAGE_SIG) = (module Stub_page)

(* Entry contract (serve_run.mli): this check MUST run before anything
   else in [main] — before Alcotest's runner, before any Eio loop —
   exactly mirroring how a host app's [main] must behave before calling
   [Miaou_serve.run]. When re-exec'd by Serve_supervisor.spawn_worker,
   this process becomes a worker and never reaches the test suite below. *)
let () =
  match Sys.getenv_opt Miaou_serve.Serve_worker.env_var with
  | Some socket_path ->
      Miaou_serve.Serve_worker.run ~socket_path page ;
      exit 0
  | None -> ()

open Alcotest
module Sup = Miaou_serve.Serve_supervisor

let scenario_counter = Atomic.make 0

let fresh_socket_path scenario =
  let n = Atomic.fetch_and_add scenario_counter 1 in
  let dir = Sup.socket_dir ~pid:(Unix.getpid ()) in
  Sup.ensure_socket_dir dir ;
  Filename.concat dir (Printf.sprintf "%s-%d.sock" scenario n)

let spawn_and_wait_ready ~sw ~env ~scenario =
  let socket_path = fresh_socket_path scenario in
  let worker = Sup.spawn_worker ~sw ~proc_mgr:env#process_mgr ~socket_path () in
  let ready =
    Sup.wait_ready
      ~sw
      ~net:env#net
      ~clock:env#clock
      ~socket_path
      ~retries:200
      ~delay:0.02
  in
  check bool (scenario ^ ": worker becomes reachable") true ready ;
  check bool (scenario ^ ": worker pid is positive") true (worker.Sup.pid > 0) ;
  worker

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

(* Scenario: "create" (FR-010) — spawning a worker makes it reachable on
   its private Unix socket, with a real OS pid. *)
let test_create () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let worker = spawn_and_wait_ready ~sw ~env ~scenario:"create" in
  Sup.kill worker ;
  ignore (worker.Sup.await () : Eio.Process.exit_status)

(* Scenario: "explicit-kill" (FR-014) — the operator-facing admin surface
   (Serve_supervisor.kill, SIGTERM) actually terminates the worker, and
   Serve_supervisor.reap (FR-015) observes the exit. *)
let test_explicit_kill () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let worker = spawn_and_wait_ready ~sw ~env ~scenario:"explicit-kill" in
  let exited = ref false in
  Sup.reap ~sw worker ~on_exit:(fun _status -> exited := true) ;
  Sup.kill worker ;
  wait_until
    ~env
    ~deadline:(Unix.gettimeofday () +. 5.0)
    ~msg:"worker was not reaped after explicit kill"
    (fun () -> !exited) ;
  check bool "worker reaped after explicit SIGTERM kill" true !exited

(* Scenario: "worker-crash-no-zombie" (FR-015) — an external kill -9
   (simulating a crash, bypassing Serve_supervisor.kill entirely) is
   still reaped: no zombie process lingers in the process table. *)
let test_crash_no_zombie () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let worker = spawn_and_wait_ready ~sw ~env ~scenario:"crash-no-zombie" in
  let exited = ref false in
  Sup.reap ~sw worker ~on_exit:(fun _status -> exited := true) ;
  Unix.kill worker.Sup.pid Sys.sigkill ;
  wait_until
    ~env
    ~deadline:(Unix.gettimeofday () +. 5.0)
    ~msg:"worker was not reaped after kill -9"
    (fun () -> !exited) ;
  check bool "worker reaped after kill -9 (no zombie)" true !exited ;
  (* Once our reaper's [Eio.Process.await] has consumed the exit status,
     the kernel's process-table entry for [pid] is gone. A zombie, by
     contrast, still answers signals until reaped — so signalling the
     pid again must now fail with ESRCH, not succeed. *)
  let esrch =
    try
      Unix.kill worker.Sup.pid 0 ;
      false
    with Unix.Unix_error (Unix.ESRCH, _, _) -> true
  in
  check bool "pid fully reaped (ESRCH), not a lingering zombie" true esrch

let () =
  run
    "serve_session_lifecycle"
    [
      ( "lifecycle",
        [
          test_case "create" `Slow test_create;
          test_case "explicit-kill" `Slow test_explicit_kill;
          test_case "worker-crash-no-zombie" `Slow test_crash_no_zombie;
        ] );
    ]
