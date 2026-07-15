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

    [Miaou_serve.run] is a {b top-level} entry point: it starts its own
    Eio event loop and calls {!Miaou_helpers.Fiber_runtime.init} itself.
    Callers must invoke it directly from their [main] — not from inside
    an existing [Eio_main.run]/[Fiber_runtime.init] scope (unlike
    {!Miaou_driver_web.Web_driver.run}, which assumes the caller already
    set those up, per [example/gallery/main_web.ml]).

    Once the process-per-session supervisor lands (Slice 2+), [run] will
    re-exec [Sys.executable_name] to become a worker when
    [MIAOU_SERVE_WORKER_SOCKET] is set in the environment. Everything a
    host app does in its own [main] {b before} calling [Miaou_serve.run]
    must therefore be deterministic and idempotent on re-exec (safe to
    run twice: once as supervisor, once as worker) — do not perform
    one-shot side effects (e.g. consuming a queue, prompting a user)
    ahead of this call.

    {2 Slice 1 scope}

    This slice proves the CLI/token/auth-default surface only: no
    process-per-session supervisor exists yet (that is Slice 2). [run]
    enforces the fail-closed bind policy (FR-003) and generates a
    controller-role {!Serve_token.t}, but still delegates directly,
    in-process, to {!Miaou_driver_web.Web_driver.run} using the
    existing query-string password mechanism as an interim bridge — the
    token is passed as [controller_password]. Two known gaps, both
    explicitly deferred to Slice 2's [Web_driver.run_on] seam, not
    silently accepted as final behavior:
    - The printed URL is query-string-based ([?password=<token>]), not
      the FR-030 path form ([/s/<token>]); real path-based routing
      requires the supervisor/proxy layer.
    - [Web_driver.run] always listens on all interfaces regardless of
      the [bind] value passed here (a pre-existing discrepancy this
      spec calls out); the fail-closed check below still holds
      (non-loopback without auth is refused before any socket opens),
      but a non-loopback [bind] with auth configured does not yet
      scope the listening address the way the string implies. The
      converse also holds and is the more surprising direction: passing
      [~bind:"127.0.0.1"] exempts the caller from the fail-closed check
      (loopback is treated as already-trusted), but the process still
      listens on all interfaces underneath — a [127.0.0.1] bind is
      {b not} loopback-restricted at runtime in Slice 1. Honoring
      [bind] for real is tracked as Slice 2's [Web_driver.run_on]
      seam's responsibility, not a separate follow-up. *)

(** Raised by {!run} when {!Serve_policy.check} refuses the requested
    bind (FR-003). The message is {!Serve_policy.refusal_message}'s
    output — documented and stable, not an internal exception dump. *)
exception Bind_refused of string

(** [auth_token] and [auth_file], when supplied, only satisfy the
    fail-closed bind policy's "an auth mechanism is configured" test
    (FR-003) in Slice 1 — neither is yet the credential a client
    presents, and [auth_file]'s contents are not read or validated at
    all in this slice (its mere presence as a path is what counts,
    same as [auth_token]'s mere presence — not its value). The actual
    per-session, CSPRNG-generated {!Serve_token.t} (FR-030) is what
    gates the WebSocket upgrade, printed as part of the session URL at
    startup. Wiring an operator-supplied [auth_token]/[auth_file] into
    that check, and reading [auth_file]'s contents, is Slice 5 scope
    (FR-031/FR-033's negative-auth suite). *)
val run :
  ?auth_token:string ->
  ?auth_file:string ->
  ?port:int ->
  ?bind:string ->
  ?max_sessions:int ->
  ?idle_timeout:float ->
  ?insecure_allow_plaintext_external:bool ->
  (module Miaou_core.Tui_page.PAGE_SIG) ->
  unit
