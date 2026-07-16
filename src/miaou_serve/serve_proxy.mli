(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** The supervisor's byte proxy (Slice 2, generalized to a session table
    in Slice 3).

    The supervisor is the only network-facing process; each session's
    worker listens on a private Unix domain socket, spawned lazily on
    first controller-role attach (FR-010, {!Serve_session.ensure_worker}).
    This module reads just enough of an incoming HTTP request's head
    (request line + headers) to: validate the [/s/<token>] path segment
    against the session table in constant time
    ({!Serve_session.find}), identify which role the matched token
    grants (FR-032 — the role is never client-asserted), strip that
    segment before forwarding (so the token never reaches the worker —
    its own request-line [eprintf] cannot leak it), and connect to the
    right worker. On a controller-role request to the [/ws] endpoint
    while another controller connection is already live for that
    session, the request is transparently rewritten to [/ws/viewer]
    instead (FR-011 — the worker's own single-controller-slot 409 stays
    a backstop). After the (rewritten) head and any already-buffered
    residue are replayed to the worker, the connection becomes a raw
    bidirectional byte copy: WebSocket frames are never parsed here,
    only by the worker's own {!Miaou_driver_web.Web_websocket}
    (unmodified). *)

(** [handle_connection ~sw ~env ~sessions ~max_sessions ~allowed_origins
    ~conn] services one accepted client connection: parses the request
    head, resolves the [/s/<token>] prefix against [sessions]
    (constant-time per session, and never matching a session
    {!Serve_session.is_dead} — FR-013's dead-token-never-resurrects
    guarantee), and on a match:
    - a viewer-role token requesting the [/ws] controller endpoint is
      refused (403) without ever contacting a worker (FR-032);
    - a viewer-role token requesting anything else, for a session with
      no worker currently running ({!Serve_session.has_worker} is
      [false] — no controller has ever attached, or a previously-running
      worker crashed and has not yet been respawned by a controller), is
      refused (409, mirroring the worker's own "no controller connected
      yet" backstop response for the same precondition) — a viewer
      cannot bring a session's worker into existence;
    - a controller-role token that would cause a *new* worker spawn
      ({!Serve_session.would_spawn}) while [sessions] already has
      [max_sessions] spawned workers ({!Serve_session.count_spawned}) is
      refused (429 — FR-070), without contacting any worker; a
      controller reattaching to a session whose worker already exists is
      never refused by this cap;
    - otherwise, a controller-role token lazily spawns (or reuses) the
      session's worker ({!Serve_session.ensure_worker}) and, for the
      [/ws] endpoint specifically, is either forwarded unmodified
      (first/only live controller) or rewritten to [/ws/viewer] (a
      controller connection is already live — FR-011);
    - any other path (static assets, the viewer endpoint once a worker
      exists) is forwarded to the session's worker unmodified.

    Once resolved to a forward, but before ever connecting to the
    worker: if the request carries an [Upgrade: websocket] header, its
    [Origin] header is validated against [allowed_origins]
    ({!Serve_origin.is_allowed}, FR-045) — refused with [403] before any
    bytes are forwarded to the worker if present and not on the list (note:
    for a controller-role token the session's worker may already have been
    lazily spawned by [resolve], though it is never contacted); a request
    with no [Origin] header at all is allowed (see
    {!Serve_origin}'s documented policy). This runs even for an
    otherwise-valid session token (US-4 scenario 4: token possession
    alone must not bypass the Origin check).

    On a missing/invalid session prefix or token mismatch, responds with
    a bounded HTTP error and closes [conn] without ever contacting any
    worker. Connecting to a worker is retried with a short bounded
    backoff (the worker may still be starting up just after spawn); if
    all retries are exhausted, responds [502] and closes [conn].

    Never raises to the caller — internal errors are logged and the
    connection is closed. *)
val handle_connection :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  sessions:Serve_session.table ->
  max_sessions:int ->
  allowed_origins:string list ->
  conn:_ Eio.Net.stream_socket ->
  unit

(** Exposed for unit testing the pure path-splitting logic in isolation,
    without opening any sockets or consulting a session table.
    [split_session_path path] is [Some (candidate, tail)] when [path] has
    the [/s/<candidate>...] shape ([candidate] being the token-string
    segment, [tail] being the remainder — ["/s/<tok>"] -> [("<tok>",
    "/")], ["/s/<tok>/ws"] -> [("<tok>", "/ws")]); [None] if [path] does
    not start with [/s/]. *)
val split_session_path : string -> (string * string) option
