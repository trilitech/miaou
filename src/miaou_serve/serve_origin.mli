(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** WebSocket upgrade Origin allow-list (FR-045).

    A browser cannot forge an arbitrary [Origin] header (unlike a custom
    header or query parameter), so validating it against a configured
    allow-list defends against a malicious page, running on a different
    origin, driving a WebSocket connection to a [miaou serve] session
    using a token it obtained some other way (e.g. phished separately) —
    see the spec's threat table entry for this FR. A raw-socket attacker
    who already possesses a valid token bypasses this check entirely
    (there is no browser [Origin] header to spoof or validate); that is
    an accepted limitation, since such an attacker is already
    authenticated by token possession — Origin is defense against
    browser-mediated hijack, not a substitute for the token.

    {2 Missing-[Origin] policy (documented; weakens the literal FR-045
    text on purpose)}

    A request that carries {i no} [Origin] header at all is ALLOWED,
    regardless of the configured allow-list. Browsers always send
    [Origin] on a WebSocket handshake (same-origin or cross-origin), so
    any browser attempt always carries the header and is always subject
    to the check above.
    Non-browser clients — [websocat], a CLI script, a reverse-proxy
    health check, `curl --include` — legitimately send no [Origin]
    header at all; refusing them by default would make the "Origin
    guards browser CSRF/hijack" mitigation also block the intended
    non-browser CLI/automation use of [miaou serve] (`miaou-serve-intake.md`'s
    own audience includes scripted access, not just a browser tab). Since
    [Origin] is not itself the authentication mechanism (the session
    token is, FR-030/031/032), allowing an absent [Origin] does not
    weaken authentication — it only narrows Origin's own guard to the
    browser-mediated case it was designed for. *)

(** [is_websocket_upgrade header_lines] is [true] iff [header_lines]
    (raw request header lines, as produced by
    {!Serve_proxy.read_header_lines} — one per line, a trailing ['\r']
    tolerated) contains an [Upgrade] header whose value is
    case-insensitively ["websocket"]. *)
val is_websocket_upgrade : string list -> bool

(** [header_value header_lines ~name] is the trimmed value of the first
    header in [header_lines] whose name matches [name]
    case-insensitively, or [None] if no such header is present. *)
val header_value : string list -> name:string -> string option

(** [default_allowed ~bind ~port] is the single-element allow-list
    derived from the server's own bind address and port (e.g.
    [["http://127.0.0.1:8080"]] for [~bind:"0.0.0.0" ~port:8080] —
    {!Serve_process.display_host} substitutes a client-reachable address
    for the all-interfaces bind form). This is the "same-origin-as-bind"
    default FR-045 calls for; an operator fronting [miaou serve] with a
    reverse proxy whose public origin differs (a different scheme/host/
    port than the bind address) must add it explicitly via
    [--allowed-origin] — see {!Serve_config.t}'s [allowed_origins]. *)
val default_allowed : bind:string -> port:int -> string list

(** [is_allowed ~allowed ~origin] is the FR-045 allow/refuse decision:
    [true] if [origin] is [None] (the documented missing-[Origin] policy
    above), or if [origin] is [Some o] and [o] case-insensitively equals
    some entry of [allowed]; [false] otherwise (a foreign [Origin], even
    with an otherwise-valid session token, must be refused — US-4
    scenario 4). Origin values are not secret, so this is a plain
    (non-constant-time) membership check — unlike {!Serve_token.matches},
    timing here carries no exploitable information. *)
val is_allowed : allowed:string list -> origin:string option -> bool
