(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* FR-002: Miaou_serve.run must let an app opt in programmatically and be
   servable. Slice 1 has no supervisor/cancellation, so this drives
   Miaou_serve.run as a real subprocess (serve_stub_worker.exe) and talks
   HTTP to it, rather than calling it in-process (which would block the
   test runner forever in Web_driver's accept loop). *)

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

let curl_status_code ~port =
  let ic =
    Unix.open_process_in
      (Printf.sprintf
         "curl -s -o /dev/null -w '%%{http_code}' http://127.0.0.1:%d/ \
          2>/dev/null"
         port)
  in
  let line = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic) ;
  line

let rec wait_for_200 ~port ~deadline =
  if Unix.gettimeofday () > deadline then "timeout"
  else
    let code = curl_status_code ~port in
    if code = "200" then code
    else begin
      Unix.sleepf 0.05 ;
      wait_for_200 ~port ~deadline
    end

let with_worker ~extra_env ~port f =
  let exe = "./serve_stub_worker.exe" in
  let env =
    Array.append
      (Array.append
         (Unix.environment ())
         [|Printf.sprintf "MIAOU_SERVE_TEST_PORT=%d" port|])
      extra_env
  in
  let pid =
    Unix.create_process_env exe [|exe|] env Unix.stdin Unix.stdout Unix.stderr
  in
  Fun.protect
    ~finally:(fun () ->
      (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) ;
      ignore (Unix.waitpid [] pid))
    f

let test_session_is_servable () =
  let port = free_port () in
  with_worker ~extra_env:[||] ~port (fun () ->
      let code = wait_for_200 ~port ~deadline:(Unix.gettimeofday () +. 5.0) in
      check string "controller page is servable over HTTP" "200" code)

(* H1 regression test: --auth-file (with no --auth-token) must, on its own,
   satisfy the fail-closed bind policy for a non-loopback bind — it must
   not be silently dropped and refused with a message telling the operator
   to do the thing they already did. The file need not exist/be read in
   Slice 1 (see serve_run.mli): only its presence as a path counts. *)
let test_auth_file_alone_permits_public_bind () =
  let port = free_port () in
  with_worker
    ~extra_env:
      [|
        "MIAOU_SERVE_TEST_BIND=0.0.0.0";
        "MIAOU_SERVE_TEST_AUTH_FILE=/nonexistent/serve.token";
      |]
    ~port
    (fun () ->
      let code = wait_for_200 ~port ~deadline:(Unix.gettimeofday () +. 5.0) in
      check
        string
        "public bind with only --auth-file is not fail-closed-refused"
        "200"
        code)

let () =
  run
    "miaou_serve_lib"
    [
      ( "session",
        [
          test_case "servable" `Slow test_session_is_servable;
          test_case
            "auth-file alone permits public bind"
            `Slow
            test_auth_file_alone_permits_public_bind;
        ] );
    ]
