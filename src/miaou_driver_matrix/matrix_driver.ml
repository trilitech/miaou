(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37"]

open Miaou_core

let available = true

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
  (* Render "matrix L:XX R:XX T:XX" in top-right corner with dim style
     L = Loop FPS (cap), R = Render FPS (actual), T = TPS *)
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
      (module Tui_page.PAGE_SIG with type state = 's) * 's
      -> packed_state

let run (initial_page : (module Tui_page.PAGE_SIG)) :
    [`Quit | `SwitchTo of string] =
  (* Load configuration *)
  let config = Matrix_config.load () in
  let tick_time_s = config.tick_time_ms /. 1000.0 in

  (* Setup terminal *)
  let terminal = Matrix_terminal.setup () in
  at_exit (fun () -> Matrix_terminal.cleanup terminal) ;

  (* Get terminal size *)
  let rows, cols = Matrix_terminal.size terminal in

  (* Create buffer *)
  let buffer = Matrix_buffer.create ~rows ~cols in

  (* Create parser and writer *)
  let parser = Matrix_ansi_parser.create () in
  let writer = Matrix_ansi_writer.create () in

  (* Create input handler *)
  let input = Matrix_input.create terminal in

  (* Create render loop *)
  let render_loop =
    Matrix_render_loop.create ~config ~buffer ~writer ~terminal
  in

  (* Enter raw mode and enable mouse *)
  Matrix_terminal.enter_raw terminal ;
  Matrix_terminal.enable_mouse terminal ;

  (* Hide cursor *)
  Matrix_terminal.write terminal Matrix_ansi_writer.cursor_hide ;

  (* Clear screen initially *)
  Matrix_terminal.write terminal "\027[2J\027[H" ;

  (* Start render domain - runs at 60 FPS in parallel *)
  Matrix_render_loop.start render_loop ;

  (* TPS tracker for debug overlay *)
  let tps_tracker = create_tps_tracker () in

  (* Track modal state to trigger full redraw on modal open/close *)
  let last_modal_active = ref false in

  (* Main loop - runs in main domain, handles input and effects *)
  let rec loop packed =
    let tick_start = Unix.gettimeofday () in
    let (Packed ((module Page), state)) = packed in

    (* Get current terminal size *)
    let rows, cols = Matrix_terminal.size terminal in
    let size = {LTerm_geom.rows; cols} in

    (* Check if we need to resize buffer *)
    let buf_rows, buf_cols = Matrix_buffer.size buffer in
    if rows <> buf_rows || cols <> buf_cols then begin
      Matrix_buffer.resize buffer ~rows ~cols ;
      Matrix_buffer.mark_all_dirty buffer
    end ;

    (* Render page view to ANSI string *)
    let view_output = Page.view state ~focus:true ~size in

    (* Check for modal state change - force full redraw on open/close *)
    let modal_active = Modal_manager.has_active () in
    let modal_just_changed = modal_active <> !last_modal_active in
    if modal_just_changed then begin
      (* Debug: dump view_output to file when modal state changes *)
      if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then (
        let filename =
          if modal_active then "/tmp/miaou-modal-open-base.ansi"
          else "/tmp/miaou-modal-close.ansi"
        in
        let oc = open_out filename in
        output_string oc view_output ;
        close_out oc) ;
      (* NOTE: mark_all_dirty is now done INSIDE with_back_buffer to avoid
         race condition where render domain could see cleared front with old back *)
      last_modal_active := modal_active
    end ;

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

    (* Debug: dump final view_output after overlay when modal just opened *)
    if
      Sys.getenv_opt "MIAOU_DEBUG" = Some "1"
      && modal_just_changed && modal_active
    then (
      let oc = open_out "/tmp/miaou-modal-with-overlay.ansi" in
      output_string oc view_output ;
      close_out oc) ;

    (* Update TPS tracker *)
    update_tps tps_tracker ;

    (* Update back buffer with new view - thread-safe batch operation.
       If modal just changed, force full redraw to avoid artifacts. *)
    Matrix_buffer.with_back_buffer
      ~force_full_redraw:modal_just_changed
      buffer
      (fun ops ->
        (* Clear back buffer *)
        ops.clear () ;

        (* Parse ANSI output into buffer using batch set_char *)
        Matrix_ansi_parser.reset parser ;
        let _ =
          Matrix_ansi_parser.parse_into_batch
            parser
            ops
            ~row:0
            ~col:0
            view_output
        in

        (* Render debug overlay if enabled *)
        if Lazy.force overlay_enabled then
          render_overlay_text
            ~loop_fps:(Matrix_render_loop.loop_fps render_loop)
            ~render_fps:(Matrix_render_loop.current_fps render_loop)
            ~tps:tps_tracker.current_tps
            ~cols
            ops) ;

    (* Poll for input with short timeout to maintain TPS *)
    let timeout_ms = int_of_float (config.tick_time_ms *. 0.8) in
    match Matrix_input.poll input ~timeout_ms with
    | Matrix_input.Quit ->
        Matrix_render_loop.shutdown render_loop ;
        `Quit
    | Matrix_input.Resize ->
        Matrix_terminal.invalidate_size_cache terminal ;
        (* Clear terminal on resize to avoid artifacts from old layout *)
        Matrix_terminal.write terminal "\027[2J\027[H" ;
        Matrix_buffer.mark_all_dirty buffer ;
        loop packed
    | Matrix_input.Refresh ->
        let state' = Page.service_cycle state 0 in
        check_navigation (Packed ((module Page), state')) tick_start
    | Matrix_input.Key key ->
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
            (Page.has_modal state) ;
          close_out oc) ;
        let _ = Matrix_input.drain_nav_keys input (Matrix_input.Key key) in
        (* Set modal size before handling keys *)
        Modal_manager.set_current_size rows cols ;
        (* Check if modal is active - if so, send keys to modal instead of page *)
        if Modal_manager.has_active () then begin
          Modal_manager.handle_key key ;
          (* After modal handles key, check if navigation requested *)
          let state' = Page.service_cycle state 0 in
          check_navigation (Packed ((module Page), state')) tick_start
        end
        else if Page.has_modal state then
          (* Page has its own modal - use page's modal key handler *)
          let state' = Page.handle_modal_key state key ~size in
          check_navigation (Packed ((module Page), state')) tick_start
        else
          (* Try page keymap first (for all keys including Esc) *)
          let keymap = Page.keymap state in
          let keymap_match = List.find_opt (fun (k, _, _) -> k = key) keymap in
          (* Debug: log keymap lookup *)
          if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then (
            let oc =
              open_out_gen [Open_append; Open_creat] 0o644 "/tmp/miaou-keys.log"
            in
            Printf.fprintf
              oc
              "Keymap lookup for %S: %s\n%!"
              key
              (match keymap_match with
              | Some (k, _, d) -> Printf.sprintf "found (%s: %s)" k d
              | None -> "not found") ;
            close_out oc) ;
          let state' =
            match keymap_match with
            | Some (_, transformer, _) -> transformer state
            | None -> Page.handle_key state key ~size
          in
          check_navigation (Packed ((module Page), state')) tick_start
    | Matrix_input.Mouse (row, col) ->
        let mouse_key = Printf.sprintf "Mouse:%d:%d" row col in
        (* Set modal size before handling keys *)
        Modal_manager.set_current_size rows cols ;
        (* Check if modal is active - if so, send keys to modal instead of page *)
        if Modal_manager.has_active () then begin
          Modal_manager.handle_key mouse_key ;
          let state' = Page.service_cycle state 0 in
          check_navigation (Packed ((module Page), state')) tick_start
        end
        else if Page.has_modal state then
          (* Page has its own modal - use page's modal key handler *)
          let state' = Page.handle_modal_key state mouse_key ~size in
          check_navigation (Packed ((module Page), state')) tick_start
        else
          let state' = Page.handle_key state mouse_key ~size in
          check_navigation (Packed ((module Page), state')) tick_start
  and check_navigation packed tick_start =
    let (Packed ((module Page), state)) = packed in
    let next = Page.next_page state in
    (* Debug: log navigation if MIAOU_DEBUG is set *)
    (if Sys.getenv_opt "MIAOU_DEBUG" = Some "1" then
       match next with
       | Some name ->
           let oc =
             open_out_gen [Open_append; Open_creat] 0o644 "/tmp/miaou-keys.log"
           in
           Printf.fprintf oc "Navigation requested: %S\n%!" name ;
           close_out oc
       | None -> ()) ;
    match next with
    | Some "__QUIT__" ->
        Matrix_render_loop.shutdown render_loop ;
        `Quit
    | Some name -> `SwitchTo name
    | None ->
        (* Maintain TPS by sleeping if we have time left *)
        let elapsed = Unix.gettimeofday () -. tick_start in
        let sleep_time = tick_time_s -. elapsed in
        if sleep_time > 0.001 then Thread.delay sleep_time ;
        loop (Packed ((module Page), state))
  in

  (* Start with initial page *)
  let (module P) = initial_page in
  let result = loop (Packed ((module P), P.init ())) in

  (* Cleanup *)
  Matrix_render_loop.shutdown render_loop ;
  Matrix_terminal.write terminal Matrix_ansi_writer.cursor_show ;
  Matrix_terminal.write terminal "\027[0m" ;
  Matrix_terminal.cleanup terminal ;

  result
