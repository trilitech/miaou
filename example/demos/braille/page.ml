(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Sparkline = Miaou_widgets_display.Sparkline_widget
module Line_chart = Miaou_widgets_display.Line_chart_widget
module Bar_chart = Miaou_widgets_display.Bar_chart_widget

type render_mode = ASCII | Braille

module Inner = struct
  let tutorial_title = "Braille Charts"

  let tutorial_markdown = [%blob "README.md"]

  type state = {mode : render_mode; next_page : string option}

  type msg = unit

  let init () = {mode = ASCII; next_page = None}

  let update s (_ : msg) = s

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Braille Chart Comparison" in

    let spark_mode =
      match s.mode with
      | ASCII -> Sparkline.ASCII
      | Braille -> Sparkline.Braille
    in
    let line_mode =
      match s.mode with
      | ASCII -> Line_chart.ASCII
      | Braille -> Line_chart.Braille
    in
    let bar_mode =
      match s.mode with
      | ASCII -> Bar_chart.ASCII
      | Braille -> Bar_chart.Braille
    in

    let sp = Sparkline.create ~width:40 ~max_points:80 () in
    for i = 0 to 79 do
      let value = 50.0 +. (30.0 *. sin (float_of_int i /. 8.0)) in
      Sparkline.push sp value
    done ;
    let spark_output =
      Sparkline.render sp ~focus:false ~show_value:true ~mode:spark_mode ()
    in

    let points =
      List.init 50 (fun i ->
          let x = float_of_int i in
          let y = 50.0 +. (30.0 *. sin (x /. 5.0)) in
          {Line_chart.x; y; color = None})
    in
    let series = {Line_chart.label = "Sine Wave"; points; color = None} in
    let line_chart =
      Line_chart.create
        ~width:60
        ~height:8
        ~series:[series]
        ~title:"Sine Wave"
        ()
    in
    let line_output =
      Line_chart.render
        line_chart
        ~show_axes:false
        ~show_grid:false
        ~mode:line_mode
        ()
    in

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
    let bar_chart =
      Bar_chart.create ~width:56 ~height:8 ~data ~title:"Weekly Sales" ()
    in
    let bar_output =
      Bar_chart.render bar_chart ~show_values:false ~mode:bar_mode ()
    in

    let mode_label =
      match s.mode with ASCII -> "ASCII" | Braille -> "Braille"
    in
    let hint =
      W.dim
        (Printf.sprintf
           "Current: %s • b to toggle • t for tutorial • Esc to return"
           mode_label)
    in

    String.concat
      "\n\n"
      [
        header;
        W.bold "Sparkline:" ^ "\n" ^ spark_output;
        W.bold "Line Chart:" ^ "\n" ^ line_output;
        W.bold "Bar Chart:" ^ "\n" ^ bar_output;
        hint;
      ]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "b" ->
        let mode = match s.mode with ASCII -> Braille | Braille -> ASCII in
        {s with mode}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
