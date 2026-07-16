(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-010/FR-011 process-isolation proof: two concurrent controller
   sessions, each lazily spawning its own worker process, must not leak
   any state between each other. The served page deliberately touches
   {!Miaou_core.Modal_manager} — a true process-global singleton with no
   mutex (per kb/risks.md R3 and the miaou-serve spec's own §1 evidence)
   — precisely so that a regression collapsing Slice 3 back to a single
   shared worker process would make this test fail: pushing session A's
   modal would also flip session B's rendered [MODAL=] state, and
   incrementing session A's counter would leak into session B's [N=]
   value, since both would be reading/writing the same OCaml-level
   globals in one address space. Today's design (real, separate OS
   processes per session — {!Miaou_serve.Serve_session.ensure_worker})
   makes that structurally impossible: there is no code path by which one
   worker's memory is reachable from another's. *)

module Marker_modal : Miaou_core.Tui_page.PAGE_SIG with type state = unit =
struct
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

  let view _ps ~focus:_ ~size:_ = "marker-modal"

  let keymap _ : key_binding list = []

  let handled_keys () = []

  let handle_key ps _ ~size:_ = ps

  let on_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)
end

(* Deliberately touches two process-global singletons the spec's own
   evidence (§1) names as the sharpest argument against in-process
   multi-session: [Modal_manager]'s unguarded stack (pushed on key "m")
   and, via [Navigation]'s state, a per-page counter (incremented on key
   "d") whose value is rendered directly into the frame text so a test
   client can observe it without any internal hooks — only the wire
   protocol. *)
module Counter_page : Miaou_core.Tui_page.PAGE_SIG with type state = int =
struct
  type state = int

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  include Test_helpers.Stub_page_defaults (struct
    type nonrec state = state

    type nonrec pstate = pstate
  end)

  let init () = Miaou_core.Navigation.make 0

  let update ps _ = ps

  let view ps ~focus:_ ~size:_ =
    Printf.sprintf
      "N=%d MODAL=%s"
      ps.Miaou_core.Navigation.s
      (if Miaou_core.Modal_manager.has_active () then "OPEN" else "CLOSED")

  let keymap _ : key_binding list = []

  let handled_keys () = []

  let handle_key ps _ ~size:_ = ps

  let on_key ps key ~size:_ =
    let ps' =
      match key with
      | Miaou_core.Keys.Char "d" ->
          Miaou_core.Navigation.update (fun n -> n + 1) ps
      | Miaou_core.Keys.Char "m" ->
          Miaou_core.Modal_manager.push
            (module Marker_modal)
            ~init:(Marker_modal.init ())
            ~ui:
              {
                Miaou_core.Modal_manager.title = "marker";
                left = None;
                max_width = None;
                dim_background = false;
              }
            ~commit_on:["Enter"]
            ~cancel_on:["Escape"]
            ~on_close:(fun _ _ -> ()) ;
          ps
      | _ -> ps
    in
    (ps', Miaou_interfaces.Key_event.Bubble)
end

let page : (module Miaou_core.Tui_page.PAGE_SIG) = (module Counter_page)

(* Entry contract (serve_run.mli): this MUST run before anything else in
   [main] — before Alcotest, before any Eio loop — exactly mirroring how a
   host app's [main] must behave before calling [Miaou_serve.run]. When
   re-exec'd as a session's worker (this test binary IS
   [Sys.executable_name], per {!Serve_process.spawn_worker}'s contract),
   this process becomes that worker's full app instance and never reaches
   the test scenarios below. *)
let () =
  match Sys.getenv_opt Miaou_serve.Serve_worker.env_var with
  | Some socket_path ->
      Miaou_serve.Serve_worker.run ~socket_path page ;
      exit 0
  | None -> ()

open Alcotest
module Session = Miaou_serve.Serve_session
module Supervisor = Miaou_serve.Serve_supervisor

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

(* --- Minimal RFC 6455 client-frame codec over a real blocking socket
   (adapted from test_web_websocket.ml's in-memory version): client
   frames must be masked (RFC 6455 6.1). *)
let mask_key = "\x12\x34\x56\x78"

let build_client_frame ~opcode payload =
  let len = String.length payload in
  let buf = Buffer.create (len + 10) in
  Buffer.add_uint8 buf (0x80 lor opcode) ;
  let mask_bit = 0x80 in
  if len < 126 then Buffer.add_uint8 buf (mask_bit lor len)
  else begin
    Buffer.add_uint8 buf (mask_bit lor 126) ;
    Buffer.add_uint16_be buf len
  end ;
  Buffer.add_string buf mask_key ;
  String.iteri
    (fun i c ->
      let m = Char.code mask_key.[i mod 4] in
      Buffer.add_char buf (Char.chr (Char.code c lxor m)))
    payload ;
  Buffer.contents buf

let opcode_text = 0x1

type client = {fd : Unix.file_descr; mutable pending : string}

let close_client client =
  try Unix.close client.fd with Unix.Unix_error _ -> ()

let find_substring haystack needle =
  let hn = String.length needle in
  let hl = String.length haystack in
  let rec loop i =
    if i + hn > hl then None
    else if String.sub haystack i hn = needle then Some i
    else loop (i + 1)
  in
  loop 0

(* Connects, sends a raw upgrade request to [path], and blocks until the
   full response head is received; returns the client with any bytes
   already read past the head (e.g. the start of a WS frame arriving in
   the same TCP segment) kept in [pending], plus the response's HTTP
   status code. *)
let connect_and_upgrade ~port ~path =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO 10.0 ;
  Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) ;
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
  ignore (Unix.write_substring fd req 0 (String.length req) : int) ;
  let buf = Buffer.create 512 in
  let rec read_head () =
    let chunk = Bytes.create 4096 in
    let n = Unix.read fd chunk 0 4096 in
    if n = 0 then failwith "connection closed during handshake"
    else begin
      Buffer.add_subbytes buf chunk 0 n ;
      let s = Buffer.contents buf in
      match find_substring s "\r\n\r\n" with
      | Some idx ->
          ( String.sub s 0 idx,
            String.sub s (idx + 4) (String.length s - idx - 4) )
      | None -> read_head ()
    end
  in
  let head, residue = read_head () in
  let status =
    match String.split_on_char ' ' head with _ :: code :: _ -> code | _ -> "?"
  in
  ({fd; pending = residue}, status)

let send_json client msg =
  let frame = build_client_frame ~opcode:opcode_text msg in
  ignore (Unix.write_substring client.fd frame 0 (String.length frame) : int)

(* Attempts to decode exactly one complete server (unmasked) frame from
   the front of [client.pending]. Handles the two length forms the
   server's small JSON/ANSI payloads actually use (< 126 bytes, and the
   16-bit extended-length form); returns [None] (leaving [pending]
   untouched) if not enough bytes have arrived yet for a full frame. *)
let try_decode_frame client =
  let s = client.pending in
  if String.length s < 2 then None
  else
    let b1 = Char.code s.[1] in
    let len7 = b1 land 0x7F in
    let hdr_len, len =
      if len7 < 126 then (2, len7)
      else if len7 = 126 then
        if String.length s < 4 then (-1, 0)
        else (4, (Char.code s.[2] * 256) + Char.code s.[3])
      else (-1, 0)
      (* 64-bit extended length: not produced by this server for these
         small test payloads; treated as "not enough data yet" is wrong
         but harmless here since it never occurs in practice. *)
    in
    if hdr_len < 0 || String.length s < hdr_len + len then None
    else
      let opcode = Char.code s.[0] land 0x0F in
      let payload = String.sub s hdr_len len in
      client.pending <-
        String.sub s (hdr_len + len) (String.length s - hdr_len - len) ;
      Some (opcode, payload)

let opcode_text_frame = 0x1

(* Reads whatever is available within [timeout] seconds (a single
   syscall's worth), appending it to [client.pending]; returns [false] on
   a read timeout or EOF. *)
let read_more client ~timeout =
  match Unix.select [client.fd] [] [] timeout with
  | [], _, _ -> false
  | _ -> (
      let b = Bytes.create 65536 in
      match Unix.read client.fd b 0 65536 with
      | 0 -> false
      | n ->
          client.pending <- client.pending ^ Bytes.sub_string b 0 n ;
          true
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> true)

(* Polls [client] until [acc] (the concatenation of every text frame
   payload received so far) contains [marker], or [deadline] passes. *)
let wait_for_marker client ~marker ~deadline =
  let acc = Buffer.create 1024 in
  let rec drain_buffered () =
    match try_decode_frame client with
    | Some (op, payload) when op = opcode_text_frame ->
        Buffer.add_string acc payload ;
        drain_buffered ()
    | Some (_, _) -> drain_buffered ()
    | None -> ()
  in
  let rec loop () =
    drain_buffered () ;
    if Test_helpers.contains_substring (Buffer.contents acc) marker then true
    else if Unix.gettimeofday () > deadline then false
    else begin
      ignore (read_more client ~timeout:0.1 : bool) ;
      loop ()
    end
  in
  loop ()

(* Drains whatever [client] sends for [duration] seconds, returning the
   concatenation of every text-frame payload observed. Used to assert an
   *absence* — unlike {!wait_for_marker}, which stops as soon as it finds
   something, this always waits out the full window so a marker that
   never arrives is a meaningful negative result, not an early exit. *)
let drain_for client ~duration =
  let acc = Buffer.create 1024 in
  let deadline = Unix.gettimeofday () +. duration in
  let rec loop () =
    (match try_decode_frame client with
    | Some (op, payload) when op = opcode_text_frame ->
        Buffer.add_string acc payload
    | Some (_, _) -> ()
    | None -> ()) ;
    if Unix.gettimeofday () > deadline then Buffer.contents acc
    else begin
      ignore (read_more client ~timeout:0.05 : bool) ;
      loop ()
    end
  in
  loop ()

(* The session table's own routing/spawn machinery ({!Supervisor.accept_loop})
   must run inside an Eio scheduler, but this test's WebSocket client
   uses plain blocking POSIX sockets (the simplest way to speak the raw
   RFC 6455 wire protocol without fighting cross-domain Eio ownership).
   Driving both halves on the same Eio-scheduled thread would deadlock:
   a blocking [Unix.read] on the client side never yields back to Eio's
   scheduler, so the [accept_loop] fiber servicing that very connection
   would never get to run. Running the Eio side on its own system
   thread — decoupled from the main thread's blocking client calls, and
   released to make progress during every blocking syscall the client
   makes — avoids that. *)
type harness = {
  port : int;
  session_a : Session.t;
  session_b : Session.t;
  socket_path_a : string;
}

(* This test binary runs more than one Alcotest scenario in the same OS
   process (same pid, hence the same {!Supervisor.socket_dir}); each
   scenario's worker(s) are also never explicitly killed at the end of a
   scenario (a real detach leaves a worker running, per FR-012), so a
   later scenario reusing an earlier scenario's socket filename would
   have its "fresh" worker spawn collide with a still-live prior worker
   still bound to that same path — the second [spawn_worker] either
   fails to bind or (worse) silently steals the path while the old
   worker answers requests instead, cross-contaminating two scenarios
   that are supposed to be fully independent. A monotonic counter keeps
   every {!start_harness} call's socket paths distinct. *)
let harness_counter = Atomic.make 0

let start_harness () =
  let port = free_port () in
  let n = Atomic.fetch_and_add harness_counter 1 in
  let session_a_slot = ref None in
  let session_b_slot = ref None in
  let ready = Atomic.make false in
  let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
  let socket_path_a =
    Filename.concat dir (Printf.sprintf "multi-a-%d.sock" n)
  in
  let socket_path_b =
    Filename.concat dir (Printf.sprintf "multi-b-%d.sock" n)
  in
  let (_ : Thread.t) =
    Thread.create
      (fun () ->
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        Supervisor.ensure_socket_dir dir ;
        let session_a =
          Session.create
            ~env
            ~socket_path:socket_path_a
            ~now:(Eio.Time.now env#clock)
        in
        let session_b =
          Session.create
            ~env
            ~socket_path:socket_path_b
            ~now:(Eio.Time.now env#clock)
        in
        let sessions = Session.create_table () in
        Session.add sessions session_a ;
        Session.add sessions session_b ;
        session_a_slot := Some session_a ;
        session_b_slot := Some session_b ;
        let listening =
          Eio.Net.listen
            env#net
            ~sw
            ~reuse_addr:true
            ~backlog:16
            (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
        in
        Atomic.set ready true ;
        Supervisor.accept_loop
          ~sw
          ~env
          ~sessions
          ~max_sessions:1000
          ~allowed_origins:[]
          listening)
      ()
  in
  let deadline = Unix.gettimeofday () +. 10.0 in
  while (not (Atomic.get ready)) && Unix.gettimeofday () < deadline do
    Unix.sleepf 0.01
  done ;
  if not (Atomic.get ready) then
    fail "test harness's supervisor thread never became ready" ;
  match (!session_a_slot, !session_b_slot) with
  | Some session_a, Some session_b ->
      {port; session_a; session_b; socket_path_a}
  | _ -> fail "test harness never captured its sessions"

let test_two_controllers_are_process_isolated () =
  let {port; session_a; session_b; socket_path_a = _} = start_harness () in
  let token_a = Session.controller_token_string session_a in
  let token_b = Session.controller_token_string session_b in
  let client_a, status_a =
    connect_and_upgrade ~port ~path:(Printf.sprintf "/s/%s/ws" token_a)
  in
  check string "session A controller upgrade succeeds" "101" status_a ;
  let client_b, status_b =
    connect_and_upgrade ~port ~path:(Printf.sprintf "/s/%s/ws" token_b)
  in
  check string "session B controller upgrade succeeds" "101" status_b ;
  send_json client_a {|{"type":"resize","rows":24,"cols":80}|} ;
  send_json client_b {|{"type":"resize","rows":24,"cols":80}|} ;
  (* Drive session A only: 3x increment, then open a modal. *)
  send_json client_a {|{"type":"key","key":"d"}|} ;
  send_json client_a {|{"type":"key","key":"d"}|} ;
  send_json client_a {|{"type":"key","key":"d"}|} ;
  send_json client_a {|{"type":"key","key":"m"}|} ;
  let deadline = Unix.gettimeofday () +. 15.0 in
  check
    bool
    "session A's counter reaches N=3 and its modal opens"
    true
    (wait_for_marker client_a ~marker:"N=3 MODAL=OPEN" ~deadline) ;
  (* Session B never received any key input: its frames must never show
     A's counter value or A's modal state — this is the isolation
     assertion the test exists to make (it would fail if a regression
     ever collapsed both sessions onto one shared worker process, since
     [Modal_manager]/[Navigation] state would then be the same OCaml
     value for both connections). *)
  let b_output = drain_for client_b ~duration:2.0 in
  check
    bool
    "session B's frames never show session A's counter value"
    false
    (Test_helpers.contains_substring b_output "N=3") ;
  check
    bool
    "session B's frames never show session A's modal as open"
    false
    (Test_helpers.contains_substring b_output "MODAL=OPEN") ;
  check
    bool
    "session B's frames do show its own untouched state, once rendered"
    true
    (Test_helpers.contains_substring b_output "N=0"
    || wait_for_marker
         client_b
         ~marker:"N=0"
         ~deadline:(Unix.gettimeofday () +. 5.0)) ;
  (* The process-isolation proof itself: two distinct OS pids. *)
  match (Session.worker_pid session_a, Session.worker_pid session_b) with
  | Some pid_a, Some pid_b ->
      check bool "session A has a real worker pid" true (pid_a > 0) ;
      check bool "session B has a real worker pid" true (pid_b > 0) ;
      check
        bool
        "session A and session B are distinct worker processes"
        true
        (pid_a <> pid_b)
  | _ -> fail "expected both sessions to have spawned a worker by now"

let wait_until ~deadline ~msg is_done =
  let rec loop () =
    if is_done () then ()
    else if Unix.gettimeofday () > deadline then fail msg
    else begin
      Unix.sleepf 0.02 ;
      loop ()
    end
  in
  loop ()

(* Regression test for the HIGH-severity finding: a controller attach
   whose connection to the worker fails (worker unreachable at connect
   time — here, because it just crashed) must not leave
   [Serve_session.controller_live] stuck [true] forever. Before the fix,
   [serve_proxy.ml]'s [Fun.protect ~finally:on_close] only wrapped the
   [proxy_bytes] happy path, so a [connect_worker] failure (-> 502) or
   any exception while reading the rest of the request head skipped
   [controller_detach] entirely: every later controller attach for that
   session would be silently downgraded to a viewer (FR-011's
   [`Downgrade]), and since the worker itself has no controller
   attached, viewer attaches to it would also fail (409) — a permanent,
   silent lockout with no recovery. *)
let test_worker_unreachable_then_fresh_controller_reattaches () =
  let {port; session_a; session_b = _; socket_path_a} = start_harness () in
  let token = Session.controller_token_string session_a in
  let c1, s1 =
    connect_and_upgrade ~port ~path:(Printf.sprintf "/s/%s/ws" token)
  in
  check string "first controller attach succeeds" "101" s1 ;
  close_client c1 ;
  if Session.worker_pid session_a = None then
    fail "expected a worker pid after the first attach" ;
  (* Deterministically make the *next* connect to this session's worker
     fail, without racing the worker's own reap/self-heal at all:
     [ensure_worker]'s "already Spawned" fast path never re-verifies
     reachability, so unlinking the socket file out from under the
     still-running worker is enough to make the proxy's own, separate
     [connect_worker] dial fail on the very next attempt — the worker
     process itself is untouched and stays alive throughout. *)
  (try Unix.unlink socket_path_a with Unix.Unix_error _ -> ()) ;
  (* Second attach: the proxy's own connect to the (now-unlinked) worker
     socket must fail -> 502. Before the HIGH fix, this attempt's own
     [controller_attach] call (which runs before the proxy ever tries to
     connect) would leave [controller_live] stuck [true] forever, since
     nothing ran [controller_detach] on this 502 path. *)
  let c2, s2 =
    connect_and_upgrade ~port ~path:(Printf.sprintf "/s/%s/ws" token)
  in
  check
    string
    "second attach, worker unreachable at connect time, gets 502"
    "502"
    s2 ;
  close_client c2 ;
  (* Now retire the (still-alive, but permanently unreachable-by-path)
     worker for real, and wait for the session to self-heal (LOW#1):
     [has_worker] flips back to [false] once the reap callback resets
     the session's worker state, at which point the *next*
     [ensure_worker] call spawns a genuinely fresh, reachable worker —
     giving the third attach below an unambiguous live worker to land
     on, so its response code cleanly distinguishes Attach (101) from
     Downgrade (409, "no controller connected yet" on a fresh worker). *)
  Session.kill_worker session_a ;
  wait_until
    ~deadline:(Unix.gettimeofday () +. 5.0)
    ~msg:
      "session never self-healed (has_worker never returned to false) after \
       the worker was killed"
    (fun () -> not (Session.has_worker session_a)) ;
  (* Third attach: if the HIGH fix is in place, [controller_live] was
     reset by the second attempt's own (now-guaranteed) detach, so this
     is treated as a normal first attach against the fresh, self-healed
     worker -> 101. Without the fix, [controller_live] would still read
     [true] from the second attempt, so this would be silently
     downgraded to a viewer request against a worker with no controller
     yet -> 409 — a permanent lockout with no way for a legitimate
     controller to ever attach again. *)
  let c3, s3 =
    connect_and_upgrade ~port ~path:(Printf.sprintf "/s/%s/ws" token)
  in
  check
    string
    "a fresh controller attach after the crash still gets Attach (101), not a \
     silent permanent Downgrade (409) lockout"
    "101"
    s3 ;
  close_client c3

let () =
  run
    "serve_multi_session"
    [
      ( "isolation",
        [
          test_case
            "two controllers are process-isolated"
            `Slow
            test_two_controllers_are_process_isolated;
        ] );
      ( "recovery",
        [
          test_case
            "worker unreachable then fresh controller reattaches"
            `Slow
            test_worker_unreachable_then_fresh_controller_reattaches;
        ] );
    ]
