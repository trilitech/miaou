(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module A = Miaou_helpers.Animation

(* Tolerance for float comparisons *)
let eps = 1e-9

let float_eq =
  testable
    (fun fmt f -> Format.fprintf fmt "%.12f" f)
    (fun a b -> Float.abs (a -. b) < eps)

let approx_eq ?(tolerance = 0.01) () =
  testable
    (fun fmt f -> Format.fprintf fmt "%.6f" f)
    (fun a b -> Float.abs (a -. b) < tolerance)

(* ----------------------------------------------------------------------- *)
(* Easing curves                                                            *)
(* ----------------------------------------------------------------------- *)

let test_linear_easing () =
  let a = A.create ~duration:1.0 ~easing:Linear () in
  let a = A.tick a ~dt:0.5 in
  check (approx_eq ()) "linear midpoint" 0.5 (A.value a)

let test_ease_in () =
  let a = A.create ~duration:1.0 ~easing:Ease_in () in
  let a = A.tick a ~dt:0.5 in
  (* Cubic ease-in at 0.5: 0.5^3 = 0.125 — slower than linear *)
  check (approx_eq ()) "ease_in midpoint" 0.125 (A.value a) ;
  (* At endpoints: 0 and 1 *)
  let a0 = A.create ~duration:1.0 ~easing:Ease_in () in
  check float_eq "ease_in start" 0.0 (A.value a0) ;
  let a1 = A.tick a0 ~dt:1.0 in
  check float_eq "ease_in end" 1.0 (A.value a1)

let test_ease_out () =
  let a = A.create ~duration:1.0 ~easing:Ease_out () in
  let a = A.tick a ~dt:0.5 in
  (* Cubic ease-out at 0.5: 1 - (0.5)^3 = 0.875 — faster than linear *)
  check (approx_eq ()) "ease_out midpoint" 0.875 (A.value a) ;
  let a1 = A.tick (A.create ~duration:1.0 ~easing:Ease_out ()) ~dt:1.0 in
  check float_eq "ease_out end" 1.0 (A.value a1)

let test_ease_in_out () =
  let a = A.create ~duration:1.0 ~easing:Ease_in_out () in
  let a25 = A.tick a ~dt:0.25 in
  let a50 = A.tick a ~dt:0.5 in
  let a75 = A.tick a ~dt:0.75 in
  (* Symmetric: value at 0.25 + value at 0.75 = 1.0 *)
  let v25 = A.value a25 in
  let v75 = A.value a75 in
  check (approx_eq ()) "ease_in_out symmetry" 1.0 (v25 +. v75) ;
  (* Midpoint should be exactly 0.5 *)
  check (approx_eq ()) "ease_in_out midpoint" 0.5 (A.value a50)

(* ----------------------------------------------------------------------- *)
(* Once mode                                                                *)
(* ----------------------------------------------------------------------- *)

let test_once_lifecycle () =
  let a = A.create ~duration:0.5 () in
  check bool "not finished at start" false (A.finished a) ;
  check float_eq "value at start" 0.0 (A.value a) ;
  let a = A.tick a ~dt:0.25 in
  check bool "not finished at half" false (A.finished a) ;
  check (approx_eq ()) "value at half" 0.5 (A.value a) ;
  let a = A.tick a ~dt:0.25 in
  check bool "finished at end" true (A.finished a) ;
  check float_eq "value at end" 1.0 (A.value a)

let test_once_clamps () =
  let a = A.create ~duration:0.5 () in
  let a = A.tick a ~dt:10.0 in
  check float_eq "clamped at 1.0" 1.0 (A.value a) ;
  check bool "finished" true (A.finished a)

let test_negative_dt_ignored () =
  let a = A.create ~duration:1.0 () in
  let a = A.tick a ~dt:0.5 in
  let a = A.tick a ~dt:(-1.0) in
  check (approx_eq ()) "negative dt no effect" 0.5 (A.value a)

(* ----------------------------------------------------------------------- *)
(* Loop mode                                                                *)
(* ----------------------------------------------------------------------- *)

let test_loop_wraps () =
  let a = A.create ~duration:1.0 ~repeat:Loop () in
  check bool "never finished" false (A.finished a) ;
  let a = A.tick a ~dt:1.5 in
  check bool "still not finished" false (A.finished a) ;
  (* 1.5 / 1.0 = 1.5 → fractional part = 0.5 *)
  check (approx_eq ()) "wraps to 0.5" 0.5 (A.value a)

let test_loop_multiple_cycles () =
  let a = A.create ~duration:0.25 ~repeat:Loop () in
  let a = A.tick a ~dt:1.1 in
  (* 1.1 / 0.25 = 4.4, fractional = 0.4, raw = 0.4 *)
  check (approx_eq ()) "multi-cycle" 0.4 (A.raw a)

(* ----------------------------------------------------------------------- *)
(* Ping_pong mode                                                           *)
(* ----------------------------------------------------------------------- *)

let test_ping_pong () =
  let a = A.create ~duration:1.0 ~repeat:Ping_pong () in
  (* Forward phase: 0.5s → value 0.5 *)
  let a1 = A.tick a ~dt:0.5 in
  check (approx_eq ()) "forward 0.5" 0.5 (A.value a1) ;
  (* At peak: 1.0s → value 1.0 *)
  let a2 = A.tick a ~dt:1.0 in
  check (approx_eq ()) "peak 1.0" 1.0 (A.value a2) ;
  (* Backward phase: 1.5s → value 0.5 *)
  let a3 = A.tick a ~dt:1.5 in
  check (approx_eq ()) "backward 0.5" 0.5 (A.value a3) ;
  (* Full cycle: 2.0s → back to 0.0 *)
  let a4 = A.tick a ~dt:2.0 in
  check (approx_eq ()) "full cycle 0.0" 0.0 (A.value a4) ;
  check bool "never finished" false (A.finished a4)

(* ----------------------------------------------------------------------- *)
(* Reset                                                                    *)
(* ----------------------------------------------------------------------- *)

let test_reset () =
  let a = A.create ~duration:1.0 () in
  let a = A.tick a ~dt:0.7 in
  let a = A.reset a in
  check float_eq "reset to 0" 0.0 (A.value a) ;
  check float_eq "elapsed reset" 0.0 (A.elapsed a) ;
  check bool "not finished after reset" false (A.finished a)

(* ----------------------------------------------------------------------- *)
(* Interpolation                                                            *)
(* ----------------------------------------------------------------------- *)

let test_lerp () =
  let a = A.create ~duration:1.0 () in
  check (approx_eq ()) "lerp at 0" 10.0 (A.lerp 10.0 20.0 a) ;
  let a = A.tick a ~dt:0.5 in
  check (approx_eq ()) "lerp at 0.5" 15.0 (A.lerp 10.0 20.0 a) ;
  let a = A.tick a ~dt:0.5 in
  check (approx_eq ()) "lerp at 1" 20.0 (A.lerp 10.0 20.0 a)

let test_lerp_int () =
  let a = A.create ~duration:1.0 () in
  let a = A.tick a ~dt:0.5 in
  check int "lerp_int midpoint" 15 (A.lerp_int 10 20 a) ;
  (* Rounding: 0.3 of 0..10 = 3 *)
  let b = A.create ~duration:1.0 () in
  let b = A.tick b ~dt:0.3 in
  check int "lerp_int round" 3 (A.lerp_int 0 10 b)

let test_lerp_reverse () =
  (* lerp works with b < a (reverse interpolation) *)
  let a = A.create ~duration:1.0 () in
  let a = A.tick a ~dt:0.5 in
  check (approx_eq ()) "reverse lerp" 15.0 (A.lerp 20.0 10.0 a)

(* ----------------------------------------------------------------------- *)
(* Elapsed                                                                  *)
(* ----------------------------------------------------------------------- *)

let test_elapsed () =
  let a = A.create ~duration:1.0 () in
  let a = A.tick a ~dt:0.3 in
  let a = A.tick a ~dt:0.4 in
  check (approx_eq ()) "elapsed accumulates" 0.7 (A.elapsed a)

let test_elapsed_exceeds_duration () =
  (* For Once, elapsed can exceed duration *)
  let a = A.create ~duration:0.5 () in
  let a = A.tick a ~dt:2.0 in
  check (approx_eq ()) "elapsed exceeds" 2.0 (A.elapsed a) ;
  check float_eq "value clamped" 1.0 (A.value a)

(* ----------------------------------------------------------------------- *)
(* Raw vs eased value                                                       *)
(* ----------------------------------------------------------------------- *)

let test_raw_vs_eased () =
  let a = A.create ~duration:1.0 ~easing:Ease_in () in
  let a = A.tick a ~dt:0.5 in
  check (approx_eq ()) "raw at 0.5" 0.5 (A.raw a) ;
  (* Eased should differ from raw for non-linear easing *)
  let v = A.value a in
  check bool "eased differs from raw" true (Float.abs (v -. 0.5) > 0.01)

(* ----------------------------------------------------------------------- *)
(* Edge cases                                                               *)
(* ----------------------------------------------------------------------- *)

let test_zero_dt () =
  let a = A.create ~duration:1.0 () in
  let a = A.tick a ~dt:0.0 in
  check float_eq "zero dt stays at 0" 0.0 (A.value a)

let test_tiny_duration () =
  (* Duration is clamped to epsilon, not zero *)
  let a = A.create ~duration:0.0 () in
  let a = A.tick a ~dt:0.001 in
  check bool "tiny duration finishes" true (A.finished a)

(* ----------------------------------------------------------------------- *)
(* Bounce easing                                                            *)
(* ----------------------------------------------------------------------- *)

let test_bounce () =
  let a = A.create ~duration:1.0 ~easing:Bounce () in
  (* At start and end, values are 0 and 1 *)
  check float_eq "bounce start" 0.0 (A.value a) ;
  let a1 = A.tick a ~dt:1.0 in
  check (approx_eq ()) "bounce end" 1.0 (A.value a1) ;
  (* Midway, bounce should overshoot above 1.0 at some point *)
  let a_mid = A.tick a ~dt:0.5 in
  let v = A.value a_mid in
  check bool "bounce overshoots at midpoint" true (v > 0.5)

let test_custom_easing () =
  (* Custom easing: square root (fast start, slow end) *)
  let a = A.create ~duration:1.0 ~easing:(Custom Float.sqrt) () in
  let a = A.tick a ~dt:0.25 in
  check (approx_eq ()) "custom sqrt at 0.25" 0.5 (A.value a)

(* ----------------------------------------------------------------------- *)
(* Delay                                                                    *)
(* ----------------------------------------------------------------------- *)

let test_delay () =
  let a = A.delay 0.5 in
  check float_eq "delay starts at 0" 0.0 (A.value a) ;
  check bool "delay not finished at start" false (A.finished a) ;
  let a = A.tick a ~dt:0.25 in
  check (approx_eq ()) "delay midway" 0.5 (A.value a) ;
  let a = A.tick a ~dt:0.25 in
  check bool "delay finishes" true (A.finished a)

(* ----------------------------------------------------------------------- *)
(* Sequence                                                                 *)
(* ----------------------------------------------------------------------- *)

let test_sequence_basic () =
  (* Two 0.5s linear animations in sequence *)
  let s = A.sequence [A.create ~duration:0.5 (); A.create ~duration:0.5 ()] in
  check float_eq "seq start" 0.0 (A.value s) ;
  check bool "seq not finished" false (A.finished s) ;
  (* 0.25s into first step: value = 0.5 *)
  let s = A.tick s ~dt:0.25 in
  check (approx_eq ()) "step 1 midway" 0.5 (A.value s) ;
  (* 0.5s: first step done, second step just starting *)
  let s = A.tick s ~dt:0.25 in
  check bool "not finished after step 1" false (A.finished s) ;
  (* 0.75s: second step midway *)
  let s = A.tick s ~dt:0.25 in
  check (approx_eq ()) "step 2 midway" 0.5 (A.value s) ;
  (* 1.0s: done *)
  let s = A.tick s ~dt:0.25 in
  check bool "finished" true (A.finished s) ;
  check (approx_eq ()) "final value" 1.0 (A.value s)

let test_sequence_with_delay () =
  (* flash in → hold → fade out *)
  let s =
    A.sequence
      [
        A.create ~duration:0.1 ~easing:Ease_out ();
        A.delay 0.5;
        A.create ~duration:0.3 ~easing:Ease_in ();
      ]
  in
  (* During hold phase, value should be linear progress of the delay *)
  let s = A.tick s ~dt:0.1 in
  (* first step done *)
  check bool "past step 1" false (A.finished s) ;
  let s = A.tick s ~dt:0.25 in
  (* midway through delay *)
  check (approx_eq ()) "delay midway" 0.5 (A.value s) ;
  let s = A.tick s ~dt:0.25 in
  (* delay done, step 3 starting *)
  let s = A.tick s ~dt:0.3 in
  (* step 3 done *)
  check bool "sequence finished" true (A.finished s)

let test_sequence_empty () =
  let s = A.sequence [] in
  check bool "empty sequence finished" true (A.finished s) ;
  (* Empty sequence is an already-completed no-op — value is 1.0 *)
  check float_eq "empty sequence value" 1.0 (A.value s)

let test_sequence_reset () =
  let s = A.sequence [A.create ~duration:0.5 (); A.create ~duration:0.5 ()] in
  let s = A.tick s ~dt:1.0 in
  check bool "finished before reset" true (A.finished s) ;
  let s = A.reset s in
  check bool "not finished after reset" false (A.finished s) ;
  check float_eq "value reset" 0.0 (A.value s)

let test_sequence_excess_carries () =
  (* When step 1 gets excess time, it carries to step 2 *)
  let s = A.sequence [A.create ~duration:0.2 (); A.create ~duration:0.8 ()] in
  (* Tick 0.5s in one shot: 0.2s for step 1, 0.3s carries to step 2 *)
  let s = A.tick s ~dt:0.5 in
  (* Step 2 should be at 0.3/0.8 = 0.375 *)
  check (approx_eq ~tolerance:0.02 ()) "excess carried" 0.375 (A.value s)

let () =
  run
    "animation"
    [
      ( "easing",
        [
          test_case "linear" `Quick test_linear_easing;
          test_case "ease_in" `Quick test_ease_in;
          test_case "ease_out" `Quick test_ease_out;
          test_case "ease_in_out" `Quick test_ease_in_out;
          test_case "bounce" `Quick test_bounce;
          test_case "custom" `Quick test_custom_easing;
        ] );
      ( "once",
        [
          test_case "lifecycle" `Quick test_once_lifecycle;
          test_case "clamps past end" `Quick test_once_clamps;
          test_case "negative dt ignored" `Quick test_negative_dt_ignored;
        ] );
      ( "loop",
        [
          test_case "wraps around" `Quick test_loop_wraps;
          test_case "multiple cycles" `Quick test_loop_multiple_cycles;
        ] );
      ("ping_pong", [test_case "oscillates" `Quick test_ping_pong]);
      ("reset", [test_case "resets state" `Quick test_reset]);
      ( "lerp",
        [
          test_case "float interpolation" `Quick test_lerp;
          test_case "int interpolation" `Quick test_lerp_int;
          test_case "reverse direction" `Quick test_lerp_reverse;
        ] );
      ( "elapsed",
        [
          test_case "accumulates" `Quick test_elapsed;
          test_case "exceeds duration" `Quick test_elapsed_exceeds_duration;
        ] );
      ( "raw_vs_eased",
        [test_case "differ for non-linear" `Quick test_raw_vs_eased] );
      ( "edge_cases",
        [
          test_case "zero dt" `Quick test_zero_dt;
          test_case "tiny duration" `Quick test_tiny_duration;
        ] );
      ("delay", [test_case "delay lifecycle" `Quick test_delay]);
      ( "sequence",
        [
          test_case "basic two-step" `Quick test_sequence_basic;
          test_case "with delay" `Quick test_sequence_with_delay;
          test_case "empty" `Quick test_sequence_empty;
          test_case "reset" `Quick test_sequence_reset;
          test_case "excess time carries" `Quick test_sequence_excess_carries;
        ] );
    ]
