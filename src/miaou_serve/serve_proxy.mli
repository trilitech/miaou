(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** The supervisor's byte proxy (Slice 2).

    The supervisor is the only network-facing process; a worker listens
    on a private Unix domain socket. This module reads just enough of an
    incoming HTTP request's head (request line + headers) to: validate
    the [/s/<token>] path segment against the session's token in
    constant time, strip that segment before forwarding (so the token
    never reaches the worker — its own request-line [eprintf] cannot
    leak it), and connect to the worker. After the (rewritten) head and
    any already-buffered residue are replayed to the worker, the
    connection becomes a raw bidirectional byte copy: WebSocket frames
    are never parsed here, only by the worker's own
    {!Miaou_driver_web.Web_websocket} (unmodified). *)

(** [handle_connection ~sw ~env ~token ~worker_socket_path ~conn] services
    one accepted client connection: parses the request head, checks the
    [/s/<token>] prefix against [token] (via
    {!Miaou_serve.Serve_token.matches}, constant-time), and on success
    proxies bytes to/from the worker listening at [worker_socket_path].
    On a missing/invalid session prefix or token mismatch, responds with
    a bounded HTTP error and closes [conn] without ever contacting the
    worker. Connect to the worker is retried with a short bounded
    backoff (the worker may still be starting up just after spawn); if
    all retries are exhausted, responds [502] and closes [conn].

    Never raises to the caller — internal errors are logged and the
    connection is closed. *)
val handle_connection :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  token:Serve_token.t ->
  worker_socket_path:string ->
  conn:_ Eio.Net.stream_socket ->
  unit

(** Exposed for unit testing the path/token rewrite in isolation, without
    opening any sockets. [strip_session_prefix ~token path] is:
    - [Some tail] where [tail] is [path] with the leading
      [/s/<token-string>] segment removed (["/s/<tok>"] -> ["/"],
      ["/s/<tok>/ws"] -> ["/ws"]) when [path] starts with [/s/] and the
      segment's token-string component matches [token] per
      {!Serve_token.matches};
    - [None] if [path] does not have the [/s/...] shape, or the token
      segment does not match [token]. *)
val strip_session_prefix : token:Serve_token.t -> string -> string option
