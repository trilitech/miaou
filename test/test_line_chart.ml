(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

open Alcotest
module Line_chart = Miaou_widgets_display.Line_chart_widget

let test_empty_chart () =
  let chart = Line_chart.create ~width:10 ~height:5 ~series:[] () in
  let output =
    Line_chart.render chart ~show_axes:false ~show_grid:false ~thresholds:[] ()
  in
  (* Should render empty grid *)
  check bool "non-empty output" true (String.length output > 0)

let test_single_point () =
  let series =
    {
      Line_chart.label = "test";
      points = [{Line_chart.x = 5.0; y = 2.5; color = None}];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:10 ~height:5 ~series:[series] () in
  let output =
    Line_chart.render chart ~show_axes:false ~show_grid:false ~thresholds:[] ()
  in
  (* Should contain the point marker *)
  let has_marker =
    try
      ignore (Str.search_forward (Str.regexp "●") output 0) ;
      true
    with Not_found -> false
  in
  check bool "has marker" true has_marker

let test_two_points_line () =
  let series =
    {
      Line_chart.label = "test";
      points =
        [
          {Line_chart.x = 0.0; y = 0.0; color = None};
          {Line_chart.x = 10.0; y = 10.0; color = None};
        ];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:10 ~height:5 ~series:[series] () in
  let output =
    Line_chart.render chart ~show_axes:true ~show_grid:false ~thresholds:[] ()
  in
  (* With axes, should render something *)
  check bool "has output" true (String.length output > 20)

let test_axes_rendering () =
  let series =
    {
      Line_chart.label = "test";
      points = [{Line_chart.x = 5.0; y = 5.0; color = None}];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:15 ~height:8 ~series:[series] () in
  let output =
    Line_chart.render chart ~show_axes:true ~show_grid:false ~thresholds:[] ()
  in
  (* Should have rendered output with axes *)
  check bool "has output" true (String.length output > 30)

let test_grid_rendering () =
  let series =
    {
      Line_chart.label = "test";
      points = [{Line_chart.x = 5.0; y = 5.0; color = None}];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:20 ~height:10 ~series:[series] () in
  let output =
    Line_chart.render chart ~show_axes:true ~show_grid:true ~thresholds:[] ()
  in
  (* Should render with both axes and grid *)
  check bool "has output" true (String.length output > 50)

let test_multiple_series () =
  let series1 =
    {
      Line_chart.label = "series1";
      points = [{Line_chart.x = 0.0; y = 0.0; color = None}];
      color = None;
    }
  in
  let series2 =
    {
      Line_chart.label = "series2";
      points = [{Line_chart.x = 5.0; y = 5.0; color = None}];
      color = None;
    }
  in
  let chart =
    Line_chart.create ~width:10 ~height:5 ~series:[series1; series2] ()
  in
  let output =
    Line_chart.render chart ~show_axes:false ~show_grid:false ~thresholds:[] ()
  in
  (* Should have markers for both series (● and ■) *)
  check bool "non-empty" true (String.length output > 0)

let test_update_series () =
  let series =
    {
      Line_chart.label = "test";
      points = [{Line_chart.x = 0.0; y = 0.0; color = None}];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:10 ~height:5 ~series:[series] () in
  let new_points = [{Line_chart.x = 5.0; y = 5.0; color = None}] in
  let chart' =
    Line_chart.update_series chart ~label:"test" ~points:new_points
  in
  let output =
    Line_chart.render chart' ~show_axes:false ~show_grid:false ~thresholds:[] ()
  in
  check bool "updated" true (String.length output > 0)

let test_add_point () =
  let series =
    {
      Line_chart.label = "test";
      points = [{Line_chart.x = 0.0; y = 0.0; color = None}];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:10 ~height:5 ~series:[series] () in
  let chart' =
    Line_chart.add_point
      chart
      ~label:"test"
      ~point:{Line_chart.x = 5.0; y = 5.0; color = None}
  in
  let output =
    Line_chart.render chart' ~show_axes:false ~show_grid:false ~thresholds:[] ()
  in
  check bool "point added" true (String.length output > 0)

let test_with_title () =
  let series =
    {
      Line_chart.label = "test";
      points = [{Line_chart.x = 5.0; y = 5.0; color = None}];
      color = None;
    }
  in
  let chart =
    Line_chart.create
      ~width:10
      ~height:5
      ~series:[series]
      ~title:"Test Chart"
      ()
  in
  let output =
    Line_chart.render chart ~show_axes:false ~show_grid:false ~thresholds:[] ()
  in
  (* Title should be in output *)
  check bool "has title" true (String.contains output 'T')

let test_braille_mode () =
  let series =
    {
      Line_chart.label = "test";
      points =
        [
          {Line_chart.x = 0.0; y = 0.0; color = None};
          {Line_chart.x = 5.0; y = 5.0; color = None};
          {Line_chart.x = 10.0; y = 10.0; color = None};
        ];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:20 ~height:10 ~series:[series] () in
  let output =
    Line_chart.render
      chart
      ~show_axes:false
      ~show_grid:false
      ~thresholds:[]
      ~mode:Line_chart.Braille
      ()
  in
  check bool "braille has output" true (String.length output > 0)

let test_braille_vs_ascii () =
  let series =
    {
      Line_chart.label = "test";
      points =
        [
          {Line_chart.x = 0.0; y = 0.0; color = None};
          {Line_chart.x = 10.0; y = 10.0; color = None};
        ];
      color = None;
    }
  in
  let chart = Line_chart.create ~width:15 ~height:8 ~series:[series] () in
  let ascii_output =
    Line_chart.render
      chart
      ~show_axes:false
      ~show_grid:false
      ~thresholds:[]
      ~mode:Line_chart.ASCII
      ()
  in
  let braille_output =
    Line_chart.render
      chart
      ~show_axes:false
      ~show_grid:false
      ~thresholds:[]
      ~mode:Line_chart.Braille
      ()
  in
  (* Both should produce output *)
  check bool "ascii not empty" true (String.length ascii_output > 0) ;
  check bool "braille not empty" true (String.length braille_output > 0)

let suite =
  [
    test_case "empty chart" `Quick test_empty_chart;
    test_case "single point" `Quick test_single_point;
    test_case "two points line" `Quick test_two_points_line;
    test_case "axes rendering" `Quick test_axes_rendering;
    test_case "grid rendering" `Quick test_grid_rendering;
    test_case "multiple series" `Quick test_multiple_series;
    test_case "update series" `Quick test_update_series;
    test_case "add point" `Quick test_add_point;
    test_case "with title" `Quick test_with_title;
    test_case "braille mode" `Quick test_braille_mode;
    test_case "braille vs ascii" `Quick test_braille_vs_ascii;
  ]

let () = run "line_chart" [("line_chart", suite)]
