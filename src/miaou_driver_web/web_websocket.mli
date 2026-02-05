(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Minimal WebSocket implementation for Eio.

    Implements RFC 6455 WebSocket protocol using direct flow writes
    (no Buf_write buffering). *)

(** A WebSocket connection. *)
type t

(** Parse HTTP headers from a buffered reader until a blank line.
    Returns a hashtable of lowercase header names to values. *)
val parse_headers : Eio.Buf_read.t -> (string, string) Hashtbl.t

(** Attempt a WebSocket upgrade given parsed HTTP headers.
    Sends the 101 Switching Protocols response via the [write] function.
    Returns [None] if the headers are not a valid upgrade request. *)
val upgrade : (string, string) Hashtbl.t -> write:(string -> unit) -> t option

(** Send a text frame. *)
val send_text : t -> string -> unit

(** Receive the next text message.
    Handles ping/pong automatically.
    Returns [None] on connection close. *)
val recv_text : t -> Eio.Buf_read.t -> string option

(** Send a close frame and shut down. *)
val close : t -> unit

(** Check whether the connection has been closed. *)
val is_closed : t -> bool
