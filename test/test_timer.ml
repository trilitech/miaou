(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Cap = Miaou_interfaces.Capability
module Clock = Miaou_interfaces.Clock
module Timer = Miaou_interfaces.Timer

(** Helper: set up a fresh Clock + Timer capability pair and return both
    states so the test can call [Clock.tick] / [Timer.tick] manually. *)
let setup () =
  Cap.clear () ;
  let clock_state = Clock.create_state () in
  Clock.register clock_state ;
  let timer_state = Timer.create_state () in
  Timer.register timer_state ;
  (clock_state, timer_state)

(* ----------------------------------------------------------------------- *)
(* Tests                                                                    *)
(* ----------------------------------------------------------------------- *)

let test_interval_fires () =
  let _cs, ts = setup () in
  let timer = Timer.require () in
  (* Use 0.0 interval so deadline = now, fires on next tick *)
  timer.set_interval ~id:"poll" 0.0 ;
  Timer.tick ts ;
  let fired = timer.drain_fired () in
  check (list string) "poll fires" ["poll"] fired

let test_timeout_fires_once () =
  let cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_timeout ~id:"once" 0.0 ;
  Timer.tick ts ;
  let fired = timer.drain_fired () in
  check (list string) "timeout fires" ["once"] fired ;
  (* Timeout auto-removes — should not appear in active_ids *)
  check (list string) "timeout removed" [] (timer.active_ids ()) ;
  (* Second tick: nothing fires *)
  Clock.tick cs ;
  Timer.tick ts ;
  let fired2 = timer.drain_fired () in
  check (list string) "no second fire" [] fired2

let test_clear_before_fire () =
  let _cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_interval ~id:"cancel_me" 999.0 ;
  check
    bool
    "active before clear"
    true
    (List.mem "cancel_me" (timer.active_ids ())) ;
  timer.clear "cancel_me" ;
  Timer.tick ts ;
  let fired = timer.drain_fired () in
  check (list string) "nothing fires" [] fired ;
  check (list string) "no active timers" [] (timer.active_ids ())

let test_drain_resets () =
  let _cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_timeout ~id:"drain_test" 0.0 ;
  Timer.tick ts ;
  let first = timer.drain_fired () in
  check (list string) "first drain" ["drain_test"] first ;
  (* Second drain returns empty *)
  let second = timer.drain_fired () in
  check (list string) "second drain empty" [] second

let test_clear_all () =
  let _cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_interval ~id:"a" 1.0 ;
  timer.set_timeout ~id:"b" 2.0 ;
  check int "two active" 2 (List.length (timer.active_ids ())) ;
  Timer.clear_all ts ;
  check (list string) "all cleared" [] (timer.active_ids ()) ;
  (* Also clears any pending fired list *)
  check (list string) "fired cleared" [] (timer.drain_fired ())

let test_interval_reschedules () =
  let cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_interval ~id:"repeat" 0.0 ;
  Timer.tick ts ;
  let fired1 = timer.drain_fired () in
  check (list string) "first fire" ["repeat"] fired1 ;
  (* Interval stays active *)
  check bool "still active" true (List.mem "repeat" (timer.active_ids ())) ;
  (* Second tick — fires again *)
  Clock.tick cs ;
  Timer.tick ts ;
  let fired2 = timer.drain_fired () in
  check (list string) "second fire" ["repeat"] fired2

let test_multiple_timers () =
  let _cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_interval ~id:"a" 0.0 ;
  timer.set_timeout ~id:"b" 0.0 ;
  Timer.tick ts ;
  let fired = timer.drain_fired () in
  let fired_sorted = List.sort String.compare fired in
  check (list string) "both fire" ["a"; "b"] fired_sorted

let test_replace_same_id () =
  let _cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_interval ~id:"x" 999.0 ;
  (* Replace with a 0-second timeout *)
  timer.set_timeout ~id:"x" 0.0 ;
  (* Only one timer with that id *)
  check int "one active" 1 (List.length (timer.active_ids ())) ;
  Timer.tick ts ;
  let fired = timer.drain_fired () in
  check (list string) "replacement fires" ["x"] fired ;
  (* It was a timeout, so auto-removed *)
  check (list string) "auto-removed" [] (timer.active_ids ())

let test_clear_nonexistent () =
  let _cs, _ts = setup () in
  let timer = Timer.require () in
  (* Should not raise *)
  timer.clear "does_not_exist" ;
  check (list string) "still empty" [] (timer.active_ids ())

let test_long_interval_does_not_fire () =
  let _cs, ts = setup () in
  let timer = Timer.require () in
  timer.set_interval ~id:"slow" 9999.0 ;
  Timer.tick ts ;
  let fired = timer.drain_fired () in
  check (list string) "no fire" [] fired ;
  check bool "still active" true (List.mem "slow" (timer.active_ids ()))

let () =
  run
    "timer"
    [
      ( "timer",
        [
          test_case "interval fires on tick" `Quick test_interval_fires;
          test_case
            "timeout fires once and auto-removes"
            `Quick
            test_timeout_fires_once;
          test_case "clear prevents firing" `Quick test_clear_before_fire;
          test_case "drain_fired resets list" `Quick test_drain_resets;
          test_case "clear_all removes everything" `Quick test_clear_all;
          test_case
            "interval reschedules after fire"
            `Quick
            test_interval_reschedules;
          test_case "multiple timers fire" `Quick test_multiple_timers;
          test_case "replace timer with same id" `Quick test_replace_same_id;
          test_case "clear nonexistent is no-op" `Quick test_clear_nonexistent;
          test_case
            "long interval does not fire"
            `Quick
            test_long_interval_does_not_fire;
        ] );
    ]
