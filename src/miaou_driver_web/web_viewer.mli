(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Standalone viewer-only HTTP+WebSocket server.

    Runs alongside the headless driver so a human can open a browser and
    observe a TUI session driven by an AI agent in real time. *)

(** A running web viewer server. *)
type t

(** [start ~sw ~net ~port ()] starts the HTTP+WebSocket server on [port].
    The server runs as a fiber in [sw] and serves:
    - [/] and [/viewer] — the xterm.js viewer page
    - [/client.js] — the JavaScript client
    - [/ws/viewer] — WebSocket endpoint for viewer connections *)
val start :
  sw:Eio.Switch.t ->
  net:[> [> ] Eio.Net.ty] Eio.Resource.t ->
  port:int ->
  unit ->
  t

(** [broadcast t ~rows ~cols data] sends the raw ANSI frame [data] to all
    connected viewers.  The terminal dimensions [rows] x [cols] are tracked
    so that newly connecting viewers can resize their xterm.js terminal to
    match the headless driver.  If the dimensions change, a JSON
    ["dimensions"] message is sent before the ANSI frame. *)
val broadcast : t -> rows:int -> cols:int -> string -> unit

(** [url t] returns the viewer URL, e.g. ["http://127.0.0.1:8765/viewer"]. *)
val url : t -> string
