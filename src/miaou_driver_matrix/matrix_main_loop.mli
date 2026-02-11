(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Shared main loop for the Matrix rendering engine.

    Contains the event loop, page rendering, modal handling, keymap dispatch,
    and navigation logic. Parameterized on I/O via {!Matrix_io.t} so it can
    be reused by different backends (terminal, WebSocket, etc.).

    The rendering pipeline (buffer, diff, ANSI writer) is shared across all
    backends. Only the I/O operations (write, input, size) differ.
*)

(** Context required to run the main loop. *)
type context = {
  config : Matrix_config.t;
  buffer : Matrix_buffer.t;
  parser : Matrix_ansi_parser.t;
  render_loop : Matrix_render_loop.t;
  io : Matrix_io.t;
}

(** Run the main loop for a page.

    Handles rendering, input, modal dispatch, and navigation.
    Returns when the page requests a quit or page switch.

    Must be called inside {!Miaou_helpers.Fiber_runtime.with_page_switch}. *)
val run :
  context ->
  env:Eio_unix.Stdenv.base ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  [`Quit | `Back | `SwitchTo of string]
