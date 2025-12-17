(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

let tutorial_markdown = [%blob "README.md"]

module Sparkline = Miaou_widgets_display.Sparkline_widget

type state = {
  cpu_spark : Sparkline.t;
  mem_spark : Sparkline.t;
  net_spark : Sparkline.t;
  tick_count : int;
  next_page : string option;
}

type msg = unit

let init () =
  {
    cpu_spark =
      Sparkline.create
        ~width:50
        ~max_points:50
        ~min_value:0.0
        ~max_value:100.0
        ();
    mem_spark =
      Sparkline.create
        ~width:50
        ~max_points:50
        ~min_value:0.0
        ~max_value:100.0
        ();
    net_spark = Sparkline.create ~width:50 ~max_points:50 ();
    tick_count = 0;
    next_page = None;
  }

let update s (_ : msg) = s

let simulate_tick s =
  let cpu, mem, net =
    if Demo_shared.System_metrics.is_supported () then
      ( Demo_shared.System_metrics.get_cpu_usage (),
        Demo_shared.System_metrics.get_memory_usage (),
        Demo_shared.System_metrics.get_network_usage () )
    else
      (30. +. Random.float 40., 60. +. Random.float 30., Random.float 100.)
  in
  Sparkline.push s.cpu_spark cpu ;
  Sparkline.push s.mem_spark mem ;
  Sparkline.push s.net_spark net ;
  {s with tick_count = s.tick_count + 1}

let view s ~focus:_ ~size:_ =
  let module W = Miaou_widgets_display.Widgets in
  let header = W.titleize "Sparkline Charts Demo" in
  let sep = String.make 60 '-' in
  let source =
    if Demo_shared.System_metrics.is_supported () then "Real system metrics"
    else "Simulated data (Linux /proc not available)"
  in
  let cpu_thresholds =
    [{Sparkline.value = 90.0; color = "31"}; {value = 75.0; color = "33"}]
  in
  let sparklines =
    [
      "";
      W.bold "Real-time Metrics:";
      W.dim source;
      "";
      Sparkline.render_with_label
        s.cpu_spark
        ~label:"CPU Usage"
        ~focus:true
        ~color:"32"
        ~thresholds:cpu_thresholds
        ();
      Sparkline.render_with_label
        s.mem_spark
        ~label:"Memory   "
        ~focus:false
        ~color:"34"
        ();
      Sparkline.render_with_label
        s.net_spark
        ~label:"Network  "
        ~focus:false
        ();
      "";
      sep;
      "";
      W.dim
        (Printf.sprintf
           "Data points: %d • Auto-updating (~150ms) • t tutorial • Esc returns"
           s.tick_count);
    ]
  in
  String.concat "\n" (header :: sep :: sparklines)

let go_back s = {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

let show_tutorial () =
  Demo_shared.Tutorial_modal.show ~title:"Sparkline tutorial" ~markdown:tutorial_markdown ()

let handle_key s key_str ~size:_ =
  match Miaou.Core.Keys.of_string key_str with
  | Some (Miaou.Core.Keys.Char "Esc") | Some (Miaou.Core.Keys.Char "Escape") ->
      go_back s
  | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "t" ->
      show_tutorial () ;
      s
  | Some (Miaou.Core.Keys.Char " ") -> simulate_tick s
  | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "r" ->
      simulate_tick s
  | _ -> s

let move s _ = s
let refresh s = simulate_tick s
let enter s = s
let service_select s _ = s
let service_cycle s _ = simulate_tick s
let handle_modal_key s _ ~size:_ = s
let next_page s = s.next_page
let keymap (_ : state) = []
let handled_keys () = []
let back s = go_back s
let has_modal _ = false
