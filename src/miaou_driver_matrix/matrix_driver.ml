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
    [`Quit | `SwitchTo of string] =
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
      let input = Matrix_input.create terminal in

      (* Build I/O interface for the shared main loop *)
      let io : Matrix_io.t =
        {
          write = Matrix_terminal.write terminal;
          poll = (fun ~timeout_ms -> Matrix_input.poll input ~timeout_ms);
          drain_nav_keys = (fun ev -> Matrix_input.drain_nav_keys input ev);
          drain_esc_keys = (fun () -> Matrix_input.drain_esc_keys input);
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

      (* Hide cursor *)
      Matrix_terminal.write terminal Matrix_ansi_writer.cursor_hide ;

      (* Clear screen initially *)
      Matrix_terminal.write terminal "\027[2J\027[H" ;

      (* Start render domain - runs at 60 FPS in parallel *)
      Matrix_render_loop.start render_loop ;

      (* Build context for the shared main loop *)
      let ctx : Matrix_main_loop.context =
        {config; buffer; parser; render_loop; io}
      in

      (* Run the shared main loop *)
      let result = Matrix_main_loop.run ctx ~env initial_page in

      (* Cleanup *)
      Matrix_render_loop.shutdown render_loop ;
      Matrix_terminal.write terminal Matrix_ansi_writer.cursor_show ;
      Matrix_terminal.write terminal "\027[0m" ;
      (* Save screen content for debugging - will be printed after exit *)
      let screen_dump = Matrix_buffer.dump_to_string buffer in
      Matrix_terminal.set_exit_screen_dump terminal screen_dump ;
      Matrix_terminal.cleanup terminal ;

      result)
