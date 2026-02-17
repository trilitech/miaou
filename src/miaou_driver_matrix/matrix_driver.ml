(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Terminal backend for the Matrix driver.

    Handles terminal-specific lifecycle (setup, raw mode, signals, cleanup)
    and delegates the main loop to {!Matrix_main_loop}. *)

open Miaou_core

let available = true

module Fibers = Miaou_helpers.Fiber_runtime

let run ?(config = None) (initial_page : (module Tui_page.PAGE_SIG)) :
    [`Quit | `Back | `SwitchTo of string] =
  Fibers.with_page_switch (fun env _page_sw ->
      (* Load configuration *)
      let config =
        match config with Some c -> c | None -> Matrix_config.load ()
      in

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
      let input =
        Matrix_input.create ~handle_sigint:config.handle_sigint terminal
      in

      (* Build I/O interface for the shared main loop *)
      let io : Matrix_io.t =
        {
          write = Matrix_terminal.write terminal;
          drain = (fun () -> Matrix_input.drain input);
          size = (fun () -> Matrix_terminal.size terminal);
          invalidate_size_cache =
            (fun () -> Matrix_terminal.invalidate_size_cache terminal);
        }
      in

      (* Create render loop with terminal write function *)
      let render_loop =
        Matrix_render_loop.create
          ~config
          ~buffer
          ~writer
          ~write:(Matrix_terminal.write terminal)
      in

      (* Enter raw mode and enable mouse *)
      Matrix_terminal.enter_raw terminal ;
      if config.enable_mouse then Matrix_terminal.enable_mouse terminal ;

      (* Re-check size after raw mode; some terminals report 80x24 initially *)
      let sleep_s seconds = Eio.Time.sleep env#clock seconds in
      let rec read_size_retry attempts last =
        if attempts <= 0 then last
        else (
          Matrix_terminal.invalidate_size_cache terminal ;
          let s = Matrix_terminal.size terminal in
          if s <> last && s <> (24, 80) then s
          else (
            sleep_s 0.02 ;
            read_size_retry (attempts - 1) s))
      in
      let rows2, cols2 = read_size_retry 5 (rows, cols) in
      if rows2 <> rows || cols2 <> cols then
        Matrix_buffer.resize buffer ~rows:rows2 ~cols:cols2 ;

      (* Hide cursor *)
      Matrix_terminal.write terminal Matrix_ansi_writer.cursor_hide ;

      (* Clear screen initially *)
      Matrix_terminal.write terminal "\027[2J\027[H" ;

      (* Start render domain - runs at 60 FPS in parallel *)
      Matrix_render_loop.start render_loop ;

      (* Start decoupled input reader fiber *)
      Matrix_input.start input ;

      (* Build context for the shared main loop *)
      let ctx : Matrix_main_loop.context =
        {config; buffer; parser; render_loop; io}
      in

      (* Run the shared main loop *)
      let result = Matrix_main_loop.run ctx ~env initial_page in

      (* Cleanup *)
      Matrix_input.stop input ;
      Matrix_render_loop.shutdown render_loop ;
      Matrix_terminal.write terminal Matrix_ansi_writer.cursor_show ;
      Matrix_terminal.write terminal "\027[0m" ;
      (* Save screen content for debugging - will be printed after exit *)
      let screen_dump = Matrix_buffer.dump_to_string buffer in
      Matrix_terminal.set_exit_screen_dump terminal screen_dump ;
      Matrix_terminal.cleanup terminal ;

      result)
