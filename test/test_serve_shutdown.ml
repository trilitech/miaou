(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-090 (Slice 7): graceful shutdown. Named scenario:
   "SIGTERM-drains-and-exits-cleanly" — SIGTERM'ing a real supervisor
   process (spawned as a genuine OS subprocess, reusing
   test_miaou_serve_lib.ml's [serve_stub_worker.exe] harness/pattern) that
   has already spawned at least one worker (attached as controller once,
   so its own child process genuinely exists — not a vacuous
   "zero-sessions" shutdown) must leave zero surviving child processes
   and no leftover socket directory. *)

open Alcotest
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

(* Identical to test_miaou_serve_lib.ml's own line-reader: reads one
   '\n'-terminated line from [fd], never blocking past [deadline]. *)
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

(* Extract just the [/s/<token>/] tail from a printed session URL and
   rebuild it against 127.0.0.1:[port] — mirrors
   test_miaou_serve_lib.ml's identical helper. *)
let loopback_url_of ~port url =
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
      Some (Printf.sprintf "http://127.0.0.1:%d%s" port rest)

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

(* Opens a real WebSocket upgrade against [url] and leaves the socket
   open (fd returned), so the supervisor genuinely has a live controller
   connection — and therefore a genuinely-spawned worker process — at
   the moment it is SIGTERM'd below, exercising the actual drain path
   rather than a no-op "zero sessions" shutdown. *)
let open_ws_and_leave_connected url =
  match parse_http_url url with
  | None -> fail "bad session URL"
  | Some (host, port, path) ->
      let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      Unix.setsockopt_float fd Unix.SO_RCVTIMEO 5.0 ;
      Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_of_string host, port)) ;
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
      let status =
        match String.split_on_char ' ' resp with
        | _ :: code :: _ -> code
        | _ -> "bad-response"
      in
      (fd, status)

(* [pgrep -P pid] — the direct-child pids of [pid], as a string list
   ([] if none, or if [pid] no longer exists at all). This is the
   brief's own named mechanism, kept as one line of evidence, but it is
   NOT by itself a reliable post-mortem orphan check: once the
   supervisor process has actually exited, any child still alive at
   that instant is reparented (to init / the nearest subreaper) as part
   of the very same [exit] syscall, so [pgrep -P <now-dead-pid>] finds
   nothing regardless of whether an orphan survived — reparenting, not
   death, is what removes it from this listing. The rigorous check
   below ({!still_alive}) instead captures each child's pid up front
   (while the supervisor is still alive to legitimately own them) and
   directly probes *that* pid's liveness after shutdown, which
   reparenting cannot hide. *)
let child_pids pid =
  let ic =
    Unix.open_process_in (Printf.sprintf "pgrep -P %d 2>/dev/null" pid)
  in
  let rec read_lines acc =
    match input_line ic with
    | line -> read_lines (line :: acc)
    | exception End_of_file -> List.rev acc
  in
  let lines = read_lines [] in
  ignore (Unix.close_process_in ic) ;
  lines

let still_alive pid_str =
  match int_of_string_opt pid_str with
  | None -> false
  | Some pid -> (
      try
        Unix.kill pid 0 ;
        true
      with
      | Unix.Unix_error (Unix.ESRCH, _, _) -> false
      | Unix.Unix_error _ -> true)

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

let test_sigterm_drains_and_exits_cleanly () =
  let port = free_port () in
  let exe = "./serve_stub_worker.exe" in
  let env =
    Array.append
      (Unix.environment ())
      [|Printf.sprintf "MIAOU_SERVE_TEST_PORT=%d" port|]
  in
  let stderr_r, stderr_w = Unix.pipe () in
  let supervisor_pid =
    Unix.create_process_env exe [|exe|] env Unix.stdin Unix.stdout stderr_w
  in
  Unix.close stderr_w ;
  Fun.protect
    ~finally:(fun () ->
      (try Unix.kill supervisor_pid Sys.sigkill with Unix.Unix_error _ -> ()) ;
      (try ignore (Unix.waitpid [] supervisor_pid : int * Unix.process_status)
       with Unix.Unix_error _ -> ()) ;
      try Unix.close stderr_r with Unix.Unix_error _ -> ())
    (fun () ->
      match
        find_session_url stderr_r ~deadline:(Unix.gettimeofday () +. 10.0)
      with
      | None -> fail "supervisor never printed a session URL"
      | Some url -> (
          match loopback_url_of ~port url with
          | None -> fail "session URL not in /s/<token>/ form"
          | Some base_url -> (
              let ws_fd, status =
                open_ws_and_leave_connected (base_url ^ "ws")
              in
              check string "controller WS upgrade succeeds" "101" status ;
              (* The worker is spawned lazily on this very first
                 controller attach (FR-010); give the supervisor a
                 moment to actually fork/exec + become ready. *)
              wait_until
                ~deadline:(Unix.gettimeofday () +. 5.0)
                ~msg:"supervisor never spawned a worker child process"
                (fun () -> child_pids supervisor_pid <> []) ;
              let children_before = child_pids supervisor_pid in
              check
                bool
                "supervisor has at least one live child before shutdown"
                true
                (children_before <> []) ;
              let socket_dir = Supervisor.socket_dir ~pid:supervisor_pid in
              check
                bool
                "socket directory exists before shutdown"
                true
                (Sys.file_exists socket_dir) ;
              Unix.kill supervisor_pid Sys.sigterm ;
              (* Bounded wait for the supervisor process itself to
                 exit — FR-090 requires it to actually drain and call
                 [exit 0], not linger. *)
              wait_until
                ~deadline:(Unix.gettimeofday () +. 15.0)
                ~msg:"supervisor process did not exit after SIGTERM"
                (fun () ->
                  match Unix.waitpid [Unix.WNOHANG] supervisor_pid with
                  | 0, _ -> false
                  | _ -> true) ;
              (* Brief's own named mechanism (see {!child_pids}'s doc
                 comment on why this alone is not conclusive). *)
              check
                bool
                "pgrep -P reports no children of the (now-exited) supervisor \
                 pid"
                true
                (child_pids supervisor_pid = []) ;
              (* The rigorous check: every pid that WAS a live child
                 while the supervisor was still alive must now actually
                 be dead — reparenting cannot hide a survivor from this,
                 unlike the pgrep-only check above. *)
              let survivors = List.filter still_alive children_before in
              check
                bool
                "no orphaned worker process survives supervisor shutdown \
                 (checked by pid liveness, immune to reparenting)"
                true
                (survivors = []) ;
              check
                bool
                "no leftover socket directory after graceful shutdown"
                false
                (Sys.file_exists socket_dir) ;
              try Unix.close ws_fd with Unix.Unix_error _ -> ())))

let () =
  run
    "serve_shutdown"
    [
      ( "shutdown",
        [
          test_case
            "SIGTERM drains and exits cleanly"
            `Slow
            test_sigterm_drains_and_exits_cleanly;
        ] );
    ]
