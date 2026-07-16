(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-040/FR-041/FR-042/FR-032: server-side viewer read-only enforcement.
   Named scenarios (the intake's "viewer attempting input" negative
   test, extended per the Slice 3 sub-brief):
   - a crafted [{"type":"key",...}] frame from a viewer produces no
     state change and an audit line, and never reaches
     [parse_client_message]/[Matrix_io] (viewer input classification
     happens before those are ever consulted — see web_driver.ml's
     [classify_and_audit_viewer_input]);
   - a viewer's [resize] frame never alters the controller's rendered
     buffer;
   - a viewer-scoped token cannot attach as controller (uniform 403
     refusal, not a silent downgrade/upgrade). *)

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

(* Entry contract: see test_serve_multi_session.ml's identical guard. *)
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

let find_substring haystack needle =
  let hn = String.length needle in
  let hl = String.length haystack in
  let rec loop i =
    if i + hn > hl then None
    else if String.sub haystack i hn = needle then Some i
    else loop (i + 1)
  in
  loop 0

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

let close_client client =
  try Unix.close client.fd with Unix.Unix_error _ -> ()

let send_json client msg =
  let frame = build_client_frame ~opcode:opcode_text msg in
  ignore (Unix.write_substring client.fd frame 0 (String.length frame) : int)

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
    in
    if hdr_len < 0 || String.length s < hdr_len + len then None
    else
      let opcode = Char.code s.[0] land 0x0F in
      let payload = String.sub s hdr_len len in
      client.pending <-
        String.sub s (hdr_len + len) (String.length s - hdr_len - len) ;
      Some (opcode, payload)

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

let wait_for_marker client ~marker ~deadline =
  let acc = Buffer.create 1024 in
  let rec drain_buffered () =
    match try_decode_frame client with
    | Some (0x1, payload) ->
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

let drain_for client ~duration =
  let acc = Buffer.create 1024 in
  let deadline = Unix.gettimeofday () +. duration in
  let rec loop () =
    (match try_decode_frame client with
    | Some (0x1, payload) -> Buffer.add_string acc payload
    | Some (_, _) -> ()
    | None -> ()) ;
    if Unix.gettimeofday () > deadline then Buffer.contents acc
    else begin
      ignore (read_more client ~timeout:0.05 : bool) ;
      loop ()
    end
  in
  loop ()

(* Shared fixture for all three scenarios: one session, its controller
   attached and driven far enough to observe its own baseline state,
   plus a viewer connection attached via the session's *distinct*
   viewer-role token (FR-032 — never the controller token). *)
type fixture = {
  port : int;
  session : Session.t;
  controller : client;
  viewer : client;
}

(* The audit line (FR-041) is emitted via [Printf.eprintf] *inside the
   worker process*, not this test process — a worker inherits whatever
   file descriptor is open as fd 2 at the moment it is spawned
   ([Eio.Process.spawn] with no explicit [~stderr] override). So this
   redirect MUST be installed before the fixture's first controller
   connection (which triggers the lazy spawn, FR-010) for the child to
   inherit the redirected fd; installing it only around the input we
   send would redirect *this* process's fd 2 after the worker already
   captured its own copy of the original one, and observe nothing. *)
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
  let buf = Buffer.create 1024 in
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

(* The session table's own routing/spawn machinery ({!Supervisor.accept_loop})
   must run inside an Eio scheduler, but this test's WebSocket client
   uses plain blocking POSIX sockets (the simplest way to speak the raw
   RFC 6455 wire protocol without fighting cross-domain Eio ownership).
   Driving both halves on the same Eio-scheduled thread would deadlock:
   a blocking [Unix.read] on the client side never yields back to Eio's
   scheduler, so the [accept_loop] fiber servicing that very connection
   would never get to run. Running the Eio side on its own system
   thread — decoupled from the main thread's blocking client calls —
   avoids that. *)
(* Each scenario in this file calls {!start_session_harness} independently
   (three [with_fixture] calls, one per Alcotest test case, in the same
   process); a fixture's worker is never explicitly killed afterwards
   (only its client sockets are closed — the worker legitimately
   survives a detach per FR-012). Reusing the same socket filename
   across scenarios would let a later scenario's controller connect
   race against an *earlier* scenario's still-alive, already-attached
   worker (through nothing more than an accidental path collision),
   which would itself then correctly (if confusingly) 409 as a second
   controller — a self-inflicted false failure, not a real regression.
   A monotonic counter keeps every scenario's socket path distinct. *)
let harness_counter = Atomic.make 0

let start_session_harness () =
  let port = free_port () in
  let n = Atomic.fetch_and_add harness_counter 1 in
  let session_slot = ref None in
  let ready = Atomic.make false in
  let (_ : Thread.t) =
    Thread.create
      (fun () ->
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
        Supervisor.ensure_socket_dir dir ;
        let session =
          Session.create
            ~env
            ~socket_path:
              (Filename.concat dir (Printf.sprintf "viewer-ro-%d.sock" n))
        in
        let sessions = Session.create_table () in
        Session.add sessions session ;
        session_slot := Some session ;
        let listening =
          Eio.Net.listen
            env#net
            ~sw
            ~reuse_addr:true
            ~backlog:16
            (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
        in
        Atomic.set ready true ;
        Supervisor.accept_loop ~sw ~env ~sessions ~max_sessions:1000 listening)
      ()
  in
  let deadline = Unix.gettimeofday () +. 10.0 in
  while (not (Atomic.get ready)) && Unix.gettimeofday () < deadline do
    Unix.sleepf 0.01
  done ;
  if not (Atomic.get ready) then
    fail "test harness's supervisor thread never became ready" ;
  match !session_slot with
  | Some session -> (port, session)
  | None -> fail "test harness never captured its session"

(* [with_fixture f] sets up one session, attaches its controller and its
   distinct-token viewer, then runs [f] against the resulting fixture.
   Any stderr capture MUST wrap the *entire* call (not just the input
   the test scenario later sends) — the fixture's first controller
   connection triggers the lazy worker spawn (FR-010), and a worker
   inherits whatever fd 2 refers to at that moment. *)
let with_fixture f =
  let port, session = start_session_harness () in
  let controller_token = Session.controller_token_string session in
  let viewer_token = Session.viewer_token_string session in
  let controller, controller_status =
    connect_and_upgrade ~port ~path:(Printf.sprintf "/s/%s/ws" controller_token)
  in
  check string "controller upgrade succeeds" "101" controller_status ;
  send_json controller {|{"type":"resize","rows":24,"cols":80}|} ;
  let viewer, viewer_status =
    connect_and_upgrade
      ~port
      ~path:(Printf.sprintf "/s/%s/ws/viewer" viewer_token)
  in
  check string "viewer upgrade succeeds" "101" viewer_status ;
  Fun.protect
    ~finally:(fun () ->
      close_client controller ;
      close_client viewer)
    (fun () -> f {port; session; controller; viewer})

let test_viewer_key_frame_rejected_and_logged () =
  let capture = start_capture_stderr () in
  let stderr_output =
    Fun.protect
      ~finally:(fun () -> ())
      (fun () ->
        with_fixture (fun fx ->
            send_json fx.viewer {|{"type":"key","key":"d"}|} ;
            (* Give the worker's viewer reader fiber time to classify
               and audit the frame. *)
            Unix.sleepf 0.5 ;
            (* The controller's own state must be unaffected: drive it
               once with a real key to confirm N=1 (not N=2, which
               would mean the viewer's key leaked through to the shared
               page state). *)
            send_json fx.controller {|{"type":"key","key":"d"}|} ;
            let deadline = Unix.gettimeofday () +. 10.0 in
            check
              bool
              "controller state reflects exactly its own one keystroke (N=1), \
               not the viewer's rejected one"
              true
              (wait_for_marker fx.controller ~marker:"N=1" ~deadline) ;
            let controller_output = drain_for fx.controller ~duration:1.0 in
            check
              bool
              "controller never advances to N=2 from the viewer's rejected key"
              false
              (Test_helpers.contains_substring controller_output "N=2")) ;
        stop_capture_stderr capture)
  in
  check
    bool
    "an AUDIT viewer-input-rejected line was emitted for the key frame"
    true
    (Test_helpers.contains_substring
       stderr_output
       "AUDIT viewer-input-rejected") ;
  check
    bool
    "the audit line names the rejected frame's type as key"
    true
    (Test_helpers.contains_substring stderr_output "type=key")

let test_viewer_resize_does_not_affect_controller_buffer () =
  (* A viewer resize must never alter the shared session's server-side
     buffer dimensions (FR-042) — only the controller's own reported
     size is authoritative. Send a wildly different size from the
     viewer, then confirm the controller can still drive its page
     normally (no crash/resize-induced corruption) and that the
     rejection was audited exactly like the key case. *)
  let capture = start_capture_stderr () in
  let stderr_output =
    Fun.protect
      ~finally:(fun () -> ())
      (fun () ->
        with_fixture (fun fx ->
            send_json fx.viewer {|{"type":"resize","rows":5,"cols":5}|} ;
            Unix.sleepf 0.5 ;
            send_json fx.controller {|{"type":"key","key":"d"}|} ;
            let deadline = Unix.gettimeofday () +. 10.0 in
            check
              bool
              "controller still renders correctly (its own buffer/size were \
               never touched by the viewer's resize)"
              true
              (wait_for_marker fx.controller ~marker:"N=1" ~deadline)) ;
        stop_capture_stderr capture)
  in
  check
    bool
    "an AUDIT viewer-input-rejected line was emitted for the resize frame"
    true
    (Test_helpers.contains_substring
       stderr_output
       "AUDIT viewer-input-rejected") ;
  check
    bool
    "the audit line names the rejected frame's type as resize"
    true
    (Test_helpers.contains_substring stderr_output "type=resize")

let test_viewer_token_cannot_attach_as_controller () =
  with_fixture (fun fx ->
      let viewer_token = Session.viewer_token_string fx.session in
      let attempt, status =
        connect_and_upgrade
          ~port:fx.port
          ~path:(Printf.sprintf "/s/%s/ws" viewer_token)
      in
      close_client attempt ;
      check
        string
        "a viewer-scoped token attempting the controller endpoint is refused, \
         not silently upgraded/downgraded"
        "403"
        status)

let () =
  run
    "serve_viewer_readonly"
    [
      ( "readonly",
        [
          test_case
            "viewer key frame rejected and logged"
            `Slow
            test_viewer_key_frame_rejected_and_logged;
          test_case
            "viewer resize does not affect controller buffer"
            `Slow
            test_viewer_resize_does_not_affect_controller_buffer;
          test_case
            "viewer token cannot attach as controller"
            `Slow
            test_viewer_token_cannot_attach_as_controller;
        ] );
    ]
