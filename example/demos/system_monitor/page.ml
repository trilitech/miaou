(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

module Inner = struct
  let tutorial_title = "System Monitor"

  let tutorial_markdown = [%blob "README.md"]

  module Sparkline = Miaou_widgets_display.Sparkline_widget
  module Line_chart = Miaou_widgets_display.Line_chart_widget
  module Desc_list = Miaou_widgets_display.Description_list
  module SDL_render = Demo_shared.System_monitor_sdl

  type state = {
    cpu_spark : Sparkline.t;
    mem_spark : Sparkline.t;
    net_spark : Sparkline.t;
    cpu_history : Line_chart.point list;
    tick_count : int;
    mode : Line_chart.render_mode;
    next_page : string option;
  }

  type msg = unit

  let init () =
    {
      cpu_spark =
        Sparkline.create
          ~width:35
          ~max_points:35
          ~min_value:0.0
          ~max_value:100.0
          ();
      mem_spark =
        Sparkline.create
          ~width:35
          ~max_points:35
          ~min_value:0.0
          ~max_value:100.0
          ();
      net_spark = Sparkline.create ~width:35 ~max_points:35 ();
      cpu_history = [];
      tick_count = 0;
      mode = Line_chart.ASCII;
      next_page = None;
    }

  let update s (_ : msg) = s

  let format_uptime seconds =
    let hours = int_of_float (seconds /. 3600.0) in
    let minutes = int_of_float (mod_float seconds 3600.0 /. 60.0) in
    Printf.sprintf "%dh %dm" hours minutes

  let update_metrics s =
    let cpu, mem, net =
      if Demo_shared.System_metrics.is_supported () then
        ( Demo_shared.System_metrics.get_cpu_usage (),
          Demo_shared.System_metrics.get_memory_usage (),
          Demo_shared.System_metrics.get_network_usage () )
      else (30. +. Random.float 40., 60. +. Random.float 30., Random.float 100.)
    in
    Sparkline.push s.cpu_spark cpu ;
    Sparkline.push s.mem_spark mem ;
    Sparkline.push s.net_spark net ;
    let new_point =
      {Line_chart.x = float_of_int s.tick_count; y = cpu; color = None}
    in
    let cpu_history =
      let hist = s.cpu_history @ [new_point] in
      if List.length hist > 50 then List.tl hist else hist
    in
    {s with cpu_history; tick_count = s.tick_count + 1}

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let width = size.LTerm_geom.cols in
    let uptime = Demo_shared.System_metrics.get_uptime () in
    let load1, load5, load15 = Demo_shared.System_metrics.get_load_average () in
    let sys_info =
      Desc_list.create
        ~title:"System Information"
        ~key_width:15
        ~items:
          [
            ("Hostname", try Unix.gethostname () with _ -> "unknown");
            ("Uptime", format_uptime uptime);
            ( "Load (1/5/15)",
              Printf.sprintf "%.2f / %.2f / %.2f" load1 load5 load15 );
            ("Updates", Printf.sprintf "%d ticks" s.tick_count);
          ]
        ()
    in
    let cpu_thresholds =
      [{Sparkline.value = 90.0; color = "31"}; {value = 75.0; color = "33"}]
    in
    let mode_label =
      match s.mode with Line_chart.ASCII -> "ASCII" | Braille -> "Braille"
    in
    let separator_width = 3 in
    let left_width = min 50 (width / 2) in
    let right_width = width - left_width - separator_width in
    let sparkline_width = max 20 (right_width - 25) in
    let s_cpu_adjusted =
      Sparkline.create
        ~width:sparkline_width
        ~max_points:sparkline_width
        ~min_value:0.0
        ~max_value:100.0
        ()
    in
    let s_mem_adjusted =
      Sparkline.create
        ~width:sparkline_width
        ~max_points:sparkline_width
        ~min_value:0.0
        ~max_value:100.0
        ()
    in
    let s_net_adjusted =
      Sparkline.create ~width:sparkline_width ~max_points:sparkline_width ()
    in
    Sparkline.get_data s.cpu_spark |> List.iter (Sparkline.push s_cpu_adjusted) ;
    Sparkline.get_data s.mem_spark |> List.iter (Sparkline.push s_mem_adjusted) ;
    Sparkline.get_data s.net_spark |> List.iter (Sparkline.push s_net_adjusted) ;
    let _, _, cpu_val = Sparkline.get_bounds s_cpu_adjusted in
    let _, _, mem_val = Sparkline.get_bounds s_mem_adjusted in
    let _, _, net_val = Sparkline.get_bounds s_net_adjusted in
    let spark_mode =
      match s.mode with
      | Line_chart.ASCII -> Sparkline.ASCII
      | Braille -> Braille
    in
    let cpu_line_adj =
      Printf.sprintf "CPU: %5.1f " cpu_val
      ^ Sparkline.render
          s_cpu_adjusted
          ~focus:false
          ~show_value:false
          ~thresholds:cpu_thresholds
          ~color:"32"
          ~mode:spark_mode
          ()
    in
    let mem_line_adj =
      Printf.sprintf "MEM: %5.1f " mem_val
      ^ Sparkline.render
          s_mem_adjusted
          ~focus:false
          ~show_value:false
          ~thresholds:[]
          ~color:"34"
          ~mode:spark_mode
          ()
    in
    let net_line_adj =
      Printf.sprintf "NET: %5.1f KB/s " net_val
      ^ Sparkline.render
          s_net_adjusted
          ~focus:false
          ~show_value:false
          ~thresholds:[]
          ~color:"35"
          ~mode:spark_mode
          ()
    in
    let sys_info_lines =
      String.split_on_char
        '\n'
        (Desc_list.render ~cols:left_width ~wrap:false sys_info ~focus:false)
    in
    let metrics_title_line =
      "  " ^ W.fg 45 "*" ^ " " ^ W.fg 213 (W.bold "Real-Time Metrics")
    in
    let metrics_lines =
      [metrics_title_line; ""; cpu_line_adj; mem_line_adj; net_line_adj]
    in
    let combined_info =
      let max_lines =
        max (List.length sys_info_lines) (List.length metrics_lines)
      in
      let pad_list lst len =
        lst @ List.init (len - List.length lst) (fun _ -> "")
      in
      let sys_padded = pad_list sys_info_lines max_lines in
      let metrics_padded = pad_list metrics_lines max_lines in
      List.mapi
        (fun i (left, right) ->
          let stripped =
            Str.global_replace (Str.regexp "\027\\[[0-9;]*m") "" left
          in
          let visible_len = String.length stripped in
          let padding =
            max
              0
              (if i = 0 then left_width - visible_len + 2
               else left_width - visible_len)
          in
          let left_padded = left ^ String.make padding ' ' in
          left_padded ^ " " ^ W.dim "|" ^ " " ^ right)
        (List.combine sys_padded metrics_padded)
      |> String.concat "\n"
    in
    let cpu_chart =
      if List.length s.cpu_history >= 2 then
        let series =
          {
            Line_chart.label = "CPU %";
            points = s.cpu_history;
            color = Some "32";
          }
        in
        let chart =
          Line_chart.create
            ~width:(min 80 width)
            ~height:8
            ~series:[series]
            ~title:"CPU Usage History (last 50 samples)"
            ()
        in
        let thresholds =
          [
            {Line_chart.value = 90.0; color = "31"}; {value = 75.0; color = "33"};
          ]
        in
        "\n"
        ^ Line_chart.render
            chart
            ~show_axes:false
            ~show_grid:false
            ~thresholds
            ~mode:s.mode
            ()
      else ""
    in
    let header = W.titleize "System Monitor" in
    let sep = String.make width '-' in
    let hint =
      W.dim
        (Printf.sprintf
           "Auto-updating every ~150ms • b toggle Braille (%s) • t tutorial • \
            Esc to return"
           mode_label)
    in
    String.concat
      "\n"
      [header; sep; combined_info; ""; cpu_chart; ""; sep; hint]

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
    | _ -> s

  let move s _ = s

  let refresh s = update_metrics s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = update_metrics s

  let handle_modal_key s _ ~size:_ = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.Make (Inner)
