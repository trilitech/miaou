(******************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(******************************************************************************)

module Sparkline = Miaou_widgets_display.Sparkline_widget

(* docs:start:sparkline-dashboard *)
let latency_sparkline samples =
  let spark =
    Sparkline.create ~width:30 ~max_points:30 ~min_value:0.0 ~max_value:200.0 ()
  in
  List.iter (Sparkline.push spark) samples ;
  Sparkline.render_with_label
    spark
    ~label:"Latency"
    ~focus:false
    ~color:"38;5;81"
    ~thresholds:[{value = 120.0; color = "38;5;196"}]
    ~mode:Braille
    ()
(* docs:end:sparkline-dashboard *)

let sample () = latency_sparkline [18.; 25.; 44.; 80.; 123.; 91.; 65.; 31.]
