(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-045: WebSocket upgrade Origin allow-list. Named scenarios (per the
   Slice 5 sub-brief): foreign Origin + valid token -> refused (even
   though the session token itself is valid, US-4 scenario 4); missing
   Origin -> allowed (the documented policy, {!Miaou_serve.Serve_origin});
   an explicitly-configured allowed Origin -> 101. A fourth scenario
   checks the same-origin-as-bind default derivation directly. *)

module Marker_page : Miaou_core.Tui_page.PAGE_SIG with type state = unit =
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

  let view _ps ~focus:_ ~size:_ = "origin-check-page"

  let keymap _ : key_binding list = []

  let handled_keys () = []

  let handle_key ps _ ~size:_ = ps

  let on_key ps _key ~size:_ = (ps, Miaou_interfaces.Key_event.Bubble)
end

let page : (module Miaou_core.Tui_page.PAGE_SIG) = (module Marker_page)

(* Entry contract: see test_serve_multi_session.ml's identical guard —
   this test's own re-exec'd worker process needs to dispatch straight
   into {!Miaou_serve.Serve_worker.run} before anything else in this
   file runs. *)
let () =
  match Sys.getenv_opt Miaou_serve.Serve_worker.env_var with
  | Some socket_path ->
      Miaou_serve.Serve_worker.run ~socket_path page ;
      exit 0
  | None -> ()

open Alcotest
module Session = Miaou_serve.Serve_session
module Supervisor = Miaou_serve.Serve_supervisor
module Origin = Miaou_serve.Serve_origin

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
   carrying an [Origin] header (omitted entirely when [origin] is
   [None] — the "missing Origin" scenario), returning the status code
   string from the response's status line. Modeled on
   test_serve_viewer_readonly.ml's identical helper, extended with the
   optional [Origin] header this file needs to drive. *)
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
  (try Unix.close fd with Unix.Unix_error _ -> ()) ;
  match String.split_on_char ' ' head with _ :: code :: _ -> code | _ -> "?"

(* [allowed_origins] is a function of the chosen port, not a plain list:
   [free_port ()] below picks the port the harness will listen on, and
   the "bind-derived default" scenario needs an allow-list computed from
   that very port ({!Origin.default_allowed}), which isn't known until
   after this function has already picked it. *)

(* Each scenario in this file calls [start_harness] in the same OS
   process (same pid, hence the same {!Supervisor.socket_dir}). Since
   PREREQ-B (S6) moved the Origin check ahead of [resolve]/
   [ensure_worker], a refused (foreign-Origin) request no longer spawns
   a worker at all — so a shared, hardcoded socket filename across
   scenarios is no longer safe to assume "not yet bound by a prior
   scenario's worker": an *earlier* scenario whose own request wasn't
   refused (e.g. "missing origin allowed") leaves its worker alive,
   still listening on that path (FR-012, worker survives detach) — a
   later scenario's own fresh spawn attempt at the very same path would
   either collide, or (worse) silently reach the wrong, older worker
   process instead of its own. A monotonic counter keeps every
   {!start_harness} call's socket path distinct, mirroring
   [test_serve_multi_session.ml]'s identical [harness_counter] pattern. *)
let harness_counter = Atomic.make 0

let start_harness ~allowed_origins =
  let port = free_port () in
  let allowed_origins = allowed_origins ~port in
  let session_slot = ref None in
  let ready = Atomic.make false in
  let n = Atomic.fetch_and_add harness_counter 1 in
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
              (Filename.concat dir (Printf.sprintf "origin-check-%d.sock" n))
            ~now:(Eio.Time.now env#clock)
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
        Supervisor.accept_loop
          ~sw
          ~env
          ~sessions
          ~max_sessions:1000
          ~allowed_origins
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
  | Some session -> (port, session)
  | None -> fail "test harness never captured its session"

let test_foreign_origin_refused () =
  let port, session =
    start_harness ~allowed_origins:(fun ~port:_ -> ["http://allowed.example"])
  in
  let token = Session.controller_token_string session in
  let status =
    connect_and_upgrade
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token)
      ~origin:(Some "http://evil.example")
      ()
  in
  check
    string
    "a foreign Origin is refused even with an otherwise-valid session token"
    "403"
    status

let test_missing_origin_allowed () =
  (* deliberately empty: proves the decision is "absent => allow",
     not "absent => fall back to the default list". *)
  let port, session = start_harness ~allowed_origins:(fun ~port:_ -> []) in
  let token = Session.controller_token_string session in
  let status =
    connect_and_upgrade
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token)
      ~origin:None
      ()
  in
  check
    string
    "a request with no Origin header at all is allowed (documented policy)"
    "101"
    status

let test_allowed_origin_succeeds () =
  let extra = "http://allowed.example" in
  let port, session = start_harness ~allowed_origins:(fun ~port:_ -> [extra]) in
  let token = Session.controller_token_string session in
  let status =
    connect_and_upgrade
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token)
      ~origin:(Some extra)
      ()
  in
  check string "an explicitly-allowed Origin succeeds" "101" status

let test_bind_derived_default_origin_succeeds () =
  (* The bind-derived default allow-list depends on the harness's own
     port, which [start_harness] only picks internally — so
     [allowed_origins] is passed as a function of that port rather than
     a plain list (a list computed from a port picked up front would
     almost certainly not match the harness's actual port). This mirrors
     what {!Serve_supervisor.run} itself does with
     {!Origin.default_allowed} in production. *)
  let port, session =
    start_harness ~allowed_origins:(fun ~port ->
        Origin.default_allowed ~bind:"127.0.0.1" ~port)
  in
  let allowed_origin =
    match Origin.default_allowed ~bind:"127.0.0.1" ~port with
    | o :: _ -> o
    | [] -> Alcotest.fail "default_allowed returned no origin"
  in
  let token = Session.controller_token_string session in
  let status =
    connect_and_upgrade
      ~port
      ~path:(Printf.sprintf "/s/%s/ws" token)
      ~origin:(Some allowed_origin)
      ()
  in
  check
    string
    "an Origin matching the same-origin-as-bind default succeeds"
    "101"
    status

let () =
  run
    "serve_origin_check"
    [
      ( "origin_check",
        [
          test_case "foreign origin refused" `Quick test_foreign_origin_refused;
          test_case "missing origin allowed" `Quick test_missing_origin_allowed;
          test_case
            "allowed origin succeeds"
            `Quick
            test_allowed_origin_succeeds;
          test_case
            "bind-derived default origin succeeds"
            `Quick
            test_bind_derived_default_origin_succeeds;
        ] );
    ]
