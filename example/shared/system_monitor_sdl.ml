(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(* SDL-specific rendering for System Monitor demo
   This module provides helpers that automatically detect SDL mode
   and use enhanced rendering when available, falling back to text otherwise *)

module Sparkline = Miaou_widgets_display.Sparkline_widget
module Sparkline_sdl = Miaou_widgets_display_sdl.Sparkline_widget_sdl
module Line_chart = Miaou_widgets_display.Line_chart_widget
module Line_chart_sdl = Miaou_widgets_display_sdl.Line_chart_widget_sdl
module SDL_ctx = Miaou_widgets_display.Sdl_chart_context
module Sdl = Tsdl.Sdl
module Ttf = Tsdl_ttf.Ttf

(* [SDL_ctx.renderer] is an opaque capability token (see sdl_chart_context.ml):
   this demo module, which does depend on tsdl directly, is one of the narrow
   boundaries that recovers the real [Sdl.renderer] from that token (mirroring
   the coercion the SDL driver performs on the registration side). *)
let renderer_of_token (t : SDL_ctx.renderer) : Sdl.renderer =
  Obj.magic t [@allow_forbidden "recover real SDL renderer from opaque token"]

(* Render sparkline - uses SDL if context available, otherwise text *)
let render_sparkline_sdl sparkline ~color ~thresholds =
  match SDL_ctx.get_context () with
  | None ->
      (* No SDL context - use text rendering without value (value added separately in demo_lib) *)
      Sparkline.render
        sparkline
        ~focus:false
        ~show_value:false
        ~color
        ~thresholds
        ()
  | Some ctx ->
      (* SDL context available - render chart to SDL and return text for layout *)
      let renderer : Sdl.renderer =
        renderer_of_token (SDL_ctx.get_renderer ctx)
      in
      (* Calculate dynamic X position based on layout *)
      let terminal_width = ctx.cols in
      let left_width = min 50 (terminal_width / 2) in
      let separator_width = 3 in
      let label_and_value_width = 17 in
      (* "CPU:  99.9 " or "NET:  99.9 KB/s " *)
      let x_pos = left_width + separator_width + label_and_value_width in

      let info : Sparkline_sdl.sdl_render_info =
        {
          renderer;
          x = ctx.char_w * x_pos;
          y = ctx.y_offset;
          width = 35;
          height = 1;
          char_w = ctx.char_w;
          char_h = ctx.char_h;
        }
      in
      Sparkline_sdl.render_sdl
        info
        sparkline
        ~focus:false
        ~show_value:false
        ~color
        ~thresholds
        () ;
      (* Move y_offset down for next sparkline - single line spacing *)
      ctx.y_offset <- ctx.y_offset + ctx.char_h ;
      (* In SDL mode: return spaces for sparkline area so SDL shows through *)
      (* Value will be displayed separately before the sparkline in demo_lib *)
      String.make 35 ' '

(* Render line chart - uses SDL if context available, otherwise text *)
let render_line_chart_sdl chart ~thresholds =
  match SDL_ctx.get_context () with
  | None ->
      (* No SDL context - use text rendering without grid, smoother look *)
      Line_chart.render chart ~show_axes:false ~show_grid:false ~thresholds ()
  | Some ctx ->
      (* SDL context available - render directly to SDL *)
      let renderer : Sdl.renderer =
        renderer_of_token (SDL_ctx.get_renderer ctx)
      in
      (* Line chart starts after: title(1) + sys_info(~5) + blank(1) = ~7 lines *)
      let line_chart_y = ctx.char_h * 8 in
      let info : Line_chart_sdl.sdl_render_info =
        {
          renderer;
          x = ctx.char_w * 1;
          y = line_chart_y;
          width = 78;
          height = 8;
          char_w = ctx.char_w;
          char_h = ctx.char_h;
        }
      in
      Line_chart_sdl.render_sdl
        info
        chart
        ~show_axes:true
        ~show_grid:false
        ~thresholds
        () ;
      ctx.y_offset <- ctx.y_offset + (ctx.char_h * 9) ;
      (* Return newlines to reserve vertical space - height = 8 lines *)
      String.make 8 '\n'
