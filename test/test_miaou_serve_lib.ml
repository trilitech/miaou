(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-002: Miaou_serve.run must let an app opt in programmatically and be
   servable. Slice 2 replaces Slice 1's interim query-string bridge with a
   real supervisor + worker + byte proxy: this test drives
   serve_stub_worker.exe as a real subprocess (it becomes the
   *supervisor*, since MIAOU_SERVE_WORKER_SOCKET is unset for the initial
   invocation), captures its stderr to recover the FR-030 path-form
   session URL ([http://<bind>:<port>/s/<token>/]) it prints once its
   worker (a re-exec of the same binary, spawned by the supervisor) is
   reachable, then curls that URL through the supervisor's byte proxy. *)

open Alcotest

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

let curl_status_code url =
  let ic =
    Unix.open_process_in
      (Printf.sprintf
         "curl -s -o /dev/null -w '%%{http_code}' %s 2>/dev/null"
         url)
  in
  let line = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic) ;
  line

let rec wait_for_200 ~url ~deadline =
  if Unix.gettimeofday () > deadline then "timeout"
  else
    let code = curl_status_code url in
    if code = "200" then code
    else begin
      Unix.sleepf 0.05 ;
      wait_for_200 ~url ~deadline
    end

(* Read one '\n'-terminated line from [fd], never blocking past
   [deadline]. Returns [None] on timeout or EOF. *)
let read_line_with_timeout fd ~deadline =
  let byte = Bytes.create 1 in
  let line = Buffer.create 128 in
  let rec loop () =
    let now = Unix.gettimeofday () in
    if now > deadline then None
    else
      match Unix.select [fd] [] [] (deadline -. now) with
      | [], _, _ -> None
      | _ -> (
          match Unix.read fd byte 0 1 with
          | 0 -> None
          | _ ->
              if Bytes.get byte 0 = '\n' then Some (Buffer.contents line)
              else begin
                Buffer.add_char line (Bytes.get byte 0) ;
                loop ()
              end
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop ())
  in
  loop ()

let session_url_prefix = "[miaou serve] session ready: "

(* Scan the supervisor's stderr for its "session ready: <url>" line
   (serve_supervisor.ml), bounded by [deadline]. *)
let rec find_session_url fd ~deadline =
  match read_line_with_timeout fd ~deadline with
  | None -> None
  | Some line ->
      let plen = String.length session_url_prefix in
      if
        String.length line >= plen
        && String.sub line 0 plen = session_url_prefix
      then Some (String.trim (String.sub line plen (String.length line - plen)))
      else find_session_url fd ~deadline

(* Extract just the token from a "http://<bind>:<port>/s/<token>/" URL and
   rebuild it against 127.0.0.1 — the supervisor may have bound
   ["0.0.0.0"], which is not a portable curl target on every platform,
   whereas loopback always reaches a socket bound to all interfaces. *)
let loopback_url_of ~port url =
  match String.index_opt url '/' with
  | None -> None
  | Some _ -> (
      let marker = "/s/" in
      match
        let rec find_from i =
          if i + String.length marker > String.length url then None
          else if String.sub url i (String.length marker) = marker then Some i
          else find_from (i + 1)
        in
        find_from 0
      with
      | None -> None
      | Some i ->
          let rest = String.sub url i (String.length url - i) in
          Some (Printf.sprintf "http://127.0.0.1:%d%s" port rest))

(* Parse "http://host:port/path" — just enough to drive raw HTTP/WS
   requests without pulling in a URL library. *)
let parse_http_url url =
  let prefix = "http://" in
  let plen = String.length prefix in
  if String.length url < plen || String.sub url 0 plen <> prefix then None
  else
    let rest = String.sub url plen (String.length url - plen) in
    match String.index_opt rest '/' with
    | None -> None
    | Some i -> (
        let hostport = String.sub rest 0 i in
        let path = String.sub rest i (String.length rest - i) in
        match String.index_opt hostport ':' with
        | None -> None
        | Some j -> (
            let host = String.sub hostport 0 j in
            match
              int_of_string_opt
                (String.sub hostport (j + 1) (String.length hostport - j - 1))
            with
            | Some port -> Some (host, port, path)
            | None -> None))

(* Attempt a raw RFC 6455 WebSocket upgrade to [url] and return the HTTP
   status code of the response ("101" on success), or a synthetic error
   code on any failure (bad URL, connect failure, timeout). This is the
   browser-realistic check the HIGH-priority fix is about: a real browser
   resolves client.js's relative `wsPath` against the *page's own
   location* (see client.js's [resolvePath]), so [url] here must be
   exactly what that resolution would produce — not the token-form
   [/s/<token>/ws] path hit directly, which would mask a bug where the
   asset/WS paths are absolute and therefore resolve to the wrong
   (unprefixed) URL once served through the supervisor's proxy. *)
let ws_upgrade_status url =
  match parse_http_url url with
  | None -> "bad-url"
  | Some (host, port, path) -> (
      try
        let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
        Fun.protect
          ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
          (fun () ->
            Unix.setsockopt_float fd Unix.SO_RCVTIMEO 5.0 ;
            Unix.connect
              fd
              (Unix.ADDR_INET (Unix.inet_addr_of_string host, port)) ;
            let req =
              Printf.sprintf
                "GET %s HTTP/1.1\r\n\
                 Host: %s:%d\r\n\
                 Upgrade: websocket\r\n\
                 Connection: Upgrade\r\n\
                 Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                 Sec-WebSocket-Version: 13\r\n\
                 \r\n"
                path
                host
                port
            in
            ignore (Unix.write_substring fd req 0 (String.length req) : int) ;
            let buf = Bytes.create 512 in
            let n = Unix.read fd buf 0 512 in
            let resp = Bytes.sub_string buf 0 n in
            match String.split_on_char ' ' resp with
            | _ :: code :: _ -> code
            | _ -> "bad-response")
      with _ -> "error")

let with_worker ~extra_env ~port f =
  let exe = "./serve_stub_worker.exe" in
  let env =
    Array.append
      (Array.append
         (Unix.environment ())
         [|Printf.sprintf "MIAOU_SERVE_TEST_PORT=%d" port|])
      extra_env
  in
  let stderr_r, stderr_w = Unix.pipe () in
  let pid =
    Unix.create_process_env exe [|exe|] env Unix.stdin Unix.stdout stderr_w
  in
  Unix.close stderr_w ;
  Fun.protect
    ~finally:(fun () ->
      (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) ;
      ignore (Unix.waitpid [] pid) ;
      try Unix.close stderr_r with Unix.Unix_error _ -> ())
    (fun () -> f stderr_r)

let test_session_is_servable () =
  let port = free_port () in
  with_worker ~extra_env:[||] ~port (fun stderr_r ->
      match
        find_session_url stderr_r ~deadline:(Unix.gettimeofday () +. 10.0)
      with
      | None -> fail "supervisor never printed a session URL"
      | Some url -> (
          match loopback_url_of ~port url with
          | None ->
              fail
                (Printf.sprintf "session URL not in /s/<token>/ form: %s" url)
          | Some curl_url ->
              let code =
                wait_for_200
                  ~url:curl_url
                  ~deadline:(Unix.gettimeofday () +. 5.0)
              in
              check
                string
                "controller page is servable over HTTP via /s/<token>/"
                "200"
                code))

(* Browser-realistic end-to-end check (the HIGH-priority fix): the
   controller page's script/WS references are relative
   (`<script src="client.js">`, `wsPath: 'ws'` resolved against
   location.pathname — see static/index.html and static/client.js), so
   when served under the supervisor's [/s/<token>/] prefix they must
   resolve to [/s/<token>/client.js] and [/s/<token>/ws], not to
   [/client.js]/[/ws] at the proxy's root (which would 403, since the
   proxy's routing requires the [/s/<token>] prefix — this is exactly
   what masked the bug: hitting [/s/<token>/ws] directly in earlier
   testing always worked, because that request was already correctly
   prefixed by the test itself, not derived by client-side code). *)
let test_client_asset_and_ws_resolve_under_session_prefix () =
  let port = free_port () in
  with_worker ~extra_env:[||] ~port (fun stderr_r ->
      match
        find_session_url stderr_r ~deadline:(Unix.gettimeofday () +. 10.0)
      with
      | None -> fail "supervisor never printed a session URL"
      | Some url -> (
          match loopback_url_of ~port url with
          | None ->
              fail
                (Printf.sprintf "session URL not in /s/<token>/ form: %s" url)
          | Some base_url ->
              let html_code =
                wait_for_200
                  ~url:base_url
                  ~deadline:(Unix.gettimeofday () +. 5.0)
              in
              check string "controller HTML is servable" "200" html_code ;
              (* base_url already ends in '/' (the printed session URL
                 does); a real browser's relative "client.js"/"ws"
                 resolve against exactly that directory. *)
              let asset_code = curl_status_code (base_url ^ "client.js") in
              check
                string
                "client.js is servable at the session-relative path a \
                 browser's <script src=\"client.js\"> actually resolves to"
                "200"
                asset_code ;
              let ws_code = ws_upgrade_status (base_url ^ "ws") in
              check
                string
                "WS upgrade succeeds at the session-relative path client.js's \
                 resolvePath('ws') actually derives"
                "101"
                ws_code))

(* H1 regression test: --auth-file (with no --auth-token) must, on its own,
   satisfy the fail-closed bind policy for a non-loopback bind — it must
   not be silently dropped and refused with a message telling the operator
   to do the thing they already did. The file need not exist/be read in
   Slice 2 (see serve_run.mli): only its presence as a path counts. *)
let test_auth_file_alone_permits_public_bind () =
  let port = free_port () in
  with_worker
    ~extra_env:
      [|
        "MIAOU_SERVE_TEST_BIND=0.0.0.0";
        "MIAOU_SERVE_TEST_AUTH_FILE=/nonexistent/serve.token";
      |]
    ~port
    (fun stderr_r ->
      match
        find_session_url stderr_r ~deadline:(Unix.gettimeofday () +. 10.0)
      with
      | None -> fail "supervisor never printed a session URL"
      | Some url -> (
          match loopback_url_of ~port url with
          | None ->
              fail
                (Printf.sprintf "session URL not in /s/<token>/ form: %s" url)
          | Some curl_url ->
              let code =
                wait_for_200
                  ~url:curl_url
                  ~deadline:(Unix.gettimeofday () +. 5.0)
              in
              check
                string
                "public bind with only --auth-file is not fail-closed-refused"
                "200"
                code))

let () =
  run
    "miaou_serve_lib"
    [
      ( "session",
        [
          test_case "servable" `Slow test_session_is_servable;
          test_case
            "client asset and WS resolve under session prefix"
            `Slow
            test_client_asset_and_ws_resolve_under_session_prefix;
          test_case
            "auth-file alone permits public bind"
            `Slow
            test_auth_file_alone_permits_public_bind;
        ] );
    ]
