(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-060/FR-061 (Slice 8): TLS is not terminated in-process — v1's only
   documented path is a reverse proxy in front of a loopback-bound
   listener (docs/serve.md). This test does not re-litigate the pure
   fail-closed decision table already covered by
   {!Miaou_serve.Serve_policy.check} in test_serve_auth_default.ml
   (loopback-allowed / insecure-override-allowed / auth-allowed as pure
   [check] calls); instead it drives the real subprocess boundary
   (reusing test_miaou_serve_lib.ml/test_serve_shutdown.ml's
   [serve_stub_worker.exe] harness) to assert the two things that are
   *not* pure decision logic and therefore not covered anywhere else:
   (1) a real supervisor process, not just the [check] function, refuses
   to bind [0.0.0.0] with no auth and no override, and (2) passing
   [--insecure-allow-plaintext-external] (surfaced to the stub worker via
   MIAOU_SERVE_TEST_INSECURE, wired in this slice) makes the real
   supervisor process print the loud, non-persisted, per-invocation
   warning — never just silently proceed. *)

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

(* Identical helper to test_miaou_serve_lib.ml/test_serve_shutdown.ml: read
   one '\n'-terminated line from [fd], never blocking past [deadline]. *)
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

(* Reads lines from [fd] until [deadline], collecting all of them (rather
   than stopping at the first match like the other tests' single-line
   finders) so a caller can search the whole captured prefix for a
   substring. *)
let read_lines_until ~deadline fd =
  let rec loop acc =
    match read_line_with_timeout fd ~deadline with
    | None -> List.rev acc
    | Some line -> loop (line :: acc)
  in
  loop []

let contains_substring ~needle haystack =
  let nlen = String.length needle in
  let hlen = String.length haystack in
  let at i = i + nlen <= hlen && String.sub haystack i nlen = needle in
  let rec find i = i <= hlen - nlen && (at i || find (i + 1)) in
  nlen = 0 || (hlen >= nlen && find 0)

let any_line_contains ~needle lines =
  List.exists (contains_substring ~needle) lines

let spawn_stub_worker ~port ~bind ~insecure =
  let exe = "./serve_stub_worker.exe" in
  let env =
    Array.append
      (Unix.environment ())
      [|
        Printf.sprintf "MIAOU_SERVE_TEST_PORT=%d" port;
        Printf.sprintf "MIAOU_SERVE_TEST_BIND=%s" bind;
        Printf.sprintf "MIAOU_SERVE_TEST_INSECURE=%b" insecure;
      |]
  in
  let stderr_r, stderr_w = Unix.pipe () in
  let pid =
    Unix.create_process_env exe [|exe|] env Unix.stdin Unix.stdout stderr_w
  in
  Unix.close stderr_w ;
  (pid, stderr_r)

let kill_and_reap pid =
  (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) ;
  try ignore (Unix.waitpid [] pid : int * Unix.process_status)
  with Unix.Unix_error _ -> ()

(* 0.0.0.0 + no auth + no --insecure-allow-plaintext-external: the real
   supervisor process must refuse to bind and exit non-zero, never
   reaching the accept loop — composes with (does not duplicate) the
   pure {!Miaou_serve.Serve_policy.check} refusal already asserted in
   test_serve_auth_default.ml, at the actual process boundary instead. *)
let test_public_bind_no_auth_no_flag_fails_closed () =
  let port = free_port () in
  let pid, stderr_r = spawn_stub_worker ~port ~bind:"0.0.0.0" ~insecure:false in
  Fun.protect
    ~finally:(fun () ->
      kill_and_reap pid ;
      try Unix.close stderr_r with Unix.Unix_error _ -> ())
    (fun () ->
      let _, status = Unix.waitpid [] pid in
      (match status with
      | Unix.WEXITED 0 -> fail "supervisor exited 0 but should have refused"
      | Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> ()) ;
      (* The process has already exited, so all its stderr output is
         already fully buffered in the pipe — this deadline only bounds
         the (non-blocking, in practice) drain of that buffer. *)
      let lines =
        read_lines_until ~deadline:(Unix.gettimeofday () +. 2.0) stderr_r
      in
      check
        bool
        "refusal output mentions the fail-closed policy"
        true
        (any_line_contains ~needle:"fail-closed" lines
        || any_line_contains ~needle:"Bind_refused" lines))

let session_url_prefix = "[miaou serve] session ready: "

let has_session_url lines =
  List.exists
    (fun line ->
      let plen = String.length session_url_prefix in
      String.length line >= plen && String.sub line 0 plen = session_url_prefix)
    lines

(* 0.0.0.0 + no auth + --insecure-allow-plaintext-external: allowed, but
   MUST print the loud per-invocation warning every run (never silently).
   This is the one assertion genuinely new to this slice — the flag
   itself and the pure allow/refuse decision are already covered
   elsewhere. *)
let test_insecure_flag_allows_and_warns () =
  let port = free_port () in
  let pid, stderr_r = spawn_stub_worker ~port ~bind:"0.0.0.0" ~insecure:true in
  Fun.protect
    ~finally:(fun () ->
      kill_and_reap pid ;
      try Unix.close stderr_r with Unix.Unix_error _ -> ())
    (fun () ->
      let lines =
        read_lines_until ~deadline:(Unix.gettimeofday () +. 10.0) stderr_r
      in
      check
        bool
        "supervisor reached the accept loop (session URL printed)"
        true
        (has_session_url lines) ;
      check
        bool
        "loud WARNING is emitted for --insecure-allow-plaintext-external"
        true
        (any_line_contains ~needle:"WARNING" lines
        && any_line_contains ~needle:"insecure-allow-plaintext-external" lines))

(* Loopback bind, no auth, no flag: allowed, and the insecure warning
   must NOT be printed (it only fires when the flag is actually passed —
   never persisted, never emitted unconditionally). *)
let test_loopback_allowed_without_warning () =
  let port = free_port () in
  let pid, stderr_r =
    spawn_stub_worker ~port ~bind:"127.0.0.1" ~insecure:false
  in
  Fun.protect
    ~finally:(fun () ->
      kill_and_reap pid ;
      try Unix.close stderr_r with Unix.Unix_error _ -> ())
    (fun () ->
      let lines =
        read_lines_until ~deadline:(Unix.gettimeofday () +. 10.0) stderr_r
      in
      check
        bool
        "supervisor reached the accept loop (session URL printed)"
        true
        (has_session_url lines) ;
      check
        bool
        "no insecure-plaintext warning printed for a loopback bind"
        false
        (any_line_contains ~needle:"WARNING" lines))

let () =
  run
    "serve_tls_policy"
    [
      ( "tls-policy",
        [
          test_case
            "0.0.0.0, no auth, no flag: fails closed"
            `Slow
            test_public_bind_no_auth_no_flag_fails_closed;
          test_case
            "0.0.0.0 + --insecure-allow-plaintext-external: allowed + warning \
             emitted"
            `Slow
            test_insecure_flag_allows_and_warns;
          test_case
            "loopback: allowed, no warning"
            `Slow
            test_loopback_allowed_without_warning;
        ] );
    ]
