(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

[@@@warning "-32-34-37"]

open Miaou_core

let available = true

(* Pack page and state together to avoid GADT escaping issues *)
type packed_state =
  | Packed :
      (module Tui_page.PAGE_SIG with type state = 's) * 's
      -> packed_state

let run (initial_page : (module Tui_page.PAGE_SIG)) :
    [`Quit | `SwitchTo of string] =
  (* Load configuration *)
  let config = Matrix_config.load () in

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

  (* Main loop *)
  let rec loop packed =
    let (Packed ((module Page), state)) = packed in

    (* Get current terminal size *)
    let rows, cols = Matrix_terminal.size terminal in
    let size = {LTerm_geom.rows; cols} in

    (* Check if we need to resize buffer *)
    let buf_rows, buf_cols = Matrix_buffer.size buffer in
    if rows <> buf_rows || cols <> buf_cols then
      Matrix_buffer.mark_all_dirty buffer ;

    (* Render page view to ANSI string *)
    let view_output = Page.view state ~focus:true ~size in

    (* Render modal overlay if active *)
    let view_output =
      if Modal_manager.has_active () then
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

    (* Clear back buffer *)
    Matrix_buffer.clear_back buffer ;

    (* Parse ANSI output into buffer *)
    Matrix_ansi_parser.reset parser ;
    let _ =
      Matrix_ansi_parser.parse_into parser buffer ~row:0 ~col:0 view_output
    in

    (* Request frame render *)
    Matrix_render_loop.request_frame render_loop ;

    (* Render if needed (respects FPS cap) *)
    let _ = Matrix_render_loop.render_if_needed render_loop in

    (* Poll for input *)
    match Matrix_input.poll input ~timeout_ms:100 with
    | Matrix_input.Quit ->
        Matrix_render_loop.shutdown render_loop ;
        `Quit
    | Matrix_input.Resize ->
        Matrix_terminal.invalidate_size_cache terminal ;
        Matrix_buffer.mark_all_dirty buffer ;
        loop packed
    | Matrix_input.Refresh ->
        let state' = Page.service_cycle state 0 in
        check_navigation (Packed ((module Page), state'))
    | Matrix_input.Key key ->
        let _ = Matrix_input.drain_nav_keys input (Matrix_input.Key key) in
        (* Set modal size before handling keys *)
        Modal_manager.set_current_size rows cols ;
        (* Check if modal is active - if so, send keys to modal instead of page *)
        if Modal_manager.has_active () then begin
          Modal_manager.handle_key key ;
          (* After modal handles key, check if navigation requested *)
          let state' = Page.service_cycle state 0 in
          check_navigation (Packed ((module Page), state'))
        end
        else
          let state' = Page.handle_key state key ~size in
          check_navigation (Packed ((module Page), state'))
    | Matrix_input.Mouse (row, col) ->
        let mouse_key = Printf.sprintf "Mouse:%d:%d" row col in
        (* Set modal size before handling keys *)
        Modal_manager.set_current_size rows cols ;
        (* Check if modal is active - if so, send keys to modal instead of page *)
        if Modal_manager.has_active () then begin
          Modal_manager.handle_key mouse_key ;
          let state' = Page.service_cycle state 0 in
          check_navigation (Packed ((module Page), state'))
        end
        else
          let state' = Page.handle_key state mouse_key ~size in
          check_navigation (Packed ((module Page), state'))
  and check_navigation packed =
    let (Packed ((module Page), state)) = packed in
    match Page.next_page state with
    | Some "__QUIT__" ->
        Matrix_render_loop.shutdown render_loop ;
        `Quit
    | Some name -> `SwitchTo name
    | None -> loop (Packed ((module Page), state))
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
