(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* Standalone demo to compare ASCII and Braille chart rendering modes *)

module Sparkline = Miaou_widgets_display.Sparkline_widget
module Line_chart = Miaou_widgets_display.Line_chart_widget
module Bar_chart = Miaou_widgets_display.Bar_chart_widget

let print_section title =
  print_endline "" ;
  print_endline ("═══ " ^ title ^ " ═══") ;
  print_endline ""

let demo_sparkline () =
  print_section "Sparkline Comparison" ;

  (* Create sparkline with some sample data *)
  let sp = Sparkline.create ~width:40 ~max_points:80 () in
  for i = 0 to 79 do
    let value = 50.0 +. (30.0 *. sin (float_of_int i /. 8.0)) in
    Sparkline.push sp value
  done ;

  (* ASCII mode *)
  print_endline "ASCII Mode:" ;
  let ascii_output =
    Sparkline.render sp ~focus:false ~show_value:true ~mode:ASCII ()
  in
  print_endline ascii_output ;
  print_endline "" ;

  (* Braille mode *)
  print_endline "Braille Mode:" ;
  let braille_output =
    Sparkline.render sp ~focus:false ~show_value:true ~mode:Braille ()
  in
  print_endline braille_output

let demo_line_chart () =
  print_section "Line Chart Comparison" ;

  (* Create a sine wave *)
  let points =
    List.init 50 (fun i ->
        let x = float_of_int i in
        let y = 50.0 +. (30.0 *. sin (x /. 5.0)) in
        {Line_chart.x; y; color = None})
  in
  let series = {Line_chart.label = "Sine Wave"; points; color = None} in
  let chart =
    Line_chart.create
      ~width:60
      ~height:12
      ~series:[series]
      ~title:"Sine Wave Chart"
      ()
  in

  (* ASCII mode *)
  print_endline "ASCII Mode:" ;
  let ascii_output =
    Line_chart.render chart ~show_axes:false ~show_grid:false ~mode:ASCII ()
  in
  print_endline ascii_output ;
  print_endline "" ;

  (* Braille mode *)
  print_endline "Braille Mode:" ;
  let braille_output =
    Line_chart.render chart ~show_axes:false ~show_grid:false ~mode:Braille ()
  in
  print_endline braille_output

let demo_bar_chart () =
  print_section "Bar Chart Comparison" ;

  (* Create bar chart with sample data *)
  let data =
    [
      ("Mon", 45.0, None);
      ("Tue", 67.0, None);
      ("Wed", 82.0, None);
      ("Thu", 55.0, None);
      ("Fri", 90.0, None);
      ("Sat", 38.0, None);
      ("Sun", 42.0, None);
    ]
  in
  let chart =
    Bar_chart.create ~width:56 ~height:10 ~data ~title:"Weekly Sales" ()
  in

  (* ASCII mode *)
  print_endline "ASCII Mode:" ;
  let ascii_output = Bar_chart.render chart ~show_values:false ~mode:ASCII () in
  print_endline ascii_output ;
  print_endline "" ;

  (* Braille mode *)
  print_endline "Braille Mode:" ;
  let braille_output =
    Bar_chart.render chart ~show_values:false ~mode:Braille ()
  in
  print_endline braille_output

let () =
  print_endline "" ;
  print_endline
    "╔════════════════════════════════════════════════════════════════╗" ;
  print_endline
    "║    MIAOU Chart Rendering: ASCII vs Braille Comparison         ║" ;
  print_endline
    "╚════════════════════════════════════════════════════════════════╝" ;
  print_endline "" ;
  print_endline "This demo shows the difference between ASCII and Braille" ;
  print_endline "rendering modes for chart widgets. Braille mode uses Unicode" ;
  print_endline "Braille patterns (2×4 dots per cell) for higher resolution." ;
  print_endline "" ;

  demo_sparkline () ;
  demo_line_chart () ;
  demo_bar_chart () ;

  print_endline "" ;
  print_endline
    "═══════════════════════════════════════════════════════════════" ;
  print_endline "Demo complete! Compare the visual smoothness of the two modes." ;
  print_endline
    "═══════════════════════════════════════════════════════════════" ;
  print_endline ""
