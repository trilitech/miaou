(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Minimal WebSocket implementation for Eio.

    Implements RFC 6455 WebSocket protocol over Eio flows.
    Supports text frames, ping/pong, and close handshake. *)

(** A WebSocket connection. *)
type t

(** Parse HTTP headers from a buffered reader until a blank line.
    Returns a hashtable of lowercase header names to values. *)
val parse_headers : Eio.Buf_read.t -> (string, string) Hashtbl.t

(** Attempt a WebSocket upgrade given parsed HTTP headers.
    Sends the 101 Switching Protocols response if headers contain
    a valid WebSocket upgrade request.
    Returns [None] if the headers are not a valid upgrade request. *)
val upgrade : (string, string) Hashtbl.t -> Eio.Buf_write.t -> t option

(** Perform the server-side WebSocket handshake.
    Reads the HTTP upgrade request from the flow, validates it,
    and sends the 101 Switching Protocols response.
    Returns [None] if the request is not a valid WebSocket upgrade. *)
val server_handshake : Eio.Buf_read.t -> Eio.Buf_write.t -> t option

(** Send a text frame. *)
val send_text : t -> Eio.Buf_write.t -> string -> unit

(** Receive the next text message.
    Handles ping/pong automatically.
    Returns [None] on connection close. *)
val recv_text : t -> Eio.Buf_read.t -> Eio.Buf_write.t -> string option

(** Send a close frame and shut down. *)
val close : t -> Eio.Buf_write.t -> unit

(** Check whether the connection has been closed. *)
val is_closed : t -> bool
