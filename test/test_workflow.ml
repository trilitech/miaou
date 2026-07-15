open Alcotest
module Workflow = Miaou_core.Workflow

(* A fully scripted fake driver: no real page, no real terminal, no real
   time. [sleep] is a no-op (recorded, not actually slept) so
   `Await_modal`/`Await_no_modal`/`Loop_until` polling loops run instantly
   and deterministically in tests. *)
type fake_driver = {
  mutable calls : string list; (* reverse-order call log *)
  mutable poll_count : int;
  screen_text : string;
  mutable sleep_calls : int;
}

let make_fake ?(screen_text = "") () =
  {calls = []; poll_count = 0; screen_text; sleep_calls = 0}

let record f s = f.calls <- s :: f.calls

let log_of f = List.rev f.calls

(* [has_modal] is supplied per-test so each scenario can script exactly
   when a modal opens/closes without needing a shared "generic" policy. *)
let driver_of ?(has_modal = fun _poll_count -> false) f : Workflow.driver =
  {
    feed_key = (fun k -> record f (Printf.sprintf "feed_key:%s" k));
    feed_keys =
      (fun ks ->
        record f (Printf.sprintf "feed_keys:%s" (String.concat "," ks)));
    screen =
      (fun () ->
        record f "screen" ;
        f.screen_text);
    has_modal =
      (fun () ->
        f.poll_count <- f.poll_count + 1 ;
        has_modal f.poll_count);
    sleep = (fun _ -> f.sleep_calls <- f.sleep_calls + 1);
    log = (fun msg -> record f (Printf.sprintf "log:%s" msg));
  }

let test_feed_then_bind_ordering () =
  let f = make_fake () in
  let w =
    let open Workflow in
    let* () = feed ["a"; "b"] in
    let* () = feed ["c"] in
    return ()
  in
  Workflow.run_with (driver_of f) w ;
  check
    (list string)
    "feeds happen in program order"
    ["feed_keys:a,b"; "feed_keys:c"]
    (log_of f)

let test_await_modal_success_after_polling () =
  (* has_modal only becomes true on the 3rd poll; await_modal must retry
     rather than giving up immediately. *)
  let f = make_fake () in
  let has_modal poll_count = poll_count >= 3 in
  let w = Workflow.await_modal () (Workflow.return ()) in
  Workflow.run_modal_with (driver_of ~has_modal f) w ;
  check bool "polled has_modal at least 3 times" true (f.poll_count >= 3) ;
  check bool "slept between unsuccessful polls" true (f.sleep_calls >= 2)

let test_await_modal_timeout_raises_structured_error () =
  (* has_modal never returns true. *)
  let f = make_fake () in
  let w = Workflow.await_modal ~max_iters:3 () (Workflow.return ()) in
  match
    try Ok (Workflow.run_modal_with (driver_of f) w)
    with Workflow.Workflow_error e -> Error e
  with
  | Error e ->
      check string "error step is await_modal" "await_modal" e.step ;
      check string "error message mentions timeout" "timeout" e.message ;
      check (option int) "attempt count recorded" (Some 3) e.attempt
  | Ok () -> fail "expected a Workflow_error on await_modal timeout"

let test_run_raises_where_run_with_result_wraps_error () =
  let f = make_fake () in
  let w = Workflow.await_modal ~max_iters:1 () (Workflow.return ()) in
  (* Interpreting via [run_modal_with] raises the exception directly. *)
  check
    bool
    "run_modal_with raises Workflow_error"
    true
    (try
       Workflow.run_modal_with (driver_of f) w ;
       false
     with Workflow.Workflow_error _ -> true) ;
  (* Wrapping the same interpretation in a [try] (the pattern
     [run_modal_result] follows) never raises; it reports the same failure
     as [Error] instead. *)
  let f2 = make_fake () in
  let wrapped =
    try Ok (Workflow.run_modal_with (driver_of f2) w)
    with Workflow.Workflow_error e -> Error e
  in
  check
    bool
    "the wrapped form reports Error instead of raising"
    true
    (match wrapped with Error _ -> true | Ok () -> false)

let test_expect_screen_predicate_pass_and_fail () =
  let f_pass = make_fake ~screen_text:"Welcome to MIAOU" () in
  let w_pass = Workflow.expect (fun s -> s = "Welcome to MIAOU") in
  Workflow.run_with (driver_of f_pass) w_pass ;
  let f_fail = make_fake ~screen_text:"unexpected" () in
  let w_fail = Workflow.expect (fun s -> s = "Welcome to MIAOU") in
  check
    bool
    "expect raises Workflow_error on predicate failure"
    true
    (try
       Workflow.run_with (driver_of f_fail) w_fail ;
       false
     with Workflow.Workflow_error e -> e.step = "expect")

let test_loop_until_budget_exhausted () =
  let f = make_fake ~screen_text:"never matches" () in
  let w = Workflow.loop_until ~max_iters:5 (fun s -> s = "matches") in
  check
    bool
    "loop_until raises Workflow_error once budget is exhausted"
    true
    (try
       Workflow.run_with (driver_of f) w ;
       false
     with Workflow.Workflow_error e ->
       e.step = "loop_until" && e.attempt = Some 5)

let test_run_result_ok_on_trivial_workflow () =
  let f = make_fake () in
  let w = Workflow.return "value" in
  match
    Workflow.with_driver (driver_of f) (fun () -> Workflow.run_result w)
  with
  | Ok v -> check string "run_result Ok on a trivial workflow" "value" v
  | Error e ->
      fail (Printf.sprintf "unexpected Error: %s" (Workflow.pp_error e))

let test_run_result_surfaces_failing_step () =
  let f = make_fake ~screen_text:"whatever" () in
  let w = Workflow.expect (fun _ -> false) in
  match
    Workflow.with_driver (driver_of f) (fun () -> Workflow.run_result w)
  with
  | Error e ->
      check string "run_result surfaces the failing step name" "expect" e.step
  | Ok () -> fail "expected Error from run_result"

let test_simple_modal_flow_key_sequence () =
  (* simple_modal_flow: feed open_keys, await a modal, feed confirm_keys,
     await its dismissal. The fake modal opens on the first has_modal poll
     (satisfying await_modal) and is considered closed on every subsequent
     poll (satisfying the following await_no_modal). *)
  let opened = ref false in
  let has_modal _poll_count =
    if !opened then false
    else (
      opened := true ;
      true)
  in
  let f = make_fake () in
  let w = Workflow.simple_modal_flow ~open_keys:["m"] ~confirm_keys:["Enter"] in
  Workflow.run_with (driver_of ~has_modal f) w ;
  check
    (list string)
    "open then confirm keys fed in order"
    ["feed_keys:m"; "feed_keys:Enter"]
    (log_of f)

let () =
  run
    "workflow"
    [
      ( "workflow",
        [
          test_case "feed/bind ordering" `Quick test_feed_then_bind_ordering;
          test_case
            "await_modal succeeds after polling"
            `Quick
            test_await_modal_success_after_polling;
          test_case
            "await_modal timeout raises structured error"
            `Quick
            test_await_modal_timeout_raises_structured_error;
          test_case
            "raising vs Error-wrapped interpretation"
            `Quick
            test_run_raises_where_run_with_result_wraps_error;
          test_case
            "expect: screen predicate pass and fail"
            `Quick
            test_expect_screen_predicate_pass_and_fail;
          test_case
            "loop_until: budget exhausted"
            `Quick
            test_loop_until_budget_exhausted;
          test_case
            "run_result: Ok on a trivial workflow"
            `Quick
            test_run_result_ok_on_trivial_workflow;
          test_case
            "run_result: surfaces the failing step"
            `Quick
            test_run_result_surfaces_failing_step;
          test_case
            "simple_modal_flow key sequence"
            `Quick
            test_simple_modal_flow_key_sequence;
        ] );
    ]
