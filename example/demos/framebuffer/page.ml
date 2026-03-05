(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

module Sparkline = Miaou_widgets_display.Sparkline_widget
module Line_chart = Miaou_widgets_display.Line_chart_widget
module Bar_chart = Miaou_widgets_display.Bar_chart_widget
module FB = Miaou_widgets_display.Framebuffer_widget
module TC = Miaou_widgets_display.Terminal_caps

(* Pixel render mode cycle (for framebuffer demo) *)
type fb_mode = Octant | Sextant | Half_block | Braille

(* Chart render mode cycle *)
type chart_mode = ASCII | Braille_chart | Octant_chart

module Inner = struct
  let tutorial_title = "Framebuffer & Octant Charts"

  let tutorial_markdown = [%blob "README.md"]

  type state = {
    fb : FB.t;
    fb_mode : fb_mode;
    chart_mode : chart_mode;
    seed : int;
    next_page : string option;
  }

  type msg = unit

  (* Generate a colorful gradient + shapes into the framebuffer *)
  let fill_framebuffer fb seed width_px height_px =
    FB.clear fb ~r:0 ~g:0 ~b:0 ;
    (* Background gradient *)
    for y = 0 to height_px - 1 do
      for x = 0 to width_px - 1 do
        let r = ((x * 255 / max 1 (width_px - 1)) + seed) mod 256 in
        let g = ((y * 255 / max 1 (height_px - 1)) + (seed * 2)) mod 256 in
        let b = (x + y + (seed * 3)) * 128 / (width_px + height_px) mod 256 in
        FB.set_pixel fb ~x ~y ~r ~g ~b
      done
    done ;
    (* Bright filled rectangle *)
    let rx = width_px / 4 and ry = height_px / 4 in
    FB.fill_rect
      fb
      ~x:rx
      ~y:ry
      ~w:(width_px / 2)
      ~h:(height_px / 2)
      ~r:255
      ~g:200
      ~b:50 ;
    (* Inner red rectangle *)
    FB.fill_rect
      fb
      ~x:(rx + 4)
      ~y:(ry + 4)
      ~w:((width_px / 2) - 8)
      ~h:((height_px / 2) - 8)
      ~r:200
      ~g:50
      ~b:50

  let fb_mode_label = function
    | Octant -> "Octant (U+1CD00)"
    | Sextant -> "Sextant (U+1FB00)"
    | Half_block -> "Half-block (▀)"
    | Braille -> "Braille (dots)"

  let chart_mode_label = function
    | ASCII -> "ASCII"
    | Braille_chart -> "Braille"
    | Octant_chart -> "Octant"

  let init () =
    let fb = FB.create () in
    {
      fb;
      fb_mode = Octant;
      chart_mode = Octant_chart;
      seed = 42;
      next_page = None;
    }

  let update s (_ : msg) = s

  let view s ~focus:_ ~size =
    let module W = Miaou_widgets_display.Widgets in
    let width = size.LTerm_geom.cols in
    let header = W.titleize "Framebuffer & Octant Rendering" in

    (* Detected mode *)
    let detected = TC.detect () in
    let detected_str =
      match detected with
      | TC.Sixel -> "Sixel"
      | TC.Octant -> "Octant"
      | TC.Sextant -> "Sextant"
      | TC.Half_block -> "Half_block"
      | TC.Braille -> "Braille"
    in

    (* Framebuffer section *)
    let fb_cols = min 40 (width / 2) in
    let fb_rows = 8 in

    (* Override detected mode for the demo *)
    let override =
      match s.fb_mode with
      | Octant -> "octant"
      | Sextant -> "sextant"
      | Half_block -> "half_block"
      | Braille -> "braille"
    in
    Unix.putenv "MIAOU_PIXEL_MODE" override ;
    (* Reset cached mode so it picks up the new env var *)
    TC.reset_cache () ;

    let px_w, px_h =
      match s.fb_mode with
      | Octant -> (fb_cols * 2, fb_rows * 4)
      | Sextant -> (fb_cols * 2, fb_rows * 3)
      | Half_block -> (fb_cols * 1, fb_rows * 2)
      | Braille -> (fb_cols * 2, fb_rows * 4)
    in
    (* Ensure the pixel buffer is allocated to the correct size before filling.
       On the first frame the buffer starts empty, so we render once (blank) to
       trigger allocation, then fill with real content and render the final frame.
       On subsequent frames the pre-render returns immediately from cache (dirty=false)
       while fill sets dirty=true, so only one real encode happens. *)
    ignore (FB.render s.fb ~cols:fb_cols ~rows:fb_rows) ;
    fill_framebuffer s.fb s.seed px_w px_h ;
    let fb_output = FB.render s.fb ~cols:fb_cols ~rows:fb_rows in

    (* Chart section *)
    let spark_mode =
      match s.chart_mode with
      | ASCII -> Sparkline.ASCII
      | Braille_chart -> Sparkline.Braille
      | Octant_chart -> Sparkline.Octant
    in
    let line_mode =
      match s.chart_mode with
      | ASCII -> Line_chart.ASCII
      | Braille_chart -> Line_chart.Braille
      | Octant_chart -> Line_chart.Octant
    in
    let bar_mode =
      match s.chart_mode with
      | ASCII -> Bar_chart.ASCII
      | Braille_chart -> Bar_chart.Braille
      | Octant_chart -> Bar_chart.Octant
    in

    let chart_w = min 40 (width - 2) in

    let sp = Sparkline.create ~width:chart_w ~max_points:(chart_w * 2) () in
    for i = 0 to (chart_w * 2) - 1 do
      let v = 50.0 +. (30.0 *. sin (float_of_int (i + s.seed) /. 6.0)) in
      Sparkline.push sp v
    done ;
    let spark_output =
      Sparkline.render
        sp
        ~focus:false
        ~show_value:true
        ~color:"38;5;82"
        ~mode:spark_mode
        ()
    in

    let points =
      List.init (chart_w / 2) (fun i ->
          let x = float_of_int i in
          let y = 50.0 +. (25.0 *. sin (x /. 3.5)) in
          {Line_chart.x; y; color = None})
    in
    let series =
      [{Line_chart.label = "sin"; points; color = Some "38;5;202"}]
    in
    let line_chart = Line_chart.create ~width:chart_w ~height:6 ~series () in
    let line_output =
      Line_chart.render
        line_chart
        ~show_axes:false
        ~show_grid:false
        ~mode:line_mode
        ()
    in

    let bar_data =
      [
        ("Mon", 45.0, Some "38;5;160");
        ("Tue", 67.0, Some "38;5;208");
        ("Wed", 82.0, Some "38;5;220");
        ("Thu", 55.0, Some "38;5;118");
        ("Fri", 90.0, Some "38;5;45");
        ("Sat", 38.0, Some "38;5;177");
        ("Sun", 72.0, Some "38;5;99");
      ]
    in
    let bar_chart =
      Bar_chart.create ~width:chart_w ~height:6 ~data:bar_data ()
    in
    let bar_output =
      Bar_chart.render bar_chart ~show_values:false ~mode:bar_mode ()
    in

    let hint =
      W.dim
        (Printf.sprintf
           "Auto-detected: %s  |  m: cycle FB mode (%s)  |  c: cycle chart \
            mode (%s)  |  Space: new pixels  |  Esc: back"
           detected_str
           (fb_mode_label s.fb_mode)
           (chart_mode_label s.chart_mode))
    in

    String.concat
      "\n\n"
      [
        header;
        W.bold (Printf.sprintf "Framebuffer — %s:" (fb_mode_label s.fb_mode))
        ^ "\n" ^ fb_output;
        W.bold
          (Printf.sprintf "Charts — %s mode:" (chart_mode_label s.chart_mode));
        W.bold "Sparkline:" ^ "\n" ^ spark_output;
        W.bold "Line Chart:" ^ "\n" ^ line_output;
        W.bold "Bar Chart:" ^ "\n" ^ bar_output;
        hint;
      ]

  let go_back s =
    {s with next_page = Some Demo_shared.Demo_config.launcher_page_name}

  let handle_key s key_str ~size:(_ : LTerm_geom.size) =
    match Miaou.Core.Keys.of_string key_str with
    | Some Miaou.Core.Keys.Escape -> go_back s
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "m" ->
        let fb_mode =
          match s.fb_mode with
          | Octant -> Sextant
          | Sextant -> Half_block
          | Half_block -> Braille
          | Braille -> Octant
        in
        {s with fb_mode}
    | Some (Miaou.Core.Keys.Char k) when String.lowercase_ascii k = "c" ->
        let chart_mode =
          match s.chart_mode with
          | ASCII -> Braille_chart
          | Braille_chart -> Octant_chart
          | Octant_chart -> ASCII
        in
        {s with chart_mode}
    | Some (Miaou.Core.Keys.Char " ") -> {s with seed = (s.seed + 17) mod 256}
    | _ -> s

  let move s _ = s

  let refresh s = s

  let enter s = s

  let service_select s _ = s

  let service_cycle s _ = s

  let handle_modal_key s _ ~size:(_ : LTerm_geom.size) = s

  let next_page s = s.next_page

  let keymap (_ : state) = []

  let handled_keys () = []

  let back s = go_back s

  let has_modal _ = false
end

include Demo_shared.Demo_page.MakeSimple (Inner)
