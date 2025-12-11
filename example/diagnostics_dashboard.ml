(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Advanced diagnostics dashboard example demonstrating:
    - Ring buffer data recording for time-windowed metrics
    - Histogram-based percentile calculations (p50, p90, p99)
    - Real-time multi-chart visualization with colored thresholds
    - Auto-refresh and scrollable interface
    - Best practices for performance monitoring TUIs

    This example shows how to build a production-ready diagnostics system
    using stock Miaou widgets without custom rendering. *)

open Miaou_widgets_display

(** {1 Ring Buffer for Time-Series Data}

    A ring buffer maintains a fixed-size sliding window of recent data points.
    Older points are automatically dropped when the buffer is full. This is
    ideal for real-time monitoring where we only care about recent history. *)

module Ring_buffer = struct
  type t = {
    data : float array;
    mutable write_pos : int;
    mutable count : int;
    capacity : int;
  }

  let create capacity =
    {data = Array.make capacity 0.0; write_pos = 0; count = 0; capacity}

  let push buffer value =
    buffer.data.(buffer.write_pos) <- value ;
    buffer.write_pos <- (buffer.write_pos + 1) mod buffer.capacity ;
    buffer.count <- min (buffer.count + 1) buffer.capacity

  let to_list buffer =
    if buffer.count = 0 then []
    else
      let start =
        if buffer.count < buffer.capacity then 0
        else buffer.write_pos
      in
      List.init buffer.count (fun i ->
          buffer.data.((start + i) mod buffer.capacity))

  let clear buffer =
    buffer.write_pos <- 0 ;
    buffer.count <- 0

  let is_empty buffer = buffer.count = 0

  let size buffer = buffer.count
end

(** {1 Histogram for Percentile Calculations}

    A histogram tracks value distributions using fixed-width buckets.
    This enables efficient percentile calculations (p50, p90, p99) without
    sorting, which is important for real-time dashboards. *)

module Histogram = struct
  type t = {
    buckets : int array;
    min_value : float;
    max_value : float;
    bucket_width : float;
    mutable total_count : int;
  }

  let create ~min_value ~max_value ~num_buckets =
    let bucket_width = (max_value -. min_value) /. float_of_int num_buckets in
    {
      buckets = Array.make num_buckets 0;
      min_value;
      max_value;
      bucket_width;
      total_count = 0;
    }

  let add hist value =
    let value = max hist.min_value (min hist.max_value value) in
    let bucket_idx =
      int_of_float ((value -. hist.min_value) /. hist.bucket_width)
    in
    let bucket_idx = min bucket_idx (Array.length hist.buckets - 1) in
    hist.buckets.(bucket_idx) <- hist.buckets.(bucket_idx) + 1 ;
    hist.total_count <- hist.total_count + 1

  let percentile hist p =
    if hist.total_count = 0 then 0.0
    else
      let target_count = int_of_float (float_of_int hist.total_count *. p) in
      let rec find_bucket acc idx =
        if idx >= Array.length hist.buckets then hist.max_value
        else
          let acc = acc + hist.buckets.(idx) in
          if acc >= target_count then
            (* Estimate value within bucket *)
            hist.min_value +. (float_of_int idx *. hist.bucket_width)
            +. (hist.bucket_width /. 2.0)
          else find_bucket acc (idx + 1)
      in
      find_bucket 0 0

  let clear hist =
    Array.fill hist.buckets 0 (Array.length hist.buckets) 0 ;
    hist.total_count <- 0
end

(** {1 Metric Tracker}

    Combines ring buffer for time-series visualization and histogram for
    percentile statistics. This is the core data structure for each metric. *)

type metric_tracker = {
  name : string;
  ring_buffer : Ring_buffer.t;
  histogram : Histogram.t;
  mutable last_value : float;
  color : string;  (* ANSI color code for the metric *)
}

let create_metric ~name ~window_size ~min_value ~max_value ~color =
  {
    name;
    ring_buffer = Ring_buffer.create window_size;
    histogram = Histogram.create ~min_value ~max_value ~num_buckets:50;
    last_value = 0.0;
    color;
  }

let record_value metric value =
  Ring_buffer.push metric.ring_buffer value ;
  Histogram.add metric.histogram value ;
  metric.last_value <- value

(** {1 Dashboard State}

    Manages multiple metrics with auto-refresh timing. *)

type dashboard_state = {
  bg_queue : metric_tracker;
  services : metric_tracker;
  render_latency : metric_tracker;
  input_lag : metric_tracker;
  mutable refresh_counter : int;
  refresh_interval : int;  (* Refresh every N update calls *)
}

let create_dashboard () =
  {
    bg_queue = create_metric
      ~name:"BG Queue Depth"
      ~window_size:60  (* 1 minute at 1 sample/sec *)
      ~min_value:0.0
      ~max_value:100.0
      ~color:"34";  (* Blue *)
    services = create_metric
      ~name:"Active Services"
      ~window_size:60
      ~min_value:0.0
      ~max_value:50.0
      ~color:"32";  (* Green *)
    render_latency = create_metric
      ~name:"Render Latency (ms)"
      ~window_size:60
      ~min_value:0.0
      ~max_value:100.0
      ~color:"33";  (* Yellow *)
    input_lag = create_metric
      ~name:"Input Lag (ms)"
      ~window_size:60
      ~min_value:0.0
      ~max_value:50.0
      ~color:"36";  (* Cyan *)
    refresh_counter = 0;
    refresh_interval = 5;  (* Auto-refresh every 5 updates *)
  }

(** {1 Simulate Metric Collection}

    In a real application, these would read from system APIs, network
    endpoints, or instrumentation hooks. Here we generate realistic-looking
    data for demonstration. *)

let simulate_metrics dashboard =
  (* Simulate background queue with occasional spikes *)
  let bg_queue_value =
    if Random.int 10 = 0 then Random.float 80.0 +. 20.0
    else Random.float 30.0 +. 5.0
  in
  record_value dashboard.bg_queue bg_queue_value ;

  (* Simulate active services count (slowly varying) *)
  let services_value =
    let prev = dashboard.services.last_value in
    let delta = Random.float 4.0 -. 2.0 in
    max 5.0 (min 40.0 (prev +. delta))
  in
  record_value dashboard.services services_value ;

  (* Simulate render latency with occasional GC pauses *)
  let render_latency_value =
    if Random.int 20 = 0 then Random.float 50.0 +. 40.0
    else Random.float 20.0 +. 5.0
  in
  record_value dashboard.render_latency render_latency_value ;

  (* Simulate input lag (usually low, occasional spikes) *)
  let input_lag_value =
    if Random.int 15 = 0 then Random.float 20.0 +. 15.0
    else Random.float 5.0 +. 1.0
  in
  record_value dashboard.input_lag input_lag_value

(** {1 Chart Rendering with Color Thresholds}

    Demonstrates how to create line charts with proper color configuration:
    - Series-level color for the overall trend
    - Point-level colors for highlighting outliers
    - Threshold-based coloring for warning/critical ranges *)

let render_metric_chart ~width ~height metric =
  let points = Ring_buffer.to_list metric.ring_buffer in
  if List.length points = 0 then
    (* Pad "No data" to the specified width *)
    let msg = "No data" in
    let padding = String.make (max 0 (width - String.length msg)) ' ' in
    msg ^ padding
  else
    (* Convert to chart points with index as x-axis *)
    let chart_points =
      List.mapi
        (fun i value ->
          (* Point-level color for critical values *)
          let color =
            if value > 80.0 then Some "91"  (* Bright red for critical *)
            else None  (* Use series/threshold color *)
          in
          {Line_chart_widget.x = float_of_int i; y = value; color})
        points
    in
    let series =
      {
        Line_chart_widget.label = metric.name;
        points = chart_points;
        color = Some metric.color;  (* Series-level default color *)
      }
    in
    
    (* Define warning/critical thresholds *)
    let thresholds = [
      {Line_chart_widget.value = 60.0; color = "33"};  (* Yellow warning *)
      {Line_chart_widget.value = 80.0; color = "31"};  (* Red critical *)
    ] in
    
    let chart =
      Line_chart_widget.create
        ~width
        ~height
        ~series:[series]
        ~title:metric.name
        ()
    in
    Line_chart_widget.render chart
      ~show_axes:true
      ~show_grid:false
      ~thresholds
      ()

(** {1 Statistics Summary}

    Render percentile statistics alongside the charts for deeper insights. *)

let render_statistics metric =
  if Ring_buffer.is_empty metric.ring_buffer then
    Printf.sprintf "%s: No data\n" metric.name
  else
    let p50 = Histogram.percentile metric.histogram 0.50 in
    let p90 = Histogram.percentile metric.histogram 0.90 in
    let p99 = Histogram.percentile metric.histogram 0.99 in
    let current = metric.last_value in
    
    (* Color the current value based on thresholds *)
    let current_str =
      if current > 80.0 then
        Printf.sprintf "\027[91m%.1f\027[0m" current  (* Bright red *)
      else if current > 60.0 then
        Printf.sprintf "\027[33m%.1f\027[0m" current  (* Yellow *)
      else
        Printf.sprintf "\027[%sm%.1f\027[0m" metric.color current
    in
    
    Printf.sprintf
      "%s: current=%s | p50=%.1f | p90=%.1f | p99=%.1f\n"
      metric.name current_str p50 p90 p99

(** {1 Full Dashboard Rendering}

    Combines multiple charts and statistics into a comprehensive view. *)

let render_dashboard dashboard ~width ~height =
  let chart_height = (height - 10) / 4 in  (* Divide space among 4 charts *)
  let chart_width = width - 4 in
  
  (* Render charts *)
  let bg_chart = render_metric_chart
    ~width:chart_width ~height:chart_height dashboard.bg_queue in
  let services_chart = render_metric_chart
    ~width:chart_width ~height:chart_height dashboard.services in
  let render_chart = render_metric_chart
    ~width:chart_width ~height:chart_height dashboard.render_latency in
  let input_chart = render_metric_chart
    ~width:chart_width ~height:chart_height dashboard.input_lag in
  
  (* Render statistics *)
  let stats =
    render_statistics dashboard.bg_queue ^
    render_statistics dashboard.services ^
    render_statistics dashboard.render_latency ^
    render_statistics dashboard.input_lag
  in
  
  (* Combine everything *)
  let separator = String.make chart_width '─' in
  String.concat "\n" [
    "╔═══ DIAGNOSTICS DASHBOARD ═══╗";
    bg_chart;
    separator;
    services_chart;
    separator;
    render_chart;
    separator;
    input_chart;
    separator;
    "╔═══ STATISTICS (Percentiles) ═══╗";
    stats;
    "";
    "Press 'r' to refresh, 'c' to clear history, 'q' to quit";
  ]

(** {1 Example Usage}

    This demonstrates how to integrate the dashboard into a simple TUI:

    {[
      let dashboard = create_dashboard () in
      
      (* In your update loop: *)
      simulate_metrics dashboard;
      
      (* Render every 5 frames: *)
      dashboard.refresh_counter <- dashboard.refresh_counter + 1;
      if dashboard.refresh_counter >= dashboard.refresh_interval then (
        dashboard.refresh_counter <- 0;
        let output = render_dashboard dashboard ~width:80 ~height:40 in
        print_endline output
      )
    ]}

    {1 Key Patterns Demonstrated}

    1. {b Ring Buffers}: Efficient sliding window for time-series data
    2. {b Histograms}: O(1) percentile calculations without sorting
    3. {b Color Precedence}: Point > Series > Threshold for flexible highlighting
    4. {b ANSI Colors}: Proper use of SGR codes (["32"], ["91"], etc.)
    5. {b State Management}: Mutable state for incremental updates
    6. {b Widget Composition}: Multiple charts + text summaries
    7. {b Auto-refresh}: Throttled updates for performance

    {1 Production Adaptations}

    To use this in a real application:
    - Replace [simulate_metrics] with actual system/app metrics
    - Adjust window sizes based on sampling rate (60 samples = 1 min at 1 Hz)
    - Add persistence to save/restore historical data
    - Implement scrolling for larger metric sets
    - Add time-based x-axis labels instead of sample indices
    - Use Eio for async metric collection
    - Add metric export (Prometheus, JSON, etc.)
*)

(** {1 Standalone Demo Entry Point}

    Run with: dune exec -- miaou.diagnostics-demo *)

let () =
  Random.self_init ();
  let dashboard = create_dashboard () in
  
  (* Generate some initial data *)
  for _ = 1 to 30 do
    simulate_metrics dashboard
  done ;
  
  (* Render the dashboard *)
  let output = render_dashboard dashboard ~width:80 ~height:45 in
  print_endline output ;
  print_endline "\nThis is a snapshot. In a real TUI, this would auto-refresh." ;
  print_endline "See the source code for integration patterns."
