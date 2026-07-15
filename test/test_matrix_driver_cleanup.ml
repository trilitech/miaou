(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(* Regression tests for crash-ub-fixes slice S6: [Matrix_driver] must run
   terminal cleanup even when the main loop (a crashing page) raises, and
   must re-raise the original exception with its backtrace intact rather
   than losing it behind [Fun.protect]'s [Finally_raised]. These exercise
   [run_with_cleanup] directly (headless — no real terminal/tty needed);
   the end-to-end "terminal usable after crash" behavior is additionally
   covered by the tmux scenario in test/tmux (best-effort, requires a real
   terminal emulator). *)

open Alcotest
module Driver = Miaou_driver_matrix.Matrix_driver

exception Boom of string

let test_cleanup_runs_on_success () =
  let cleanup_ran = ref false in
  let result =
    Driver.run_with_cleanup
      ~cleanup:(fun () -> cleanup_ran := true)
      (fun () -> 42)
  in
  check int "result returned" 42 result ;
  check bool "cleanup ran" true !cleanup_ran

let test_cleanup_runs_and_exception_reraised () =
  let cleanup_ran = ref false in
  let raised =
    try
      ignore
        (Driver.run_with_cleanup
           ~cleanup:(fun () -> cleanup_ran := true)
           (fun () -> raise (Boom "page crashed"))) ;
      None
    with e -> Some e
  in
  check bool "cleanup ran despite exception" true !cleanup_ran ;
  match raised with
  | Some (Boom msg) ->
      check string "original exception preserved" "page crashed" msg
  | Some _ -> fail "wrong exception re-raised"
  | None -> fail "expected exception to propagate"

let test_cleanup_failure_does_not_hide_original_exception () =
  (* A failing cleanup step must not mask the original exception (unlike
     Fun.protect ~finally, which would wrap this in Finally_raised). *)
  let raised =
    try
      ignore
        (Driver.run_with_cleanup
           ~cleanup:(fun () -> raise (Boom "cleanup itself failed"))
           (fun () -> raise (Boom "original failure"))) ;
      None
    with e -> Some e
  in
  match raised with
  | Some (Boom msg) ->
      check string "original exception wins" "original failure" msg
  | Some _ -> fail "wrong exception re-raised"
  | None -> fail "expected exception to propagate"

let () =
  run
    "matrix_driver_cleanup"
    [
      ( "matrix_driver_cleanup",
        [
          test_case "cleanup runs on success" `Quick test_cleanup_runs_on_success;
          test_case
            "cleanup runs and exception re-raised"
            `Quick
            test_cleanup_runs_and_exception_reraised;
          test_case
            "cleanup failure does not hide original exception"
            `Quick
            test_cleanup_failure_does_not_hide_original_exception;
        ] );
    ]
