(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37"]

open Miaou_core
module Narrow_modal = Miaou_core.Narrow_modal
module Logger_capability = Miaou_interfaces.Logger_capability
module Fibers = Miaou_helpers.Fiber_runtime
module Widgets = Miaou_widgets_display.Widgets

(* One-time narrow terminal warning flag *)
let narrow_warned = ref false

(* Debug overlay - shows FPS/TPS when MIAOU_OVERLAY is set *)
let overlay_enabled =
  lazy
    (match Sys.getenv_opt "MIAOU_OVERLAY" with
    | Some ("1" | "true" | "TRUE" | "yes" | "YES") -> true
    | _ -> false)

type tps_tracker = {
  mutable tick_count : int;
  mutable last_time : float;
  mutable current_tps : float;
}

let create_tps_tracker () =
  {tick_count = 0; last_time = Unix.gettimeofday (); current_tps = 0.0}

let update_tps tracker =
  tracker.tick_count <- tracker.tick_count + 1 ;
  let now = Unix.gettimeofday () in
  let elapsed = now -. tracker.last_time in
  if elapsed >= 1.0 then begin
    tracker.current_tps <- float_of_int tracker.tick_count /. elapsed ;
    tracker.tick_count <- 0 ;
    tracker.last_time <- now
  end

let render_overlay_text ~loop_fps ~render_fps ~tps ~cols
    (ops : Matrix_buffer.batch_ops) =
  let text =
    Printf.sprintf "matrix L:%.0f R:%.0f T:%.0f" loop_fps render_fps tps
  in
  let len = String.length text in
  let start_col = cols - len - 1 in
  if start_col > 0 then begin
    let style = {Matrix_cell.default_style with dim = true; fg = 245} in
    String.iteri
      (fun i c ->
        ops.set_char ~row:0 ~col:(start_col + i) ~char:(String.make 1 c) ~style)
      text
  end

(* Pack page and state together to avoid GADT escaping issues *)
type packed_state =
  | Packed :
      (module Tui_page.PAGE_SIG with type state = 's) * 's Navigation.t
      -> packed_state

type context = {
  config : Matrix_config.t;
  buffer : Matrix_buffer.t;
  parser : Matrix_ansi_parser.t;
  render_loop : Matrix_render_loop.t;
  io : Matrix_io.t;
}

let eio_sleep env seconds =
  if seconds > 0.001 then Eio.Time.sleep env#clock seconds

let run ctx ~(env : Eio_unix.Stdenv.base)
    (initial_page : (module Tui_page.PAGE_SIG)) :
    [`Quit | `Back | `SwitchTo of string] =
  let tick_time_s = ctx.config.tick_time_ms /. 1000.0 in

  (* TPS tracker for debug overlay *)
  let tps_tracker = create_tps_tracker () in

  (* Track modal state to trigger full redraw on modal open/close *)
  let last_modal_active = ref false in

  (* Frame counter for periodic partial refresh (doesn't reset like tick_count) *)
  let frame_counter = ref 0 in

  (* Track last size for narrow warning detection *)
  let last_size = ref {LTerm_geom.rows = 24; cols = 80} in

  (* Esc cooldown: after closing a modal with Esc, suppress further Esc keys
     for a short period to prevent key-repeat from reaching the underlying page
     (e.g. causing the app to quit when the user holds Esc to close a modal). *)
  let esc_cooldown_until = ref 0.0 in
  let esc_cooldown_s = 0.2 in

  (* Convert a packed state with pending navigation into the loop outcome. *)
  let nav_outcome packed =
    let (Packed ((module Page), ps)) = packed in
    ignore (Page.init, ps) ;
    match Navigation.pending ps with
    | Some Navigation.Quit ->
        Matrix_render_loop.shutdown ctx.render_loop ;
        `Quit
    | Some Navigation.Back ->
        Matrix_render_loop.shutdown ctx.render_loop ;
        `Back
    | Some (Navigation.Goto name) -> `SwitchTo name
    | None ->
        (* Should not happen — caller checks pending first *)
        `Quit
  in

  (* Main loop *)
  let rec loop packed =
    let tick_start = Unix.gettimeofday () in
    let (Packed ((module Page), ps)) = packed in

    (* Get current size *)
    let rows, cols = ctx.io.size () in
    let size = {LTerm_geom.rows; cols} in

    (* Check if we need to resize buffer *)
    let buf_rows, buf_cols = Matrix_buffer.size ctx.buffer in
    if rows <> buf_rows || cols <> buf_cols then begin
      Matrix_buffer.resize ctx.buffer ~rows ~cols ;
      Matrix_buffer.mark_all_dirty ctx.buffer
    end ;

    (* One-time narrow terminal warning (only once per session) *)
    let prev_cols = !last_size.LTerm_geom.cols in
    if
      (cols < 80 && not !narrow_warned)
      || (cols < 80 && prev_cols >= 80 && not !narrow_warned)
    then (
      (match Logger_capability.get () with
      | Some logger ->
          logger.logf
            Warning
            (Printf.sprintf
               "WIDTH_CROSSING: prev=%d new=%d (showing narrow modal)"
               prev_cols
               cols)
      | None -> ()) ;
      narrow_warned := true ;
      Modal_manager.push
        (module Narrow_modal.Page)
        ~init:(Narrow_modal.Page.init ())
        ~ui:
          {
            title = "Narrow terminal";
            left = Some 2;
            max_width = None;
            dim_background = true;
          }
        ~commit_on:[]
        ~cancel_on:[]
        ~on_close:(fun (_ : Narrow_modal.Page.pstate) _ -> ()) ;
      Modal_manager.set_consume_next_key () ;
      let my_title = "Narrow terminal" in
      Fibers.spawn (fun env ->
          Eio.Time.sleep env#clock 5.0 ;
          match Modal_manager.top_title_opt () with
          | Some t when t = my_title -> Modal_manager.close_top `Cancel
          | _ -> ())) ;
    last_size := size ;

    (* Build header lines for narrow terminal warning banner *)
    let header_lines =
      if cols < 80 then
        [
          Miaou_widgets_display.Widgets.warning_banner
            ~cols
            (Printf.sprintf
               "Narrow terminal: %d cols (< 80). Some UI may be truncated."
               cols);
        ]
      else []
    in

    (* Build footer hints from page key_hints *)
    let footer_pairs =
      let hints = Page.key_hints ps in
      if hints <> [] then
        List.map
          (fun (h : Miaou_core.Tui_page.key_hint) -> (h.key, h.help))
          hints
      else []
    in
    let footer_str =
      if footer_pairs = [] then ""
      else Widgets.footer_hints_wrapped_capped ~cols ~max_lines:2 footer_pairs
    in
    let footer_lines =
      if footer_str = "" then 0
      else List.length (String.split_on_char '\n' footer_str)
    in

    (* Reduce available rows for the page view to leave room for footer *)
    let view_size =
      if footer_lines > 0 then
        {size with LTerm_geom.rows = max 1 (rows - footer_lines)}
      else size
    in

    (* Render page view to ANSI string *)
    let view_output = Page.view ps ~focus:true ~size:view_size in

    (* Append footer if present *)
    let view_output =
      if footer_str = "" then view_output else view_output ^ "\n" ^ footer_str
    in

    (* Prepend header lines if any *)
    let view_output =
      match header_lines with
      | [] -> view_output
      | lines -> String.concat "\n" lines ^ "\n" ^ view_output
    in

    (* Check for modal state change *)
    let modal_active = Modal_manager.has_active () in
    let modal_just_changed = modal_active <> !last_modal_active in
    if modal_just_changed then last_modal_active := modal_active ;

    (* Render modal overlay if active *)
    let view_output =
      if modal_active then
        match
          Miaou_internals.Modal_renderer.render_overlay
            ~cols:(Some cols)
            ~base:view_output
            ~rows
            ()
        with
        | Some v -> v
        | None -> view_output
      else view_output
    in

    (* Update TPS tracker *)
    update_tps tps_tracker ;

    (* Update back buffer with new view - thread-safe batch operation *)
    Matrix_buffer.with_back_buffer ctx.buffer (fun ops ->
        (* Clear back buffer *)
        ops.clear () ;

        (* Parse ANSI output into buffer using batch set_char *)
        Matrix_ansi_parser.reset ctx.parser ;
        let _ =
          Matrix_ansi_parser.parse_into_batch
            ctx.parser
            ops
            ~row:0
            ~col:0
            view_output
        in

        (* Render debug overlay if enabled *)
        if Lazy.force overlay_enabled then
          render_overlay_text
            ~loop_fps:(Matrix_render_loop.loop_fps ctx.render_loop)
            ~render_fps:(Matrix_render_loop.current_fps ctx.render_loop)
            ~tps:tps_tracker.current_tps
            ~cols
            ops) ;

    (* On modal state change (open OR close), do synchronous clear+render.
       This prevents artifacts when modal closes and underlying content has changed. *)
    if modal_just_changed then begin
      Matrix_buffer.mark_all_dirty ctx.buffer ;
      ctx.io.write "\027[2J\027[H" ;
      Matrix_render_loop.force_render ctx.render_loop
    end ;

    (* Periodic full refresh every 120 frames (~2s at 60 TPS) to catch any artifacts *)
    incr frame_counter ;
    if !frame_counter mod 120 = 0 then Matrix_buffer.mark_all_dirty ctx.buffer ;

    (* Drain all pending input events from the queue and process them
       sequentially.  When the queue is empty we still run one tick
       (service_cycle / refresh) and sleep for the remainder of the budget. *)
    let events = ctx.io.drain () in
    process_events (Packed ((module Page), ps)) events tick_start size
  and process_events packed events tick_start size =
    match events with
    | [] ->
        (* No events — run service_cycle and sleep for remainder of tick *)
        let (Packed ((module Page), ps)) = packed in
        let ps' = Page.service_cycle (Page.refresh ps) 0 in
        check_navigation (Packed ((module Page), ps')) tick_start
    | ev :: rest -> (
        match handle_single_event packed ev size with
        | `Continue packed' -> process_events packed' rest tick_start size
        | `Exit result -> result)
  and handle_single_event packed event size =
    let (Packed ((module Page), ps)) = packed in
    let rows = size.LTerm_geom.rows in
    let cols = size.LTerm_geom.cols in
    match event with
    | Matrix_io.Quit ->
        Matrix_render_loop.shutdown ctx.render_loop ;
        `Exit `Quit
    | Matrix_io.Resize ->
        ctx.io.invalidate_size_cache () ;
        (* Clear display on resize to avoid artifacts from old layout *)
        ctx.io.write "\027[2J\027[H" ;
        Matrix_buffer.mark_all_dirty ctx.buffer ;
        `Continue packed
    | Matrix_io.Refresh ->
        let ps' = Page.service_cycle (Page.refresh ps) 0 in
        `Continue (Packed ((module Page), ps'))
    | Matrix_io.Idle -> `Continue packed
    | Matrix_io.Key key -> (
        (* Debug: log received key if MIAOU_DEBUG is set *)
        if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then (
          let oc =
            open_out_gen [Open_append; Open_creat] 0o644 "/tmp/miaou-keys.log"
          in
          Printf.fprintf
            oc
            "Key received: %S, modal_active=%b, has_modal=%b\n%!"
            key
            (Modal_manager.has_active ())
            (Page.has_modal ps) ;
          close_out oc) ;
        (* Set modal size before handling keys *)
        Modal_manager.set_current_size rows cols ;
        (* Helper: detect whether the transient narrow modal is currently active *)
        let is_narrow_modal_active () =
          match Modal_manager.top_title_opt () with
          | Some t when t = "Narrow terminal" -> true
          | _ -> false
        in
        let packed' =
          (* Check if modal is active - if so, send keys to modal instead of page *)
          if Modal_manager.has_active () then begin
            (* If the narrow modal is active, close it on any key *)
            if is_narrow_modal_active () then Modal_manager.close_top `Cancel
            else Modal_manager.handle_key key ;
            (* If modal was closed by Esc, activate cooldown *)
            if
              (key = "Esc" || key = "Escape")
              && not (Modal_manager.has_active ())
            then esc_cooldown_until := Unix.gettimeofday () +. esc_cooldown_s ;
            (* After modal handles key, run service_cycle *)
            let ps' = Page.service_cycle (Page.refresh ps) 0 in
            Packed ((module Page), ps')
          end
          else if Page.has_modal ps then begin
            (* Page has its own modal - use page's modal key handler *)
            let ps' =
              match Keys.of_string key with
              | Some typed_key ->
                  let ps', _result = Page.on_modal_key ps typed_key ~size in
                  ps'
              | None ->
                  (* Fallback to legacy handle_modal_key for unparseable keys *)
                  Page.handle_modal_key ps key ~size
            in
            (* If modal was closed by Esc, activate cooldown *)
            if (key = "Esc" || key = "Escape") && not (Page.has_modal ps') then
              esc_cooldown_until := Unix.gettimeofday () +. esc_cooldown_s ;
            Packed ((module Page), ps')
          end
          else if
            (* Suppress Esc keys during cooldown period after modal close *)
            (key = "Esc" || key = "Escape")
            && Unix.gettimeofday () < !esc_cooldown_until
          then packed
          else
            (* All keys go through on_key *)
            let ps' =
              match Keys.of_string key with
              | Some typed_key ->
                  let ps', _result = Page.on_key ps typed_key ~size in
                  ps'
              | None ->
                  (* Fallback to legacy handle_key for unparseable keys *)
                  Page.handle_key ps key ~size
            in
            Packed ((module Page), ps')
        in
        (* Check navigation after each key — if a key triggers navigation,
           stop processing remaining events in this tick *)
        let (Packed ((module Page2), ps2)) = packed' in
        let ps2 =
          match Modal_manager.take_pending_navigation () with
          | Some (Navigation.Goto page) -> Navigation.goto page ps2
          | Some Navigation.Back -> Navigation.back ps2
          | Some Navigation.Quit -> Navigation.quit ps2
          | None -> ps2
        in
        let next = Navigation.pending ps2 in
        match next with
        | Some _ ->
            (* Navigation requested — stop processing further events *)
            `Exit (nav_outcome (Packed ((module Page2), ps2)))
        | None -> `Continue (Packed ((module Page2), ps2)))
    | Matrix_io.Mouse (row, col) ->
        let mouse_key = Printf.sprintf "Mouse:%d:%d" row col in
        (* Set modal size before handling keys *)
        Modal_manager.set_current_size rows cols ;
        let packed' =
          if Modal_manager.has_active () then begin
            Modal_manager.handle_key mouse_key ;
            let ps' = Page.service_cycle (Page.refresh ps) 0 in
            Packed ((module Page), ps')
          end
          else if Page.has_modal ps then
            let ps' = Page.handle_modal_key ps mouse_key ~size in
            Packed ((module Page), ps')
          else
            let ps' = Page.handle_key ps mouse_key ~size in
            Packed ((module Page), ps')
        in
        `Continue packed'
  and check_navigation packed tick_start =
    let (Packed ((module Page), ps)) = packed in
    (* Check for pending navigation from modal callbacks *)
    let ps =
      match Modal_manager.take_pending_navigation () with
      | Some (Navigation.Goto page) -> Navigation.goto page ps
      | Some Navigation.Back -> Navigation.back ps
      | Some Navigation.Quit -> Navigation.quit ps
      | None -> ps
    in
    let next = Navigation.pending ps in
    (* Debug: log navigation if MIAOU_DEBUG is set *)
    (if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then
       match next with
       | Some nav ->
           let oc =
             open_out_gen [Open_append; Open_creat] 0o644 "/tmp/miaou-keys.log"
           in
           let nav_str =
             match nav with
             | Navigation.Goto name -> Printf.sprintf "Goto %S" name
             | Navigation.Back -> "Back"
             | Navigation.Quit -> "Quit"
           in
           Printf.fprintf oc "Navigation requested: %s\n%!" nav_str ;
           close_out oc
       | None -> ()) ;
    match next with
    | Some Navigation.Quit ->
        Matrix_render_loop.shutdown ctx.render_loop ;
        `Quit
    | Some Navigation.Back ->
        Matrix_render_loop.shutdown ctx.render_loop ;
        `Back
    | Some (Navigation.Goto name) -> `SwitchTo name
    | None ->
        (* Maintain TPS by sleeping if we have time left *)
        let elapsed = Unix.gettimeofday () -. tick_start in
        let sleep_time = tick_time_s -. elapsed in
        eio_sleep env sleep_time ;
        loop (Packed ((module Page), ps))
  in

  (* Start with initial page *)
  let (module P) = initial_page in
  loop (Packed ((module P), P.init ()))
