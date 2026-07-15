(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(* Matrix driver input: the {!Matrix_io.event} data type, plus a narrow-seam
   producer/consumer parity check for the "Mouse:row:col" family of key
   strings.

   {b Honest scope}: the real producer of these strings lives in
   [matrix_main_loop.ml] (e.g. [Printf.sprintf "Mouse:%d:%d" row col]),
   which this test-debt slice does not exercise directly — matrix_main_loop
   / render_loop are explicitly out of scope, blocked on the G3 driver
   consolidation (see the test-debt plan's consensus table: they need an
   unconstructible [Eio_unix.Stdenv.base] plus a real [Domain] over
   non-domain-safe globals). Instead, [producer] below is a small,
   test-local mirror of that string-formatting convention (a "Matrix_*
   fake", per the test-debt scope rules) used purely to drive
   [Miaou_helpers.Mouse.parse_click] — the real consumer, exercised in
   test/test_mouse.ml — adversarially: for a range of coordinates and
   click kinds, the format the producer convention emits must be exactly
   what the consumer recovers. If either side's string convention drifts
   without the other being updated to match, *this* mirror needs updating
   too; it does not, by itself, prove the real [matrix_main_loop.ml] stays
   in sync — only that the documented "Mouse:row:col" contract is
   internally consistent. *)
open Alcotest
module Mouse = Miaou_helpers.Mouse
module Matrix_io = Miaou_driver_matrix.Matrix_io

let mouse_event_testable =
  let pp fmt (ev : Mouse.mouse_event) =
    Format.fprintf fmt "{row=%d; col=%d}" ev.row ev.col
  in
  let equal (a : Mouse.mouse_event) (b : Mouse.mouse_event) =
    a.row = b.row && a.col = b.col
  in
  Alcotest.testable pp equal

(* Test-local mirror of matrix_main_loop.ml's producer-side key-string
   format for clicks and drags (see this file's header comment). *)
type click_kind = Single | Double | Triple

let producer_click kind ~row ~col =
  match kind with
  | Single -> Printf.sprintf "Mouse:%d:%d" row col
  | Double -> Printf.sprintf "DoubleClick:%d:%d" row col
  | Triple -> Printf.sprintf "TripleClick:%d:%d" row col

let producer_drag ~row ~col = Printf.sprintf "MouseDrag:%d:%d" row col

let test_producer_click_strings_round_trip_through_consumer () =
  let cases =
    [(Single, 0, 0); (Single, 5, 10); (Double, 3, 7); (Triple, 100, 200)]
  in
  List.iter
    (fun (kind, row, col) ->
      let key = producer_click kind ~row ~col in
      check
        (option mouse_event_testable)
        (Printf.sprintf "consumer recovers producer's (%d,%d)" row col)
        (Some {Mouse.row; col})
        (Mouse.parse_click key))
    cases

let test_producer_drag_strings_round_trip_through_consumer () =
  let key = producer_drag ~row:12 ~col:34 in
  check
    bool
    "consumer recognizes the drag key as a drag"
    true
    (Mouse.is_drag key) ;
  check
    (option mouse_event_testable)
    "consumer recovers the drag coordinates"
    (Some {Mouse.row = 12; col = 34})
    (Mouse.parse_click key)

let test_translate_key_composes_with_the_producer_convention () =
  (* Screen-absolute coordinates from the producer, translated to
     widget-relative ones by the consumer-side helper exercised in
     test_mouse.ml — a second adversarial point where the two sides must
     agree on the exact string shape. *)
  let key = producer_click Single ~row:8 ~col:15 in
  check
    string
    "translate_key composes with the producer's Mouse: format"
    "Mouse:3:5"
    (Mouse.translate_key ~row_offset:5 ~col_offset:10 key)

let test_matrix_io_event_variants_are_distinguishable () =
  (* Structural sanity: press vs release vs drag carry distinct
     constructors even though all three are (int * int * ...) shaped, so a
     future refactor collapsing them by accident would be caught here. *)
  let classify = function
    | Matrix_io.Key _ -> "Key"
    | Matrix_io.MousePress _ -> "MousePress"
    | Matrix_io.Mouse _ -> "Mouse"
    | Matrix_io.MouseDrag _ -> "MouseDrag"
    | Matrix_io.Resize -> "Resize"
    | Matrix_io.Refresh -> "Refresh"
    | Matrix_io.Idle -> "Idle"
    | Matrix_io.Quit -> "Quit"
  in
  check
    string
    "MousePress classified distinctly from Mouse"
    "MousePress"
    (classify (Matrix_io.MousePress (1, 2, 0))) ;
  check
    string
    "Mouse (release) classified distinctly from MousePress"
    "Mouse"
    (classify (Matrix_io.Mouse (1, 2, 0))) ;
  check
    string
    "MouseDrag classified distinctly"
    "MouseDrag"
    (classify (Matrix_io.MouseDrag (1, 2))) ;
  check
    string
    "Key carries its payload"
    "Key"
    (classify (Matrix_io.Key "Enter")) ;
  List.iter
    (fun (ev, name) -> check string (name ^ " classified") name (classify ev))
    [
      (Matrix_io.Resize, "Resize");
      (Matrix_io.Refresh, "Refresh");
      (Matrix_io.Idle, "Idle");
      (Matrix_io.Quit, "Quit");
    ]

let () =
  run
    "matrix_input"
    [
      ( "producer_consumer_parity",
        [
          test_case
            "producer click strings round-trip through the consumer"
            `Quick
            test_producer_click_strings_round_trip_through_consumer;
          test_case
            "producer drag strings round-trip through the consumer"
            `Quick
            test_producer_drag_strings_round_trip_through_consumer;
          test_case
            "translate_key composes with the producer convention"
            `Quick
            test_translate_key_composes_with_the_producer_convention;
        ] );
      ( "matrix_io",
        [
          test_case
            "event variants are distinguishable"
            `Quick
            test_matrix_io_event_variants_are_distinguishable;
        ] );
    ]
