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

(** Where to listen for incoming connections (Slice 2's worker seam,
    [miaou-serve-implementer.md]): either a TCP address (host + port) or a
    Unix domain socket path. [`Tcp (host, port)] honors [host] literally
    (e.g. ["127.0.0.1"] binds loopback-only, not all interfaces) — this
    is the fix for the pre-Slice-2 discrepancy where {!run} always bound
    {!Eio.Net.Ipaddr.V4.any} regardless of the address implied by its log
    line. [`Unix path] is used by a [miaou serve] worker process, which
    listens on a private Unix domain socket instead of a public TCP port
    (the supervisor is the only network-facing process). *)
type listen = [`Tcp of string * int | `Unix of string]

(** Run the web driver on an arbitrary listen target (Slice 2's worker
    seam). Identical behavior to {!run} otherwise — same routing,
    same [auth]/[controller_html]/[viewer_html]/[extra_assets] semantics
    — but the caller chooses exactly what to bind to instead of always
    getting a TCP listener on all interfaces.

    @param listen Where to accept connections: [`Tcp (host, port)] or
      [`Unix path]. *)
val run_on :
  ?config:Miaou_driver_matrix.Matrix_config.t option ->
  listen:listen ->
  ?auth:auth ->
  ?controller_html:string ->
  ?viewer_html:string ->
  ?extra_assets:extra_asset list ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  [`Quit | `Back | `SwitchTo of string]

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

    Implemented as a {!run_on} call with [~listen:(`Tcp ("0.0.0.0",
    port))] — i.e. binds all interfaces, matching this function's
    pre-Slice-2 behavior exactly (no break to existing callers such as
    [example/gallery/main_web.ml]).

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
  [`Quit | `Back | `SwitchTo of string]
