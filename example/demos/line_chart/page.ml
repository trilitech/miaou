(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Line_chart = Miaou_widgets_display.Line_chart_widget

module Inner = struct
  let tutorial_title = "Line Chart"

  let tutorial_markdown = [%blob "README.md"]

  type state = {
    chart : Line_chart.t;
    point_count : int;
    mode : Line_chart.render_mode;
    next_page : string option;
  }

  type msg = unit

  let generate_sine_points count =
    List.init count (fun i ->
        let x = float_of_int i in
        let y = (sin (x /. 3.0) *. 30.0) +. 50.0 in
        let color = if y > 75.0 then Some "31" else None in
        {Line_chart.x; y; color})

  let generate_cosine_points count =
    List.init count (fun i ->
        let x = float_of_int i in
        let y = (cos (x /. 3.0) *. 30.0) +. 50.0 in
        {Line_chart.x; y; color = None})

  let init () =
    let sine_series =
      {
        Line_chart.label = "Sine";
        points = generate_sine_points 15;
        color = Some "32";
      }
    in
    let cosine_series =
      {
        Line_chart.label = "Cosine";
        points = generate_cosine_points 15;
        color = Some "34";
      }
    in
    {
      chart =
        Line_chart.create
          ~width:70
          ~height:18
          ~series:[sine_series; cosine_series]
          ~title:"Trigonometric Functions"
          ();
      point_count = 15;
      mode = Line_chart.ASCII;
      next_page = None;
    }

  let update s (_ : msg) = s

  let add_points s =
    let new_count = s.point_count + 5 in
    let chart =
      s.chart
      |> Line_chart.update_series
           ~label:"Sine"
           ~points:(generate_sine_points new_count)
      |> Line_chart.update_series
           ~label:"Cosine"
           ~points:(generate_cosine_points new_count)
    in
    {s with chart; point_count = new_count}

  let view s ~focus:_ ~size:_ =
    let module W = Miaou_widgets_display.Widgets in
    let header = W.titleize "Line Chart Demo" in
    let thresholds =
      [{Line_chart.value = 80.0; color = "31"}; {value = 60.0; color = "33"}]
    in
    let mode_label =
      match s.mode with Line_chart.ASCII -> "ASCII" | Braille -> "Braille"
    in
    let chart_output =
      Line_chart.render
        s.chart
        ~show_axes:true
        ~show_grid:true
        ~thresholds
        ~mode:s.mode
        ()
    in
    let hint =
      W.dim
        (Printf.sprintf
           "Points: %d • Space to add more • b toggle Braille (%s) • t \
            tutorial • Esc returns"
           s.point_count
           mode_label)
    in
    String.concat "\n" [header; ""; chart_output; ""; hint]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:_ =
    match Miaou.Core.Keys.of_string key_str with
    | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape")
      ->
        go_back s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "b" ->
        let mode =
          match s.mode with
          | Line_chart.ASCII -> Line_chart.Braille
          | Braille -> Line_chart.ASCII
        in
        {s with mode}
    | Some (Miaou.Core.Keys.Char " ") -> add_points s
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
