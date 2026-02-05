(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Web backend for the Matrix driver.

    Starts an HTTP server that serves an xterm.js-based web terminal.
    When a browser connects via WebSocket, the shared Matrix main loop
    runs and sends ANSI diff frames to the browser for rendering.

    Uses the same rendering pipeline as the terminal Matrix driver:
    buffer, diff, ANSI writer. Only the I/O transport differs. *)

(** Whether this driver is available. Always [true] when compiled. *)
val available : bool

(** Run the web driver.

    Starts an HTTP server on [port] (default 8080) and waits for a
    browser to connect. The TUI runs over the WebSocket connection.

    @param config Optional Matrix configuration override.
    @param port TCP port to listen on (default 8080). *)
val run :
  ?config:Miaou_driver_matrix.Matrix_config.t option ->
  ?port:int ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  [`Quit | `SwitchTo of string]
