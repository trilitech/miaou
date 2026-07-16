(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-080 (Slice 7): structured audit log. Drives every named
   session-lifecycle event through the real production code path
   ({!Miaou_serve.Serve_supervisor.accept_loop}/{!Miaou_serve.Serve_proxy}/
   {!Miaou_serve.Serve_session}) against one shared harness, captures
   stderr throughout, then asserts:
   - every event's tag ([event=<name>]) appears at least once;
   - the key security assertion: none of the real session tokens this
     test generated appear anywhere in the captured log, raw — every
     event is logged via a hash ({!Miaou_serve.Serve_audit.hash_token}),
     never the token value itself. *)

module Stub_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = unit

  type key_binding = state Miaou_core.Tui_page.key_binding_desc

  type pstate = state Miaou_core.Navigation.t

  type msg = unit

  let init () = Miaou_core.Navigation.make ()

  let update ps _ = ps

  let view _ps ~focus:_ ~size:_ = "serve-audit-log-stub"

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

(* Entry contract (serve_run.mli): this MUST run before anything else in
   [main]. When re-exec'd as a session's worker (this test binary IS
   [Sys.executable_name], per {!Serve_process.spawn_worker}'s contract),
   this process becomes that worker's full app instance and never
   reaches the scenarios below. *)
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

(* --- Minimal RFC 6455 client-frame codec over a real blocking socket,
   matching test_serve_reconnect.ml's/test_serve_origin_check.ml's
   identical helpers. *)
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

let opcode_close = 0x8

type client = {fd : Unix.file_descr}

let find_substring haystack needle =
  let hn = String.length needle in
  let hl = String.length haystack in
  let rec loop i =
    if i + hn > hl then None
    else if String.sub haystack i hn = needle then Some i
    else loop (i + 1)
  in
  loop 0

(* Connects and sends a WebSocket upgrade request to [path], optionally
   carrying an [Origin] header, returning the status code string from
   the response's status line — mirrors
   test_serve_origin_check.ml's identical helper. *)
let connect_and_upgrade ~port ~path ~origin () =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO 10.0 ;
  Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) ;
  let origin_header =
    match origin with Some o -> Printf.sprintf "Origin: %s\r\n" o | None -> ""
  in
  let req =
    Printf.sprintf
      "GET %s HTTP/1.1\r\n\
       Host: 127.0.0.1:%d\r\n\
       Upgrade: websocket\r\n\
       Connection: Upgrade\r\n\
       %sSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\
       Sec-WebSocket-Version: 13\r\n\
       \r\n"
      path
      port
      origin_header
  in
  ignore (Unix.write_substring fd req 0 (String.length req) : int) ;
  let buf = Buffer.create 512 in
  let rec read_head () =
    let chunk = Bytes.create 4096 in
    match Unix.read fd chunk 0 4096 with
    | 0 -> Buffer.contents buf
    | n ->
        Buffer.add_subbytes buf chunk 0 n ;
        let s = Buffer.contents buf in
        if find_substring s "\r\n\r\n" <> None then s else read_head ()
    | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
        Buffer.contents buf
  in
  let head = read_head () in
  let status =
    match String.split_on_char ' ' head with _ :: code :: _ -> code | _ -> "?"
  in
  ({fd}, status)

let send_json client msg =
  let frame = build_client_frame ~opcode:opcode_text msg in
  ignore (Unix.write_substring client.fd frame 0 (String.length frame) : int)

(* A clean close: sends a WebSocket close frame before shutting the
   socket down. *)
let close_client_clean client =
  (try
     let frame = build_client_frame ~opcode:opcode_close "" in
     ignore (Unix.write_substring client.fd frame 0 (String.length frame) : int)
   with Unix.Unix_error _ -> ()) ;
  try Unix.close client.fd with Unix.Unix_error _ -> ()

(* Stderr capture, identical to test_serve_viewer_readonly.ml's
   [start_capture_stderr]/[stop_capture_stderr] pair — must wrap the
   entire scenario (not just the input that triggers a given event),
   since a worker process inherits whatever fd 2 refers to at the
   moment it is spawned. *)
let start_capture_stderr () =
  let saved_stderr = Unix.dup Unix.stderr in
  let r, w = Unix.pipe () in
  Unix.set_nonblock r ;
  Unix.dup2 w Unix.stderr ;
  Unix.close w ;
  (saved_stderr, r)

let stop_capture_stderr (saved_stderr, r) =
  flush stderr ;
  Unix.dup2 saved_stderr Unix.stderr ;
  Unix.close saved_stderr ;
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  let rec drain () =
    match Unix.read r chunk 0 4096 with
    | 0 -> ()
    | n ->
        Buffer.add_subbytes buf chunk 0 n ;
        drain ()
    | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
  in
  drain () ;
  Unix.close r ;
  Buffer.contents buf

(* One shared harness: a session table seeded with three sessions
   (created inside the harness's own Eio env, which every
   [Session.create]/[ensure_worker]/[reap_idle_sessions] call below
   needs), driven to completion for the idle-kill and explicit-kill
   scenarios *before* [accept_loop] ever starts (both are synchronous —
   {!Session.reap_idle_sessions} and {!Session.kill_worker} return only
   after emitting their audit line), then serving the wire-level
   scenarios (create/attach/detach/reconnect/attach-viewer/auth-fail/
   origin-reject/session-end) against [session_wire] once [accept_loop]
   is running. *)
type harness = {
  port : int;
  session_wire : Session.t;
  session_idle : Session.t;
  session_kill : Session.t;
}

let start_harness () =
  let port = free_port () in
  let slot = ref None in
  let ready = Atomic.make false in
  let (_ : Thread.t) =
    Thread.create
      (fun () ->
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
        Supervisor.ensure_socket_dir dir ;
        let session_wire =
          Session.create
            ~env
            ~socket_path:(Filename.concat dir "audit-wire.sock")
            ~now:(Eio.Time.now env#clock)
        in
        let session_idle =
          Session.create
            ~env
            ~socket_path:(Filename.concat dir "audit-idle.sock")
            ~now:(Eio.Time.now env#clock)
        in
        let session_kill =
          Session.create
            ~env
            ~socket_path:(Filename.concat dir "audit-kill.sock")
            ~now:(Eio.Time.now env#clock)
        in
        let sessions = Session.create_table () in
        Session.add sessions session_wire ;
        Session.add sessions session_idle ;
        (* Idle-kill scenario: spawn [session_idle]'s worker directly (no
           controller ever attaches — [session_wire] is the only session
           any wire-level request below ever targets), then reap it
           immediately: [is_idle]'s baseline is [session_idle]'s own
           creation time (post-S7-review fix — see {!Session.create}'s
           doc comment), so a *negative* idle_timeout is used here
           (rather than [0.0], which would depend on some nonzero real
           time having elapsed between creation and this
           [reap_idle_sessions] call) to make "already idle" true
           unconditionally, keeping this deterministic with no reliance
           on real-clock timing margins. *)
        (match
           Session.ensure_worker
             session_idle
             ~sw
             ~proc_mgr:env#process_mgr
             ~net:env#net
             ~clock:env#clock
         with
        | Ok _ -> ()
        | Error Session.Unreachable ->
            failwith "test harness: session_idle's worker never became ready") ;
        Session.reap_idle_sessions
          ~sw
          ~clock:env#clock
          ~sessions
          ~idle_timeout:(-1.0)
          ~grace:0.5
          ~now:(Eio.Time.now env#clock) ;
        (* Explicit-kill scenario: no worker ever spawned for
           [session_kill] — {!Session.kill_worker} still emits its audit
           line unconditionally (see its own doc comment). *)
        Session.kill_worker session_kill ;
        slot := Some {port; session_wire; session_idle; session_kill} ;
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
          ~allowed_origins:["http://allowed.example"]
          listening)
      ()
  in
  let deadline = Unix.gettimeofday () +. 10.0 in
  while (not (Atomic.get ready)) && Unix.gettimeofday () < deadline do
    Unix.sleepf 0.01
  done ;
  if not (Atomic.get ready) then
    fail "test harness's supervisor thread never became ready" ;
  match !slot with
  | Some h -> h
  | None -> fail "test harness never captured its sessions"

let wait_until ~deadline ~msg is_done =
  let rec loop () =
    if is_done () then ()
    else if Unix.gettimeofday () > deadline then fail msg
    else begin
      Unix.sleepf 0.05 ;
      loop ()
    end
  in
  loop ()

let test_all_events_logged_no_raw_token () =
  let capture = start_capture_stderr () in
  let tokens = ref [] in
  let output =
    Fun.protect
      ~finally:(fun () -> ())
      (fun () ->
        let h = start_harness () in
        let token1 = Session.controller_token_string h.session_wire in
        let viewer_token1 = Session.viewer_token_string h.session_wire in
        tokens :=
          [
            token1;
            viewer_token1;
            Session.controller_token_string h.session_idle;
            Session.viewer_token_string h.session_idle;
            Session.controller_token_string h.session_kill;
            Session.viewer_token_string h.session_kill;
          ] ;
        (* Attach (controller): the first-ever attach spawns the
           worker — [event=attach-controller]. *)
        let client1, status1 =
          connect_and_upgrade
            ~port:h.port
            ~path:(Printf.sprintf "/s/%s/ws" token1)
            ~origin:None
            ()
        in
        check string "first controller attach succeeds" "101" status1 ;
        close_client_clean client1 ;
        (* Detach: give the proxy's byte-copy loop time to notice the
           close and run its [on_close] finally (asynchronous, on the
           harness thread's own Eio scheduler). *)
        Unix.sleepf 2.0 ;
        (* Reconnect: the worker is still running (FR-012), so this
           second controller attach is a reconnect, not a fresh
           creation — [event=reconnect]. *)
        let client2, status2 =
          connect_and_upgrade
            ~port:h.port
            ~path:(Printf.sprintf "/s/%s/ws" token1)
            ~origin:None
            ()
        in
        check string "reconnect succeeds" "101" status2 ;
        (* Attach (viewer): a distinct token, a distinct role —
           [event=attach-viewer]. *)
        let clientv, statusv =
          connect_and_upgrade
            ~port:h.port
            ~path:(Printf.sprintf "/s/%s/ws/viewer" viewer_token1)
            ~origin:None
            ()
        in
        check string "viewer attach succeeds" "101" statusv ;
        close_client_clean clientv ;
        (* Auth-fail: an unknown, never-issued candidate token. *)
        let garbage = String.make 64 '0' in
        let client3, status3 =
          connect_and_upgrade
            ~port:h.port
            ~path:(Printf.sprintf "/s/%s/ws" garbage)
            ~origin:None
            ()
        in
        check string "unknown token refused" "403" status3 ;
        close_client_clean client3 ;
        (* Origin-reject: [token1] is genuinely valid, but the Origin
           is not on the allow-list. *)
        let client4, status4 =
          connect_and_upgrade
            ~port:h.port
            ~path:(Printf.sprintf "/s/%s/ws" token1)
            ~origin:(Some "http://evil.example")
            ()
        in
        check string "foreign Origin refused" "403" status4 ;
        close_client_clean client4 ;
        (* Session-end: Ctrl+C always quits, regardless of the page
           (Matrix_main_loop's own global handling, independent of
           [Stub_page]'s empty keymap) — the worker then exits with
           [Serve_worker.quit_exit_code], and
           [Serve_session.reap_and_log] marks the session dead and logs
           [event=session-end]. *)
        send_json client2 {|{"type":"key","key":"C-c"}|} ;
        wait_until
          ~deadline:(Unix.gettimeofday () +. 10.0)
          ~msg:"session never reached session-end after Ctrl+C quit"
          (fun () -> Session.is_dead h.session_wire) ;
        close_client_clean client2 ;
        stop_capture_stderr capture)
  in
  let expect_event name =
    check
      bool
      (Printf.sprintf "an %s audit line was emitted" name)
      true
      (Test_helpers.contains_substring output (Printf.sprintf "event=%s" name))
  in
  List.iter
    expect_event
    [
      "create";
      "attach-controller";
      "detach";
      "reconnect";
      "attach-viewer";
      "auth-fail";
      "origin-reject";
      "idle-kill";
      "explicit-kill";
      "session-end";
    ] ;
  (* The key security assertion (FR-080): every real token this test
     generated must never appear raw anywhere in the captured log —
     only {!Miaou_serve.Serve_audit.hash_token}'s output ever does. *)
  List.iter
    (fun token ->
      check
        bool
        "a real session token never appears raw in the audit log"
        false
        (Test_helpers.contains_substring output token))
    !tokens

let () =
  run
    "serve_audit_log"
    [
      ( "audit_log",
        [
          test_case
            "every event type is logged, no raw token ever appears"
            `Slow
            test_all_events_logged_no_raw_token;
        ] );
    ]
