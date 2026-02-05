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

(** Authentication configuration for WebSocket connections.

    Each password is optional. When [None], no authentication is required
    for that role. When [Some pw], the client must supply [?password=pw]
    as a query parameter on the WebSocket URL. *)
type auth = {
  controller_password : string option;
  viewer_password : string option;
}

(** An extra static asset served by the web server.

    For example, a logo image:
    [{path = "/logo.png"; content_type = "image/png"; body = logo_data}] *)
type extra_asset = {path : string; content_type : string; body : string}

(** Run the web driver.

    Starts an HTTP server on [port] (default 8080) and waits for a
    browser to connect. The TUI runs over the WebSocket connection.

    URL routing:
    - [/]           — serves [controller_html] (default: built-in index.html)
    - [/viewer]     — serves [viewer_html] (default: built-in viewer.html)
    - [/client.js]  — serves the composable JS client
    - [/ws]         — controller WebSocket (409 if slot taken)
    - [/ws/viewer]  — viewer WebSocket (409 if no controller)
    - [/*]          — looked up in [extra_assets], else 404

    @param config Optional Matrix configuration override.
    @param port TCP port to listen on (default 8080).
    @param auth Optional authentication config (default: no auth).
    @param controller_html Custom HTML for the controller page.
    @param viewer_html Custom HTML for the viewer page.
    @param extra_assets Additional static assets to serve. *)
val run :
  ?config:Miaou_driver_matrix.Matrix_config.t option ->
  ?port:int ->
  ?auth:auth ->
  ?controller_html:string ->
  ?viewer_html:string ->
  ?extra_assets:extra_asset list ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  [`Quit | `SwitchTo of string]
