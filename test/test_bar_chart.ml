(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Bar_chart = Miaou_widgets_display.Bar_chart_widget

let test_empty_chart () =
  let chart = Bar_chart.create ~width:20 ~height:10 ~data:[] () in
  let output = Bar_chart.render chart ~show_values:false ~thresholds:[] () in
  check string "empty" "" output

let test_single_bar () =
  let chart =
    Bar_chart.create ~width:20 ~height:10 ~data:[("A", 50.0, None)] ()
  in
  let output = Bar_chart.render chart ~show_values:false ~thresholds:[] () in
  check bool "has output" true (String.length output > 0)

let test_multiple_bars () =
  let chart =
    Bar_chart.create
      ~width:40
      ~height:12
      ~data:[("Mon", 45.0, None); ("Tue", 67.0, None); ("Wed", 82.0, None)]
      ()
  in
  let output = Bar_chart.render chart ~show_values:false ~thresholds:[] () in
  (* Should render a substantial chart *)
  check bool "has output" true (String.length output > 100)

let test_with_title () =
  let chart =
    Bar_chart.create
      ~width:30
      ~height:10
      ~data:[("A", 10.0, None); ("B", 20.0, None)]
      ~title:"Test Chart"
      ()
  in
  let output = Bar_chart.render chart ~show_values:false ~thresholds:[] () in
  check bool "has title" true (String.contains output 'T')

let test_with_values () =
  let chart =
    Bar_chart.create
      ~width:30
      ~height:10
      ~data:[("A", 42.5, None); ("B", 73.2, None)]
      ()
  in
  let output = Bar_chart.render chart ~show_values:true ~thresholds:[] () in
  (* Should have rendered output *)
  check bool "has output" true (String.length output > 50)

let test_update_data () =
  let chart =
    Bar_chart.create ~width:20 ~height:10 ~data:[("A", 10.0, None)] ()
  in
  let chart' =
    Bar_chart.update_data chart ~data:[("X", 50.0, None); ("Y", 75.0, None)]
  in
  let output = Bar_chart.render chart' ~show_values:false ~thresholds:[] () in
  check bool "updated" true (String.length output > 0)

let test_fixed_range () =
  let chart =
    Bar_chart.create
      ~width:25
      ~height:10
      ~data:[("A", 25.0, None); ("B", 50.0, None); ("C", 75.0, None)]
      ~min_value:0.0
      ~max_value:100.0
      ()
  in
  let output = Bar_chart.render chart ~show_values:false ~thresholds:[] () in
  check bool "rendered with fixed range" true (String.length output > 50)

let test_braille_mode () =
  let chart =
    Bar_chart.create
      ~width:30
      ~height:10
      ~data:[("Mon", 45.0, None); ("Tue", 67.0, None); ("Wed", 82.0, None)]
      ()
  in
  let output =
    Bar_chart.render
      chart
      ~show_values:false
      ~thresholds:[]
      ~mode:Bar_chart.Braille
      ()
  in
  check bool "braille has output" true (String.length output > 50)

let test_braille_vs_ascii () =
  let chart =
    Bar_chart.create
      ~width:30
      ~height:10
      ~data:[("A", 30.0, None); ("B", 60.0, None); ("C", 90.0, None)]
      ()
  in
  let ascii_output =
    Bar_chart.render
      chart
      ~show_values:false
      ~thresholds:[]
      ~mode:Bar_chart.ASCII
      ()
  in
  let braille_output =
    Bar_chart.render
      chart
      ~show_values:false
      ~thresholds:[]
      ~mode:Bar_chart.Braille
      ()
  in
  check bool "ascii not empty" true (String.length ascii_output > 0) ;
  check bool "braille not empty" true (String.length braille_output > 0)

let suite =
  [
    test_case "empty chart" `Quick test_empty_chart;
    test_case "single bar" `Quick test_single_bar;
    test_case "multiple bars" `Quick test_multiple_bars;
    test_case "with title" `Quick test_with_title;
    test_case "with values" `Quick test_with_values;
    test_case "update data" `Quick test_update_data;
    test_case "fixed range" `Quick test_fixed_range;
    test_case "braille mode" `Quick test_braille_mode;
    test_case "braille vs ascii" `Quick test_braille_vs_ascii;
  ]

let () = run "bar_chart" [("bar_chart", suite)]
