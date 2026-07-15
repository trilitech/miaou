open Alcotest
module Debounce = Miaou_helpers.Debounce

(* A controllable fake clock: tests advance it explicitly instead of
   sleeping in wall-clock time, so debounce boundary behavior is exercised
   deterministically and instantly. *)
let fake_clock () =
  (* Track elapsed time in integer milliseconds internally and only convert
     to seconds when read, so repeated [advance_ms] calls never accumulate
     floating-point rounding error at a debounce boundary. *)
  let t_ms = ref 0 in
  let now () = float_of_int !t_ms /. 1000.0 in
  let advance_ms ms = t_ms := !t_ms + ms in
  (now, advance_ms)

let test_not_ready_before_mark () =
  let now, _ = fake_clock () in
  let d = Debounce.create ~debounce_ms:100 ~now () in
  check bool "no pending event before any mark" false (Debounce.is_ready d) ;
  check
    bool
    "has_pending is false before any mark"
    false
    (Debounce.has_pending d)

let test_not_ready_immediately_after_mark () =
  let now, _ = fake_clock () in
  let d = Debounce.create ~debounce_ms:100 ~now () in
  Debounce.mark d ;
  check bool "pending right after mark" true (Debounce.has_pending d) ;
  check bool "not ready with zero elapsed time" false (Debounce.is_ready d)

let test_boundary_exact_debounce_ms_is_ready () =
  let now, advance_ms = fake_clock () in
  let d = Debounce.create ~debounce_ms:100 ~now () in
  Debounce.mark d ;
  advance_ms 99 ;
  check bool "not yet ready 1ms before the boundary" false (Debounce.is_ready d) ;
  advance_ms 1 ;
  check
    bool
    "ready exactly at the debounce_ms boundary"
    true
    (Debounce.is_ready d)

let test_mark_resets_the_timer () =
  let now, advance_ms = fake_clock () in
  let d = Debounce.create ~debounce_ms:100 ~now () in
  Debounce.mark d ;
  advance_ms 80 ;
  (* A fresh event before the debounce period elapsed resets the clock;
     the original 80ms of elapsed time must not carry over. *)
  Debounce.mark d ;
  advance_ms 80 ;
  check
    bool
    "reset by a later mark, still short of the new boundary"
    false
    (Debounce.is_ready d) ;
  (* Comfortably past the 100ms boundary rather than exactly on it: the
     exact-boundary case is already covered by
     [test_boundary_exact_debounce_ms_is_ready], and floating-point
     subtraction of two non-trivial millisecond timestamps can land a
     hair under the boundary even when conceptually "100ms elapsed". *)
  advance_ms 30 ;
  check
    bool
    "ready comfortably past the boundary after the most recent mark"
    true
    (Debounce.is_ready d)

let test_clear_resets_pending () =
  let now, advance_ms = fake_clock () in
  let d = Debounce.create ~debounce_ms:50 ~now () in
  Debounce.mark d ;
  advance_ms 50 ;
  check bool "ready before clear" true (Debounce.is_ready d) ;
  Debounce.clear d ;
  check bool "not pending after clear" false (Debounce.has_pending d) ;
  check
    bool
    "not ready after clear (nothing pending)"
    false
    (Debounce.is_ready d)

let test_check_and_clear_is_idempotent_once () =
  let now, advance_ms = fake_clock () in
  let d = Debounce.create ~debounce_ms:50 ~now () in
  Debounce.mark d ;
  advance_ms 50 ;
  check bool "first check_and_clear fires" true (Debounce.check_and_clear d) ;
  check
    bool
    "second check_and_clear does not fire again"
    false
    (Debounce.check_and_clear d)

let test_debounce_ms_accessor () =
  let d = Debounce.create ~debounce_ms:333 () in
  check
    int
    "debounce_ms returns the configured value"
    333
    (Debounce.debounce_ms d)

let test_default_debounce_ms_is_250 () =
  let d = Debounce.create () in
  check int "default debounce_ms is 250" 250 (Debounce.debounce_ms d)

let () =
  run
    "debounce"
    [
      ( "debounce",
        [
          test_case "not ready before any mark" `Quick test_not_ready_before_mark;
          test_case
            "not ready immediately after mark"
            `Quick
            test_not_ready_immediately_after_mark;
          test_case
            "boundary: exactly debounce_ms is ready"
            `Quick
            test_boundary_exact_debounce_ms_is_ready;
          test_case
            "a later mark resets the timer"
            `Quick
            test_mark_resets_the_timer;
          test_case
            "clear resets pending state"
            `Quick
            test_clear_resets_pending;
          test_case
            "check_and_clear fires once"
            `Quick
            test_check_and_clear_is_idempotent_once;
          test_case "debounce_ms accessor" `Quick test_debounce_ms_accessor;
          test_case
            "default debounce_ms is 250"
            `Quick
            test_default_debounce_ms_is_250;
        ] );
    ]
