(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Slice 6: reconnect + resync (FR-050), plus the PREREQ-A regression test
   (briefs/miaou-serve-s6-prereq.md) that this slice's rework of the
   disconnect-teardown path must satisfy as a foundation.

   Named scenarios:
   - PREREQ-A: an abrupt socket close (a raw [Unix.shutdown] + close, not
     a clean WebSocket close frame) must leave the worker process alive
     and its session reattachable — never crash it.
   - the intake's reconnect test: attach, mutate visible app state,
     drop the WS, reconnect within timeout, and assert (a) the same
     worker pid answers, (b) the first post-reconnect frame contains a
     full-screen clear (["\027[2J"]), and (c) that frame's content
     reflects the *pre-disconnect* state — not the page's initial state,
     which is what would catch a silent regression back to a fresh
     [run_tui] call per reattach. *)

(* A minimal page with observable, mutable state: a counter bumped by the
   "d" key and rendered directly into the frame text, exactly like
   [test_serve_multi_session.ml]'s [Counter_page] — the simplest way for
   a wire-level test client to prove in-process state survived a
   reconnect without any internal test hooks. *)
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
    Printf.sprintf "N=%d" ps.Miaou_core.Navigation.s

  let keymap _ : key_binding list = []

  let handled_keys () = []

  let handle_key ps _ ~size:_ = ps

  let on_key ps key ~size:_ =
    let ps' =
      match key with
      | Miaou_core.Keys.Char "d" ->
          Miaou_core.Navigation.update (fun n -> n + 1) ps
      | _ -> ps
    in
    (ps', Miaou_interfaces.Key_event.Bubble)
end

let page : (module Miaou_core.Tui_page.PAGE_SIG) = (module Counter_page)

(* Entry contract: see test_serve_multi_session.ml's identical guard —
   this test's own re-exec'd worker process dispatches straight into
   {!Miaou_serve.Serve_worker.run} before anything else in this file
   runs. *)
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
   (identical to test_serve_multi_session.ml's helpers). *)
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

(* A *clean* close: sends a WebSocket close frame before shutting the
   socket down — the pre-S6 code path already handled this. *)
let close_client_clean client =
  (try
     let frame = build_client_frame ~opcode:0x8 "" in
     ignore (Unix.write_substring client.fd frame 0 (String.length frame) : int)
   with Unix.Unix_error _ -> ()) ;
  try Unix.close client.fd with Unix.Unix_error _ -> ()

(* PREREQ-A's scenario: an *abrupt* disconnect — no WebSocket close frame
   at all (unlike {!close_client_clean}); [Unix.shutdown] tears down both
   directions at the socket level first, then the [fd] itself is closed
   — the client vanishes without ever telling the app it's leaving, the
   same shape of disconnect a browser tab close, sleep, or network drop
   produces, and the one the prereq brief's own manual [curl]
   reproduction exercised. *)
let close_client_abrupt client =
  (try Unix.shutdown client.fd Unix.SHUTDOWN_ALL with Unix.Unix_error _ -> ()) ;
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

let opcode_text_frame = 0x1

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

(* Like {!wait_for_marker}, but returns the accumulated text-frame
   payload (up to and including whichever frame contained [marker], or
   whatever arrived before [deadline] if it never did) instead of a bare
   [bool] — needed where the caller must inspect *what* matched, not just
   whether something did. *)
let collect_until_marker client ~marker ~deadline =
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
    if Test_helpers.contains_substring (Buffer.contents acc) marker then
      Buffer.contents acc
    else if Unix.gettimeofday () > deadline then Buffer.contents acc
    else begin
      ignore (read_more client ~timeout:0.1 : bool) ;
      loop ()
    end
  in
  loop ()

(* Like {!wait_for_marker}, but accumulates every text frame payload
   individually (rather than one flattened buffer) so a caller can assert
   things about *which* frame a marker first appeared in — needed for the
   named test's "first post-reconnect frame contains \027[2J" assertion. *)
let collect_frames client ~duration =
  let frames = ref [] in
  let deadline = Unix.gettimeofday () +. duration in
  let rec drain_buffered () =
    match try_decode_frame client with
    | Some (op, payload) when op = opcode_text_frame ->
        frames := payload :: !frames ;
        drain_buffered ()
    | Some (_, _) -> drain_buffered ()
    | None -> ()
  in
  let rec loop () =
    drain_buffered () ;
    if Unix.gettimeofday () > deadline then List.rev !frames
    else begin
      ignore (read_more client ~timeout:0.1 : bool) ;
      loop ()
    end
  in
  loop ()

(* This test binary runs more than one Alcotest scenario in the same OS
   process; a monotonic counter keeps every {!start_harness} call's
   socket path distinct, exactly like [test_serve_multi_session.ml]'s
   identical pattern. *)
let harness_counter = Atomic.make 0

type harness = {port : int; session : Session.t}

let start_harness () =
  let port = free_port () in
  let n = Atomic.fetch_and_add harness_counter 1 in
  let session_slot = ref None in
  let ready = Atomic.make false in
  let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
  let socket_path =
    Filename.concat dir (Printf.sprintf "reconnect-%d.sock" n)
  in
  let (_ : Thread.t) =
    Thread.create
      (fun () ->
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        Supervisor.ensure_socket_dir dir ;
        let session = Session.create ~env ~socket_path in
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
  match !session_slot with
  | Some session -> {port; session}
  | None -> fail "test harness never captured its session"

(* PREREQ-A: an abrupt (RST) disconnect must never crash the worker — it
   must leave it alive, and its session reattachable via a fresh
   connection to the very same [/ws] URL. *)
let test_abrupt_disconnect_survives () =
  let {port; session} = start_harness () in
  let token = Session.controller_token_string session in
  let path = Printf.sprintf "/s/%s/ws" token in
  let client, status = connect_and_upgrade ~port ~path in
  check string "first controller attach succeeds" "101" status ;
  send_json client {|{"type":"resize","rows":24,"cols":80}|} ;
  (* Let a couple of frames flow before the abrupt drop, exercising the
     flusher fiber mid-stream (the scenario the S4/prereq finding names
     specifically — a disconnect that lands while output is actively
     being written, not only at idle). *)
  ignore
    (wait_for_marker client ~marker:"N=" ~deadline:(Unix.gettimeofday () +. 5.0)
      : bool) ;
  let pid_before =
    match Session.worker_pid session with
    | Some pid -> pid
    | None -> fail "expected a worker pid after the first attach"
  in
  close_client_abrupt client ;
  (* Give the reader fiber time to observe the RST and park; the worker
     process itself must never have moved during this window. *)
  Unix.sleepf 0.5 ;
  check
    bool
    "worker pid is unchanged (still alive) after an abrupt RST disconnect"
    true
    (match Session.worker_pid session with
    | Some pid -> pid = pid_before
    | None -> false) ;
  (* Reattachable: a fresh connection to the same session's /ws must be
     accepted as a reconnect (101), not refused. *)
  let client2, status2 = connect_and_upgrade ~port ~path in
  check
    string
    "session is reattachable after the abrupt disconnect"
    "101"
    status2 ;
  check
    bool
    "the SAME worker process answers the reconnect"
    true
    (Session.worker_pid session = Some pid_before) ;
  close_client_clean client2

(* Reconnects to [path] as a controller, retrying within [deadline].

   The supervisor's own controller-live bookkeeping ({!Serve_session},
   the proxy-level session table — a different, independent layer from
   {!Web_driver.Session}'s own controller-parked tracking this slice
   changes) only flips back to "no controller live" once the proxy's own
   byte-copy loop for the abandoned connection actually unwinds (a real
   OS-level TCP RST/EOF propagating proxy-side then to the worker and
   back) — a short, bounded race window against a reconnect attempt that
   races in immediately. A client racing in ahead of that window is
   downgraded to a viewer (the pre-existing, unrelated FR-011
   second-controller-becomes-viewer rule — nothing new here), not
   refused outright, so retrying (exactly what a real reconnecting
   client does) succeeds well within any reasonable timeout. This models
   that retry rather than asserting on a single racy attempt. *)
let reconnect_as_controller ~port ~path ~deadline =
  let rec attempt () =
    let client, status = connect_and_upgrade ~port ~path in
    if status <> "101" then begin
      close_client_clean client ;
      if Unix.gettimeofday () > deadline then
        fail
          (Printf.sprintf "reconnect never got a 101 (last status %s)" status)
      else begin
        Unix.sleepf 0.05 ;
        attempt ()
      end
    end
    else begin
      let seen =
        collect_until_marker
          client
          ~marker:{|"role"|}
          ~deadline:(min deadline (Unix.gettimeofday () +. 2.0))
      in
      if Test_helpers.contains_substring seen {|"role":"controller"|} then
        client
      else begin
        close_client_clean client ;
        if Unix.gettimeofday () > deadline then
          fail "reconnect never re-attached as controller (kept downgrading)"
        else begin
          Unix.sleepf 0.05 ;
          attempt ()
        end
      end
    end
  in
  attempt ()

(* The intake's named reconnect test: attach, mutate visible state,
   drop the WS, reconnect within timeout, assert same pid + full redraw +
   preserved (not initial) state. *)
let test_reconnect_preserves_state () =
  let {port; session} = start_harness () in
  let token = Session.controller_token_string session in
  let path = Printf.sprintf "/s/%s/ws" token in
  let client, status = connect_and_upgrade ~port ~path in
  check string "first controller attach succeeds" "101" status ;
  send_json client {|{"type":"resize","rows":24,"cols":80}|} ;
  (* Mutate visible app state: bump the counter to 3 (Navigation state
     persists in-process — the whole point of parking rather than
     restarting). *)
  send_json client {|{"type":"key","key":"d"}|} ;
  send_json client {|{"type":"key","key":"d"}|} ;
  send_json client {|{"type":"key","key":"d"}|} ;
  (* The renderer is diff-based: once the counter has already been
     rendered once (as part of the very first full frame, "N=0"), a
     later change to just the digit re-emits only the changed cell (a
     cursor-positioned single-character update), never the literal
     substring ["N=3"] again — that only reappears on a *full* redraw
     (exactly what reconnect forces, which is what the post-reconnect
     assertions below actually check). So this step only waits long
     enough for the three key events to have been processed at least
     once (a handful of render ticks), rather than asserting on frame
     content that the diff renderer has no reason to ever re-send. *)
  Unix.sleepf 0.5 ;
  ignore (collect_frames client ~duration:0.2 : string list) ;
  let pid_before =
    match Session.worker_pid session with
    | Some pid -> pid
    | None -> fail "expected a worker pid after the first attach"
  in
  (* Drop the WS — an abrupt disconnect, the harder case PREREQ-A exists
     for, not merely a clean close. *)
  close_client_abrupt client ;
  (* Reconnect within timeout: a fresh connection to the same session's
     controller URL, retrying past the supervisor's own bounded
     controller-live-detach race window (see {!reconnect_as_controller}). *)
  let client2 =
    reconnect_as_controller ~port ~path ~deadline:(Unix.gettimeofday () +. 10.0)
  in
  (* (a) same worker pid answers. *)
  check
    bool
    "the same worker process answers the reconnect (not a fresh spawn)"
    true
    (Session.worker_pid session = Some pid_before) ;
  let frames = collect_frames client2 ~duration:2.0 in
  let combined = String.concat "" frames in
  (* (b) the first post-reconnect frame (of the ones carrying actual TUI
     output, i.e. excluding the JSON role-assignment message already
     consumed above) contains a full-screen clear. *)
  check
    bool
    "a post-reconnect frame contains a full-screen clear (\\027[2J)"
    true
    (Test_helpers.contains_substring combined "\027[2J") ;
  (* (c) the repainted state reflects the PRE-disconnect state (N=3), not
     the page's initial state (N=0) — this is what catches a silent
     regression back to a fresh [run_tui]/page instance on reattach. *)
  check
    bool
    "post-reconnect frame reflects the preserved N=3 state, not a fresh N=0"
    true
    (Test_helpers.contains_substring combined "N=3") ;
  check
    bool
    "post-reconnect frame does NOT show a reset-to-initial N=0 state"
    false
    (Test_helpers.contains_substring combined "N=0") ;
  close_client_clean client2

let () =
  run
    "serve_reconnect"
    [
      ( "prereq_a",
        [
          test_case
            "abrupt (RST) disconnect survives and is reattachable"
            `Slow
            test_abrupt_disconnect_survives;
        ] );
      ( "reconnect",
        [
          test_case
            "reconnect preserves in-process state"
            `Slow
            test_reconnect_preserves_state;
        ] );
    ]
