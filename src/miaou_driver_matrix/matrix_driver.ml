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

(* Run [f], always invoking [cleanup] afterwards — whether [f] returns
   normally or raises. Unlike [Fun.protect ~finally:cleanup f], a failure
   inside [cleanup] itself is swallowed rather than wrapped in
   [Finally_raised], and an exception from [f] is re-raised with its
   original backtrace preserved via [Printexc.raise_with_backtrace] instead
   of being masked. This is what lets a crashing page still leave the
   terminal in a restored, usable state (see slice S6 of the
   crash-ub-fixes plan): the caller's [cleanup] is expected to internally
   guard each of its own steps (see [run] below) so one failing step (e.g.
   a write to an already-closed fd) doesn't skip the rest. *)
let run_with_cleanup ~cleanup f =
  match f () with
  | result ->
      (try cleanup () with _ -> ()) ;
      result
  | exception exn ->
      let bt = Printexc.get_raw_backtrace () in
      (try cleanup () with _ -> ()) ;
      Printexc.raise_with_backtrace exn bt

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

      (* Configure inline vs alt-screen before entering raw mode *)
      Matrix_terminal.set_alt_screen terminal (not config.inline_mode) ;

      (* Enter raw mode and enable mouse (mouse off in inline mode) *)
      Matrix_terminal.enter_raw terminal ;
      if config.enable_mouse && not config.inline_mode then
        Matrix_terminal.enable_mouse terminal ;

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

      (* Clear screen initially. In inline mode we skip the clear and let
         the diff renderer paint over the current scrollback contents
         starting from the cursor position; the final frame stays in
         scrollback after exit. *)
      if not config.inline_mode then
        Matrix_terminal.write terminal "\027[2J\027[H" ;

      (* Start render domain - runs at 60 FPS in parallel *)
      Matrix_render_loop.start render_loop ;

      (* Start decoupled input reader fiber *)
      Matrix_input.start input ;

      (* Build context for the shared main loop *)
      let ctx : Matrix_main_loop.context =
        {config; buffer; parser; render_loop; io}
      in

      (* Cleanup steps, each individually guarded so a failure in one step
         (e.g. a write to a closed fd) does not prevent the rest of the
         terminal restoration from running. [Matrix_terminal.cleanup] is
         idempotent (guarded by [cleanup_done]), so it is safe to call it
         here even though [at_exit] above will also call it: on the normal
         (non-exceptional) path this call does the real work and the later
         [at_exit] invocation is a no-op; on the exceptional path (a page or
         the loop raising) it is the only place the terminal gets restored
         before the process unwinds to [at_exit] — otherwise a crashing page
         would leave the user's shell stuck in raw/alt-screen/mouse-tracking
         mode. See [run_with_cleanup] above for why this uses a manual
         try/with instead of [Fun.protect]. *)
      let safe_step f = try f () with _ -> () in
      let cleanup () =
        safe_step (fun () -> Matrix_input.stop input) ;
        safe_step (fun () -> Matrix_render_loop.shutdown render_loop) ;
        safe_step (fun () ->
            Matrix_terminal.write terminal Matrix_ansi_writer.cursor_show) ;
        safe_step (fun () -> Matrix_terminal.write terminal "\027[0m") ;
        safe_step (fun () ->
            (* Save screen content for debugging - will be printed after exit *)
            let screen_dump = Matrix_buffer.dump_to_string buffer in
            Matrix_terminal.set_exit_screen_dump terminal screen_dump) ;
        safe_step (fun () -> Matrix_terminal.cleanup terminal)
      in
      let result =
        run_with_cleanup ~cleanup (fun () ->
            Matrix_main_loop.run ctx ~env initial_page)
      in
      (* Preserve the conventional 130 exit code for a signal-triggered
         quit. The terminal is already fully restored by [cleanup] above at
         this point, so it is safe to exit immediately; this also sidesteps
         waiting on any fiber the signal's blocking wait left behind (e.g.
         the reader fiber, if it never separately woke up), matching the
         existing hard-exit pattern used elsewhere in the driver stack
         rather than requiring full graceful fiber cancellation. *)
      if Matrix_input.signaled input then exit 130 else result)
