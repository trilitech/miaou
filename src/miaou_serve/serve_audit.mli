(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Structured session-lifecycle audit log (FR-080).

    Every session-lifecycle event this module knows about is emitted as
    exactly one line to stderr, carrying a timestamp, the event's name,
    and a session identifier derived by hashing (SHA-256, truncated —
    see {!hash_token}) whichever token identifies the session — never
    the raw token value itself, so a captured log line can never be
    replayed as a live credential (spec C-8). Every call site in this
    library passes the session's own {!Serve_session.controller_token_string}
    as the hashed identifier (even when the event was triggered by a
    request that presented the *viewer* token, e.g. a viewer attach) so
    every event for a given session hashes to the same value — a log
    reader can correlate a session's whole lifecycle (create, attach,
    detach, ..., session-end) by that one recurring hash, without ever
    seeing a live token.

    Note: {b viewer-input-rejection} audit logging (the tenth
    FR-080 event) does not go through this module. It fires inside the
    per-session *worker* process ({!Miaou_driver_web.Web_driver}), a
    different library that this one depends on (not the reverse — a
    dependency the other way would cycle) and which, by this
    architecture's own design (see {!Serve_proxy}'s PREREQ-B note), never
    receives the raw session token at all: the supervisor strips the
    [/s/<token>] path segment before forwarding any request to a
    worker. [Web_driver]'s own audit line uses the worker's OS process id
    (never a secret, and — in this process-per-session architecture —
    already a stable, unique per-session identifier). Note its grammar
    differs from this module's: it carries [ts=]/[session=pid-<n>] but the
    event is the literal substring [viewer-input-rejected] rather than an
    [event=<name>] field (preserved verbatim from before this slice for
    backward compatibility), so a scraper filtering on [event=] will not
    match it; see [web_driver.ml]'s [classify_and_audit_viewer_input]. *)

(** The session-lifecycle events this module can log. Named after the
    FR-080 vocabulary, with [Attach] split into a controller/viewer pair
    (matching the spec's "attach (controller/viewer)" phrasing) rather
    than carrying a role value, so this module never needs to depend on
    {!Serve_session}'s or {!Serve_token}'s role type (avoiding a library
    dependency cycle, since both of those modules call into this one). *)
type event =
  | Create  (** A session (its token pair) was created and registered. *)
  | Attach_controller
      (** A connection attached with controller role, spawning that
          session's worker for the first time (contrast {!Reconnect}). *)
  | Attach_viewer  (** A connection attached with viewer role (read-only). *)
  | Detach  (** A controller connection ended (FR-012 — the worker survives). *)
  | Reconnect
      (** A connection attached with controller role to a session whose
          worker was already running (FR-050). *)
  | Idle_kill
      (** FR-013: an idle session's worker was killed by the background
          idle-timeout reaper. *)
  | Explicit_kill
      (** FR-014 (or a graceful-shutdown drain, {!Serve_supervisor.run}):
          a session's worker was killed by an explicit (non-idle-driven)
          request. *)
  | Auth_fail
      (** FR-031/FR-032: a request's token did not resolve to any live
          session, or resolved but granted the wrong role for the path
          requested. *)
  | Origin_reject
      (** FR-045: a WebSocket upgrade's [Origin] header was not on the
          configured allow-list. *)
  | Session_end
      (** FR-050: the session's worker exited because the app itself
          reached a genuine terminal outcome (not a crash, not a kill) —
          {!Serve_session.reap_and_log}'s [quit_exit_code] case. The
          session is permanently dead afterward, same as {!Idle_kill}. *)

(** [hash_token token] is a 16-hex-character (64-bit) prefix of
    [token]'s SHA-256 digest. Long enough to distinguish sessions for
    operational log correlation; short enough not to read as a
    reproduction of the token's own length. Never reversible to [token]
    (SHA-256's preimage resistance holds regardless of truncation).
    Exposed so a test can compute the expected value independently of
    {!log}. *)
val hash_token : string -> string

(** [log event ~token] writes one line to stderr:
    [\[miaou serve audit\] ts=<unix-epoch-seconds> event=<name>
    session=<hash_token token>]. [token] itself is never printed — only
    {!hash_token}'s output is. Best-effort: a formatting failure here is
    caught and dropped rather than raised, since a logging call must
    never crash the process it is trying to log a security event about. *)
val log : event -> token:string -> unit
