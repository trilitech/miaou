(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** Library entry point for serving a MIAOU app over the network
    (FR-002), mirroring {!Miaou_driver_web.Web_driver.run}'s shape but
    session-aware. Re-exported as {!Miaou_serve.run} — this module holds
    the implementation so {!Serve_cli} (a sibling module) can depend on
    it without violating dune's library-wrapping rule that the module
    named identically to the library must sit at the top of the
    dependency order.

    {2 Entry contract (binding, do not violate silently)}

    [Miaou_serve.run] is a {b top-level} entry point and a
    {b re-exec dispatch point}: it checks
    [Sys.getenv_opt "MIAOU_SERVE_WORKER_SOCKET"] {b before} starting any
    Eio event loop (before [Eio_main.run], before
    {!Miaou_helpers.Fiber_runtime.init}) and takes one of two disjoint
    paths:
    - {b Set} (this process is a worker, re-exec'd by a supervisor):
      dispatches to {!Serve_worker.run}, which starts its own
      [Eio_main.run]/[Fiber_runtime.init] and serves [initial_page] on
      the given Unix domain socket via
      {!Miaou_driver_web.Web_driver.run_on}. Full
      [Fiber_runtime]/[Registry]/[Modal_manager] — untouched, exactly as
      a directly-run app would use them.
    - {b Unset} (this is the first invocation): dispatches to
      {!Serve_supervisor.run}, a plain-Eio process that never touches
      [Fiber_runtime]/[Registry]/[Modal_manager] and never spawns a
      [Domain]. It creates a private Unix-socket directory, re-execs
      [Sys.executable_name] with [Sys.argv] unchanged plus
      [MIAOU_SERVE_WORKER_SOCKET] set (via [Eio.Process.spawn] — never a
      bare [Unix.fork], which would fork the whole multi-domain
      runtime), waits for the worker to become reachable, and proxies
      raw bytes between the public listener and the worker's socket
      ({!Serve_proxy.handle_connection}) after validating the
      [/s/<token>] path segment.

    Because the same host [main] runs twice (once per role, via
    re-exec), everything a host app does in its own [main] {b before}
    calling [Miaou_serve.run] — including how it builds the
    [initial_page] argument itself — must be deterministic and
    idempotent on re-exec (safe to run twice, in a fresh process each
    time, with the same [Sys.argv]): no one-shot side effects (consuming
    a queue, prompting a user, reading and deleting a file) ahead of
    this call. Callers must invoke [Miaou_serve.run] directly from their
    [main] — not from inside an existing
    [Eio_main.run]/[Fiber_runtime.init] scope (unlike
    {!Miaou_driver_web.Web_driver.run}, which assumes the caller already
    set those up, per [example/gallery/main_web.ml]) — since which of
    the two paths above runs its own event loop is decided only once
    [Miaou_serve.run] itself is entered.

    {2 Slice 2 scope}

    Single-session only: the supervisor spawns exactly one worker per
    invocation (a session table keyed by multiple tokens is Slice 3).
    [max_sessions]/[idle_timeout] are accepted and recorded but not
    enforced (Slice 4). The printed session URL is now the FR-030 path
    form ([http://<bind>:<port>/s/<token>/]), superseding Slice 1's
    interim query-string bridge.

    {2 Auth model (Slice 5 decision, final)}

    [auth_token]/[auth_file] are, and remain, {b bind-policy gates only}:
    their sole effect is satisfying {!Serve_policy.check}'s "an auth
    mechanism is configured" precondition for binding a non-loopback
    address (FR-003). They are never read as request-time credentials —
    [auth_file]'s contents are not even read from disk. The per-request
    authentication FR-031/FR-032/FR-033 describe is entirely the
    per-session {!Serve_token.t} embedded in the [/s/<token>] URL:
    CSPRNG-generated at session creation (FR-030), role-bound at
    issuance (FR-032), compared in constant time (FR-033,
    {!Serve_token.matches}), and checked before any session-existence
    information is revealed or any WebSocket upgrade completes
    (FR-031, {!Serve_session.find}/{!Serve_proxy.handle_connection}).
    This is a deliberate architectural choice, not a gap: the
    process-per-session design's unguessable session URL is already a
    capability token strictly stronger (256 bits of fresh CSPRNG
    entropy, one pair per session) than a single operator-wide shared
    secret would be: layering a second, operator-supplied secret on top
    would need every client (including a plain browser tab following a
    printed link) to also transmit it on each request — WebSocket
    upgrades cannot carry arbitrary custom headers from a browser, so
    that would mean either a query parameter (worse: logged in
    proxies/history, another value to shepherd) or a fragile
    subprotocol/cookie bridge, for no additional security the session
    token doesn't already provide. Requiring [--auth-token]/[--auth-file]
    before a non-loopback bind stays valuable as a distinct, orthogonal
    policy: it forces an operator to make an explicit, auditable choice
    before exposing the listener beyond loopback (or to pass
    [--insecure-allow-plaintext-external] and own that choice knowingly)
    — independent of, and not a substitute for, the per-session token
    check that gates every individual request. *)

(** Raised by {!run} (via {!Serve_supervisor.run}) when
    {!Serve_policy.check} refuses the requested bind (FR-003). The
    message is {!Serve_policy.refusal_message}'s output — documented and
    stable, not an internal exception dump. The [.ml] defines this via
    [exception Bind_refused = Serve_supervisor.Bind_refused] — the
    identical exception, not a fresh one, so existing callers matching
    [Miaou_serve.Bind_refused] are unaffected by the fail-closed check
    having moved to {!Serve_supervisor}. (The rebind syntax is only valid
    in a structure, not a signature, so this signature just re-declares
    the same shape.) *)
exception Bind_refused of string

(** [auth_token] and [auth_file], when supplied, only satisfy the
    fail-closed bind policy's "an auth mechanism is configured" test
    (FR-003) — neither is a credential a client ever presents, and
    [auth_file]'s contents are not read or validated at all (its mere
    presence as a path is what counts, same as [auth_token]'s mere
    presence — not its value); see the auth model note above for why
    this is the final decision, not a deferred gap. The actual
    per-session, CSPRNG-generated {!Serve_token.t} (FR-030) is what
    gates the WebSocket upgrade, printed as part of the session URL at
    startup. [allowed_origins] adds extra [Origin] values accepted at
    upgrade (FR-045), beyond {!Serve_origin.default_allowed}'s
    same-origin-as-[bind] default — for a reverse proxy whose public
    origin differs from [bind]. *)
val run :
  ?auth_token:string ->
  ?auth_file:string ->
  ?port:int ->
  ?bind:string ->
  ?max_sessions:int ->
  ?idle_timeout:float ->
  ?insecure_allow_plaintext_external:bool ->
  ?allowed_origins:string list ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  unit
