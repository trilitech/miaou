(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module VT = Miaou_widgets_input.Validated_textbox_widget

let int_validator s =
  match int_of_string_opt s with
  | Some n when n >= 0 -> VT.Valid n
  | _ -> VT.Invalid "Must be non-negative integer"

let test_immediate_validation_when_debounce_zero () =
  let box = VT.create ~debounce_ms:0 ~validator:int_validator () in
  let box = VT.handle_key box ~key:"1" in
  let box = VT.handle_key box ~key:"2" in
  let box = VT.handle_key box ~key:"3" in
  check bool "valid after typing" true (VT.is_valid box) ;
  check (option int) "validated value" (Some 123) (VT.get_validated_value box) ;
  check bool "no pending validation" false (VT.has_pending_validation box)

let test_debounce_defers_validation () =
  let box = VT.create ~debounce_ms:1000 ~validator:int_validator () in
  let box = VT.handle_key box ~key:"1" in
  (* Validation should be pending, not yet run *)
  check bool "has pending validation" true (VT.has_pending_validation box) ;
  (* The validation state should still be from initial (empty string = invalid) *)
  check bool "not yet valid" false (VT.is_valid box)

let test_flush_validation_bypasses_debounce () =
  let box = VT.create ~debounce_ms:10000 ~validator:int_validator () in
  let box = VT.handle_key box ~key:"4" in
  let box = VT.handle_key box ~key:"2" in
  check bool "pending before flush" true (VT.has_pending_validation box) ;
  let box = VT.flush_validation box in
  check bool "not pending after flush" false (VT.has_pending_validation box) ;
  check bool "valid after flush" true (VT.is_valid box) ;
  check (option int) "correct value" (Some 42) (VT.get_validated_value box)

let test_tick_runs_validation_after_debounce () =
  (* Deterministic fake clock instead of a real sleep: advance it explicitly
     past the debounce window rather than waiting on wall-clock time. *)
  let t_ms = ref 0 in
  let now () = float_of_int !t_ms /. 1000.0 in
  let box = VT.create ~debounce_ms:100 ~now ~validator:int_validator () in
  let box = VT.handle_key box ~key:"9" in
  check bool "pending after key" true (VT.has_pending_validation box) ;
  t_ms := !t_ms + 150 ;
  let box = VT.tick box in
  check bool "not pending after tick" false (VT.has_pending_validation box) ;
  check bool "valid after tick" true (VT.is_valid box)

let test_tick_is_noop_before_debounce_elapses () =
  let t_ms = ref 0 in
  let now () = float_of_int !t_ms /. 1000.0 in
  let box = VT.create ~debounce_ms:100 ~now ~validator:int_validator () in
  let box = VT.handle_key box ~key:"9" in
  t_ms := !t_ms + 50 ;
  let box = VT.tick box in
  check
    bool
    "still pending before debounce elapses"
    true
    (VT.has_pending_validation box) ;
  check bool "not yet valid before debounce elapses" false (VT.is_valid box)

let test_error_message () =
  let box = VT.create ~debounce_ms:0 ~validator:int_validator () in
  let box = VT.handle_key box ~key:"a" in
  let box = VT.handle_key box ~key:"b" in
  let box = VT.handle_key box ~key:"c" in
  check bool "invalid input" false (VT.is_valid box) ;
  check
    (option string)
    "error message"
    (Some "Must be non-negative integer")
    (VT.get_error_message box)

let test_render_shows_error () =
  let box = VT.create ~debounce_ms:0 ~validator:int_validator () in
  let box = VT.handle_key box ~key:"x" in
  let rendered = VT.render box ~focus:true in
  check bool "contains warning" true (String.contains rendered '\226')

let () =
  run
    "validated_textbox"
    [
      ( "debounce",
        [
          test_case
            "immediate validation when debounce=0"
            `Quick
            test_immediate_validation_when_debounce_zero;
          test_case
            "debounce defers validation"
            `Quick
            test_debounce_defers_validation;
          test_case
            "flush_validation bypasses debounce"
            `Quick
            test_flush_validation_bypasses_debounce;
          test_case
            "tick runs validation after debounce"
            `Quick
            test_tick_runs_validation_after_debounce;
          test_case
            "tick is a no-op before debounce elapses"
            `Quick
            test_tick_is_noop_before_debounce_elapses;
          test_case "error message" `Quick test_error_message;
          test_case "render shows error" `Quick test_render_shows_error;
        ] );
    ]
