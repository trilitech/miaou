(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-031/FR-032/FR-033: the intake's named auth-negative suite ("wrong
   password" extended to token-based auth, "cross-session access"),
   extended per the Slice 5 sub-brief with a dead-token scenario. Every
   scenario here must produce a response that is BYTE-IDENTICAL (status
   line, headers, and body) to every other scenario — no oracle
   distinguishing "no such session" from "session exists but the token/
   role is wrong" from "session existed but is now dead" (US-4 scenario
   1, and the spec's own C-7 timing-channel caveat: response *shape*
   uniform, not necessarily true constant-time-over-the-network).

   None of these scenarios ever reaches {!Serve_session.ensure_worker} —
   {!Serve_proxy.resolve} only calls it for a *matched* controller-role
   token, and every scenario below is deliberately a token/role mismatch
   or a dead session — so this file never spawns a worker process and
   needs no [PAGE_SIG]/re-exec entry-point guard, unlike the viewer/
   multi-session test files. *)

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

let find_substring haystack needle =
  let hn = String.length needle in
  let hl = String.length haystack in
  let rec loop i =
    if i + hn > hl then None
    else if String.sub haystack i hn = needle then Some i
    else loop (i + 1)
  in
  loop 0

let content_length_of_head head =
  String.split_on_char '\n' head
  |> List.find_map (fun line ->
      let line = String.trim line in
      match String.index_opt line ':' with
      | Some i
        when String.lowercase_ascii (String.trim (String.sub line 0 i))
             = "content-length" -> (
          try
            Some
              (int_of_string
                 (String.trim
                    (String.sub line (i + 1) (String.length line - i - 1))))
          with _ -> None)
      | Some _ | None -> None)
  |> Option.value ~default:0

(* Reads a full HTTP response (head + body, sized by its own
   [Content-Length]) off [fd]. The server never proactively closes the
   connection after a bounded error response ([Connection: close] is
   only advisory in the header, not an actual [close] syscall on the
   proxy side — see [serve_proxy.ml]'s [respond]), so EOF is not a
   reliable terminator here; a short receive timeout bounds the read
   instead once the expected byte count has been seen. *)
let read_full_response fd =
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO 5.0 ;
  let buf = Buffer.create 512 in
  let chunk = Bytes.create 4096 in
  let rec loop () =
    match Unix.read fd chunk 0 4096 with
    | 0 -> Buffer.contents buf
    | n -> (
        Buffer.add_subbytes buf chunk 0 n ;
        let s = Buffer.contents buf in
        match find_substring s "\r\n\r\n" with
        | None -> loop ()
        | Some idx ->
            let head = String.sub s 0 idx in
            let body_start = idx + 4 in
            let content_length = content_length_of_head head in
            let have = String.length s - body_start in
            if have >= content_length then s else loop ())
    | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
        Buffer.contents buf
  in
  loop ()

let raw_get ~port ~path () =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) ;
  let req =
    Printf.sprintf
      "GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n"
      path
      port
  in
  ignore (Unix.write_substring fd req 0 (String.length req) : int) ;
  let response = read_full_response fd in
  (try Unix.close fd with Unix.Unix_error _ -> ()) ;
  response

let start_harness ~n_sessions =
  let port = free_port () in
  let sessions_slot = ref [] in
  let ready = Atomic.make false in
  let (_ : Thread.t) =
    Thread.create
      (fun () ->
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        let dir = Supervisor.socket_dir ~pid:(Unix.getpid ()) in
        Supervisor.ensure_socket_dir dir ;
        let sessions = Session.create_table () in
        let built =
          List.init n_sessions (fun i ->
              let s =
                Session.create
                  ~env
                  ~socket_path:
                    (Filename.concat dir (Printf.sprintf "auth-neg-%d.sock" i))
              in
              Session.add sessions s ;
              s)
        in
        sessions_slot := built ;
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
  (port, !sessions_slot)

let nonexistent_token = String.concat "" (List.init 64 (fun _ -> "a"))

let flip_last_char s =
  let n = String.length s in
  let c' = if s.[n - 1] = '0' then '1' else '0' in
  String.sub s 0 (n - 1) ^ String.make 1 c'

let two_sessions () =
  let port, sessions = start_harness ~n_sessions:2 in
  match sessions with
  | [a; b] -> (port, a, b)
  | _ -> fail "expected exactly two sessions from the harness"

let test_uniform_failure_responses () =
  let port, session_a, session_b = two_sessions () in
  let baseline =
    raw_get ~port ~path:(Printf.sprintf "/s/%s/" nonexistent_token) ()
  in
  check
    bool
    "the baseline (nonexistent token) response is non-empty"
    true
    (String.length baseline > 0) ;
  (* "no token": the path doesn't even have the /s/<token> shape. *)
  let no_token = raw_get ~port ~path:"/definitely-not-a-session-path" () in
  check
    string
    "wrong-token and no-token responses are byte-identical"
    baseline
    no_token ;
  (* "viewer-token-on-controller-path": session B's viewer-role token
     requesting the controller-only /ws endpoint (FR-032) — a valid
     token, wrong role, must be indistinguishable from no such session
     existing at all. *)
  let viewer_token = Session.viewer_token_string session_b in
  let viewer_on_controller =
    raw_get ~port ~path:(Printf.sprintf "/s/%s/ws" viewer_token) ()
  in
  check
    string
    "viewer-token-on-controller-path response is byte-identical to the \
     wrong-token baseline"
    baseline
    viewer_on_controller ;
  (* "dead token": session A is killed (FR-013's escalating kill marks it
     permanently dead) and its still-well-formed, previously-valid
     controller token must never resurrect (FR-013/US-4 scenario 2). No
     worker was ever spawned for session A, so this exercises the
     no-worker branch of {!Session.kill_worker_escalating} directly. *)
  let controller_token_a = Session.controller_token_string session_a in
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Session.kill_worker_escalating session_a ~sw ~clock:env#clock ~grace:0.01 ;
  let dead_token =
    raw_get ~port ~path:(Printf.sprintf "/s/%s/" controller_token_a) ()
  in
  check
    string
    "dead-token response is byte-identical to the wrong-token baseline"
    baseline
    dead_token ;
  (* "cross-session near-miss": an attacker who has seen session B's
     controller token (e.g. by observing a valid one elsewhere) flips a
     single character to probe for other sessions — this must not
     produce a response that differs from a totally-unrelated random
     guess (no "almost matched" oracle, per the spec's US-4 scenario 1
     and C-7 caveat). *)
  let near_miss = flip_last_char (Session.controller_token_string session_b) in
  let cross_session =
    raw_get ~port ~path:(Printf.sprintf "/s/%s/" near_miss) ()
  in
  check
    string
    "cross-session near-miss response is byte-identical to the wrong-token \
     baseline"
    baseline
    cross_session

let () =
  run
    "serve_auth_negative"
    [
      ( "uniform_failure",
        [
          test_case
            "wrong/no/viewer-on-controller/dead/cross-session tokens are all \
             byte-identical"
            `Quick
            test_uniform_failure_responses;
        ] );
    ]
