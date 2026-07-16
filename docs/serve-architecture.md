# `miaou serve` architecture notes

Slice 2 of the `miaou-serve` build (process-per-session supervisor +
worker + byte proxy). This document covers two things:

1. A short summary of the Slice 2 shape actually implemented.
2. The **reconnect design spike** required before Slice 6 (reconnect +
   resync) is attempted: does the worker's current `run_tui` structure
   support "park on client-close, resume on reattach" instead of today's
   "client-close means the whole TUI session is done"? This section
   names the exact `web_driver.ml` change points and gives a feasibility
   verdict, per the Slice 2 brief's instruction to stop and report a
   design finding rather than silently deferring the question.

## 1. Slice 2 shape

- `Miaou_serve.run` (`src/miaou_serve/serve_run.ml`) is a dispatcher that
  checks `Sys.getenv_opt "MIAOU_SERVE_WORKER_SOCKET"` **before** starting
  any Eio event loop:
  - set → `Serve_worker.run` (worker path): starts its own
    `Eio_main.run`/`Fiber_runtime.init`, then serves the app on a private
    Unix domain socket via `Web_driver.run_on ~listen:(`Unix path)`.
  - unset → `Serve_supervisor.run` (supervisor path): a plain-Eio process
    (no `Fiber_runtime`/`Registry`/`Modal_manager`, no `Domain.spawn`)
    that creates `$XDG_RUNTIME_DIR/miaou-serve-<pid>/` (mode `0700`),
    re-execs `Sys.executable_name` via `Eio.Process.spawn` (never a bare
    `fork`) with a fresh env carrying `MIAOU_SERVE_WORKER_SOCKET`, waits
    for the worker to become reachable (bounded connect-retry), prints
    the `/s/<token>/` session URL, and proxies bytes
    (`Serve_proxy.handle_connection`) between the public TCP listener and
    the worker's socket.
- `Web_driver.run_on` (`src/miaou_driver_web/web_driver.ml`) generalizes
  the pre-Slice-2 `run` to accept `listen:[`Tcp of string * int | `Unix
  of string]`; `run` is now a `` `Tcp ("0.0.0.0", port) `` wrapper,
  preserving its exact pre-Slice-2 behavior for existing callers
  (`example/gallery/main_web.ml` via `Runner_web`). The `` `Tcp ``
  variant honors its host string literally (via
  `Eio_unix.Net.Ipaddr.of_unix (Unix.inet_addr_of_string host)`), fixing
  the discrepancy where the old code always bound
  `Eio.Net.Ipaddr.V4.any` regardless of what its log line implied.
- `Serve_proxy.handle_connection` reads only the request head (request
  line + headers via `Eio.Buf_read`), validates the `/s/<token>` prefix
  in constant time (`Serve_token.matches`, backed by `Eqaf.equal`),
  strips the token before forwarding (so the worker's own
  `[web] GET ...` `eprintf` never sees it), replays any already-buffered
  residue (`Eio.Buf_read.peek`/`consume`), and then falls through to raw
  `Eio.Flow.copy` in both directions — no WebSocket frame is ever parsed
  outside the worker's own `Web_websocket`.
- The stdin-pipe orphan guard: the supervisor holds the write end of a
  pipe (via `Eio.Process.pipe`) open for as long as its switch lives; the
  worker's read end is its stdin, watched by
  `Serve_worker.watch_stdin_orphan_guard`, which exits the worker process
  on EOF (supervisor gone).

Single-session only (Slice 2 scope) — one worker per supervisor
invocation. The session table generalizing this to N concurrent
tokens/workers is Slice 3.

## 2. Reconnect design spike (required before Slice 6)

### The question

Slice 6's "reconnect + resync" (spec FR-050/FR-051) requires the worker
to distinguish "the browser tab closed/reloaded, might come back" from
"the app itself said `` `Quit ``" — and, in the reconnect case, to **park**
(keep the render domain and `Matrix_main_loop` state alive, discard
output) rather than tearing the session down, then **resume** on a new
WebSocket attaching to the same worker.

### What happens today (the blocking coupling)

`run_tui` (`src/miaou_driver_web/web_driver.ml:205-358`) has three pieces
tightly coupled to a *specific* `ws`/`br` pair for the *entire* lifetime
of one `Matrix_main_loop.run` call:

1. **The reader fiber** (`web_driver.ml:276-294`) closes over the `ws`
   parameter directly. On `Web_websocket.recv_text ws br` returning
   `None` (client closed the socket), it does exactly one thing:
   `Eio.Stream.add events Matrix_io.Quit` (`web_driver.ml:283`). This is
   the actual site of the problem the spec calls out: "WS close no
   longer injects `Matrix_io.Quit`" (binding design, §Reconnect) — today
   it is the *only* thing a close does.
2. **The flusher fiber and `io.write`** (`web_driver.ml:229`,
   `Output_buffer.write output`, drained via `Web_websocket.send_text ws`
   at `web_driver.ml:241`) write to the *same* captured `ws`. There is no
   indirection: `ws` is a closed-over value, not a mutable "current
   transport" cell.
3. **`Matrix_main_loop.run ctx ~env initial_page`**
   (`web_driver.ml:347`) is a single **blocking call** that owns the
   entire page's lifetime (including page-switch via `` `SwitchTo ``,
   handled by the *caller* of `run_tui`, `web_driver.ml:444-472`, which
   itself loops calling `run_tui` again per page). It only returns when
   the app produces a terminal result (`` `Quit `` / `` `Back `` /
   `` `SwitchTo ``) — there is no "suspend and give control back to the
   caller for a while, then resume the same call" primitive in
   `Matrix_main_loop` today (out of this repo's `miaou_driver_web`
   package, not inspected further here, but `run_tui`'s call site treats
   it as synchronous-to-completion).

Consequence: today, "the WS closed" and "the app is done with this page"
are *the same event* from `run_tui`'s point of view, because the reader
fiber's only vocabulary for "closed" is injecting `Matrix_io.Quit`, which
`Matrix_main_loop.run` necessarily interprets as "the app should
terminate" (that's the only meaning `Quit` has). There is no distinct
"parked, waiting for a new attachment" state anywhere in this call chain.

### What would have to change

This is a **moderate, well-scoped rework**, not a "bigger rework that
blocks Slice 6 entirely" — the three coupling points above are exactly
the change points, and none of them requires touching
`Matrix_main_loop`'s own internals (it can keep being "call it and block
until a terminal result," since parking happens *around* it, not inside
it, by never injecting `Quit` in the first place):

1. **Introduce a mutable "current transport" cell** (e.g.
   `Web_transport.t ref`, holding `Web_websocket.t option` or similar)
   that the reader fiber, flusher fiber, and `io.write` read through
   instead of closing over `ws` directly. `Session.broadcast`
   (`web_driver.ml:66-77`) already demonstrates this pattern for viewers
   (a mutable list of `Web_websocket.t`, filtered as connections close)
   — the controller side needs the equivalent for exactly *one* slot
   that can be swapped, not just removed.
2. **Change the reader fiber's close handling**
   (`web_driver.ml:279-294`): instead of unconditionally injecting
   `Matrix_io.Quit`, it should signal "parked" — e.g. clear the current
   transport cell and *not* push any event into `events` at all. The
   flusher fiber (`web_driver.ml:296-307`) must tolerate "no transport
   attached" by buffering (or simply continuing to drain into
   `Output_buffer`, which already exists precisely because output is
   decoupled from immediate delivery — `web_driver.ml:22-48`) rather than
   erroring when `Web_websocket.send_text` has nothing to send to.
3. **A reattach path**: the controller's accept-loop branch
   (`web_driver.ml:406-483`, specifically the `` `ws` `` case) needs a
   second mode — "attach to an existing parked session" — that swaps a
   new `ws`/`br` into the transport cell, sends the FR-050 full redraw
   (`\027[2J\027[H`, already precedented at `web_driver.ml:341-343` for
   *page switch*, so the sequence to send is not new, just the
   trigger for sending it is), and restarts the reader/flusher fibers
   against the new transport — all while `Matrix_main_loop.run`
   (`web_driver.ml:347`) is still blocked inside its original call,
   never having seen a `Quit`.
4. **Session-level bookkeeping to find "this token's parked worker
   again"** is not a `web_driver.ml` change at all — that is Slice 3's
   session table (mapping token → worker) plus Slice 6 adding a "is this
   worker parked or does it need a fresh spawn" bit to each entry.

### Verdict

**Feasible without a bigger rework.** The required change is localized to
`run_tui`'s three coupling points (reader fiber's close handling, an
indirection layer for the transport the flusher/`io.write` target, and a
reattach branch in the accept loop) plus a same-worker-reconnect lookup
in Slice 3's session table. `Matrix_main_loop`'s blocking
call-until-terminal-result shape does not need to change — parking means
*never sending it a `Quit`*, not interrupting it mid-flight. This is
scoped as Slice 6 work, not attempted here (Slice 2 is
supervisor/worker/proxy only) — this section exists so Slice 6 does not
have to re-derive the change points from scratch.

## 3. Slice 4 — idle timeout + resource limits

### Idle timeout (FR-013)

A session becomes idle when it has a spawned worker but no controller
currently attached (`Serve_session.controller_live = false`) for longer
than `--idle-timeout` seconds since the last detach
(`Serve_session.last_activity`, stamped by `controller_detach ~now`).
The supervisor's `run` forks a background fiber that calls
`Serve_session.reap_idle_sessions` every `idle_scan_interval_seconds`
(fixed at 5s, independent of the configured `idle_timeout` — the scan
itself is a cheap linear pass bounded by `max_sessions`, so scanning far
more often than a typically minutes-scale timeout costs little and keeps
reap latency low).

Reaping a session (`Serve_session.kill_worker_escalating`):

1. Marks the session permanently dead (`t.dead <- true`) *before*
   sending any signal — the supervisor is single-domain (documented
   invariant, no `Domain.spawn`), so there is no intervening yield a
   concurrent attach could land inside between this and the next step.
2. Sends the worker `SIGTERM`.
3. Forks a fiber that sleeps `idle_kill_grace_seconds` (5s) on the
   caller's clock, then sends `SIGKILL` only if the worker has not
   already exited (the ordinary case, since a worker's default `SIGTERM`
   disposition terminates it well within the grace window — the
   escalation exists only for a worker that is somehow ignoring or slow
   to react to `SIGTERM`).

`Serve_session.find` — the single chokepoint every attach request passes
through — refuses any session with `dead = true`, even though the token
byte strings are unchanged in memory: **a dead token never resurrects**
(US-4 scenario 2), independent of whatever `worker_state` transition
happens afterward (a crash-recovery reap that is *not* an idle-timeout
kill still self-heals via `ensure_worker`, by design — only
`kill_worker_escalating`'s explicit `dead <- true` is permanent).

The clock is fully injectable end to end: `reap_idle_sessions` takes
both `now` (a plain float, so a test can assert idleness with a
contrived timestamp with zero waiting) and `clock` (an `Eio.Time.clock`,
so the grace-period wait can be driven by a mock clock stepped directly
in a test, never a real sleep). Production wires both to
`env#clock`/`Eio.Time.now env#clock`.

### `max_sessions` (FR-070/FR-071)

The cap is enforced where a **new** worker process would actually be
spawned (`Serve_proxy.resolve`'s controller branch, gated on
`Serve_session.would_spawn`), not on the session table's size in the
abstract: a controller reattaching to a session whose worker already
exists (or is mid-spawn) costs no new resource and is never itself
refused by the cap — only a request that would grow
`Serve_session.count_spawned` beyond `max_sessions` gets the uniform,
bounded `429 Too Many Sessions` response, before any worker is ever
contacted. This keeps the "existing sessions unaffected" half of
FR-070's own check true by construction rather than by extra
bookkeeping.

**Default derivation (FR-071)**: a worker's baseline RSS was measured
directly (spawning a worker process and reading its `VmRSS` from
`/proc/<pid>/status` shortly after startup, no client attached) at
**~9.3MB** for this repository's test-harness binary (which carries
coverage/test-framework instrumentation overhead beyond a lean
production binary) — consistent with, and slightly above, a prior
~6MB figure for an uninstrumented build, both in the same low-tens-of-MB
range the spec anticipated (§2, "expected low tens of MB per worker").
Assuming a conservative 320MB memory budget an operator can spare for
`miaou serve` sessions on a modest host, and a 20MB per-worker headroom
figure (roughly 2x the measured RSS, absorbing OS/runtime bookkeeping
beyond live heap data): `320 / 20 = 16`. This is `Serve_config.default`'s
existing `max_sessions = 16` value — carried forward from its earlier
placeholder, now grounded in a real measurement rather than a guess, per
FR-071's own requirement not to ship an invented number. Adjustable via
`--max-sessions` for a host with a different memory budget.

### Per-worker resource limits (FR-072)

Each worker self-applies a resource limit from `MIAOU_SERVE_RLIMIT_AS_MB`
/ `MIAOU_SERVE_RLIMIT_CPU_SECONDS` environment variables at worker-mode
entry (`Serve_worker.run`'s first line, before the Eio event loop even
starts).

**Why this isn't a `Unix.setrlimit` call**: OCaml's stdlib `Unix` module
has no `setrlimit` binding at all (confirmed against this project's
pinned compiler). Rather than add a new opam dependency (e.g.
`extunix`, not otherwise used anywhere in this codebase) or a
from-scratch C stub library for one defense-in-depth knob — either a
disproportionate amount of new build surface for this — `Serve_rlimit`
shells out to the `prlimit(1)` command-line utility against the
worker's own pid (`prlimit --pid <self> --as=N:N` / `--cpu=N:N`), which
adjusts a *running* process's own limit in place: functionally identical
to a self-`setrlimit` call, no re-exec, no new file descriptors, no new
opam/build dependency. If the utility is missing or the call otherwise
fails, this is logged to stderr and the worker proceeds unlimited — a
missing defense-in-depth backstop must never itself become a
denial-of-service for a legitimate session (the documented
platform-support caveat FR-072's own check anticipates).

**The RLIMIT_AS-vs-OCaml-heap caveat, confirmed empirically while
writing this slice's test**: setting `MIAOU_SERVE_RLIMIT_AS_MB` too low
does not gracefully degrade the worker's memory usage — it prevents the
worker from starting at all. At 256MB, the worker reliably aborted
during Eio's own runtime initialization (`io_uring_queue_init: ENOMEM`,
i.e. before the app or the OCaml heap had done anything); 384MB+ started
reliably in this environment. `test_serve_limits.ml`'s rlimit scenario
uses 512MB, a safe margin above that observed floor, specifically so the
limit is genuinely exercised (verified via `/proc/<pid>/limits`) without
being a no-op. Operators should set this value well above a worker's
expected resident set, not merely at it — RLIMIT_AS bounds total
*virtual* address space (including the runtime's own bulk, ahead-of-use
reservations), not live heap data. `MIAOU_SERVE_RLIMIT_CPU_SECONDS` has
no equivalent interaction and is the safer knob alone if this caveat is
a concern for a given deployment.

### A pre-existing, out-of-scope finding surfaced while manually
verifying this slice

Driving a real `miaou serve` worker with `curl` (WebSocket upgrade,
then an abrupt client-side disconnect — not a clean WebSocket close
frame) reproducibly logged `worker pid=<n> exited: signaled -11`
(SIGSEGV) instead of a clean exit, on both attempts tried. This
reproduces with Slice 2/3 code alone (the crash happens inside
`Web_driver`'s own controller-disconnect teardown path, well before any
Slice 4 code runs) and is already handled correctly by the existing
FR-015 reaper (no zombie, no hang) regardless of the crash — Slice 4's
own idle-timeout/`max_sessions`/dead-token guarantees were all still
verified to hold. This is flagged here as a finding for a future slice
to investigate (not fixed in this slice — out of the FR-013/070/072
scope), not silently absorbed.

## 4. Slice 5 — Origin checks, auth-negative suite, constant-time compare

### Uniform failure shape (FR-031)

Three distinct failure classes — a well-formed but nonexistent token, a
valid token presented for the wrong role (a viewer-scoped token hitting
the controller-only `/ws` path), and a token whose session has since been
killed by the idle-timeout reaper (FR-013's "dead token never
resurrects") — already collapsed onto the same code path as of Slice 3/4:
`Serve_session.find` excludes dead sessions from ever matching, and a
viewer token on the controller path is refused (`` `Refuse_403 ``) before
any worker is contacted, both funneling into `Serve_proxy.respond_403`,
which always emits the identical, input-independent
`403 Forbidden`/`Forbidden` bytes. `test_serve_auth_negative.ml` asserts
this with an explicit byte-for-byte comparison across five scenarios
(wrong token, no token, viewer-on-controller, dead token, and a
single-bit "near miss" against another session's real token — the
"almost matched" oracle the spec's US-4 scenario 1 and C-7 caveat call
out by name).

What Slice 5 actually changed: `Serve_session.find` was scanning the
session table with `List.find_map`, which short-circuits on the first
match — a session near the front of the table would cost strictly less
work (and, in principle, less wall-clock time) to match than one near
the back, or than a total miss. This is now a `List.fold_left` that
always visits every session regardless of an earlier hit. Similarly,
`Serve_session.match_role` was an `if ... else if ...` that only
evaluated the viewer token's `Eqaf.equal` call when the controller
token's call had already failed; both calls are now always evaluated.
Neither change affects observable behavior (the *first* match still
wins, `find`'s public contract is unchanged) — both are pure timing-
uniformity hardening, in the spirit of FR-031's "no oracle" mandate,
scoped to the table/per-session comparison structure the C-7 caveat
already flags as inherently unable to reach true constant-time over a
real network stack.

### Origin allow-list (FR-045)

A new `Serve_origin` module validates the `Origin` header against a
configured allow-list on any request that carries an
`Upgrade: websocket` header, wired into `Serve_proxy.handle_connection`
after the request head is read but before a worker is ever contacted —
so a foreign `Origin` is refused (`403`) even for an otherwise-valid,
correctly-scoped session token (US-4 scenario 4). The allow-list is the
same-origin-as-`--bind`-host default (`Serve_origin.default_allowed`,
derived from the actual bind address/port at supervisor startup) unioned
with any operator-supplied `--allowed-origin` values (repeatable) — a
reverse-proxy operator adding their public origin does not lose the
ability to reach the server at its own bind address directly.

**Missing-`Origin` policy (documented, deliberately weakens the literal
FR-045 text)**: a request with *no* `Origin` header at all is allowed,
regardless of the allow-list. A browser always sends `Origin` on a
WebSocket handshake, so any browser-mediated attempt is always subject
to the check above; only non-browser clients (`websocat`, a CLI script,
a health check) legitimately omit it, and `miaou serve`'s own intake
explicitly includes scripted/CLI access as a supported use case, not
just a browser tab. Origin is not itself an authentication mechanism —
the session token is (FR-030/031/032) — so allowing an absent header
does not weaken authentication; it only narrows Origin's own guard to
the browser-mediated hijack scenario it exists to defend against. See
`src/miaou_serve/serve_origin.mli` for the full rationale.

`test_serve_origin_check.ml` drives all three named scenarios (foreign
Origin refused, missing Origin allowed, an explicitly-allowed Origin
succeeds) plus a fourth proving the bind-derived default itself works,
over a real WebSocket handshake against `Serve_supervisor.accept_loop`.

### Auth model reconciliation (FR-033, and the S1 "auth gates bind
policy only" gap)

Slices 1-4 left `--auth-token`/`--auth-file` wired only into
`Serve_policy.check`'s fail-closed bind gate (FR-003) — never read as a
per-request credential — with an explicit comment marking that decision
as provisional pending Slice 5. That decision is now made final, not
deferred further: **`--auth-token`/`--auth-file` remain bind-policy-only.
The per-session `Serve_token.t` embedded in the `/s/<token>` URL is the
entire per-request authentication mechanism FR-031/032/033 describe.**

Rationale: the process-per-session design's session URL is already a
256-bit CSPRNG capability token, freshly minted per session and bound to
a role at issuance — strictly stronger than a single operator-wide
shared secret would add on top. Layering a second, operator-supplied
secret into the per-request check would require every client (including
a plain browser tab following the printed link) to also transmit it on
every request; a browser's WebSocket handshake cannot carry arbitrary
custom headers, so the only vehicles would be a query parameter (worse:
logged in proxies/browser history, one more secret to shepherd) or a
fragile cookie/subprotocol bridge — for no additional security the
session token doesn't already provide. `--auth-token`/`--auth-file`
retain their own, orthogonal value as a bind-policy gate: they force an
operator to make an explicit, auditable choice before exposing the
listener beyond loopback (or to pass
`--insecure-allow-plaintext-external` and knowingly own that choice) —
independent of, not a substitute for, the per-request session-token
check. See `src/miaou_serve/serve_run.mli`'s entry-contract doc comment
for the same decision spelled out at the API-documentation layer.

## 5. Slice 6 — reconnect + resync (FR-050), and the two deferred prereqs

### PREREQ-A: the S4 "SIGSEGV" finding was a misdiagnosis, not a crash

The S4/S6-prereq brief reported a client-triggerable worker crash:
`worker pid=<n> exited: signaled -11`, read as SIGSEGV (raw OS signal
11). Direct reproduction against a real worker process — abrupt
disconnects (`Unix.shutdown` + close, no WebSocket close frame, no
clean FIN) before any input, mid-stream while frames are actively
flushing, and repeated across many trials on this environment's actual
Eio/io_uring backend — never crashed the worker, in any trial. The
"-11" itself explains why: OCaml's `Sys` module encodes signals with its
own *portable* negative constants, not raw OS signal numbers —
`Sys.sigterm = -11`, `Sys.sigsegv = -10` (confirmed directly: `Sys.sigsegv
= -10; Sys.sigterm = -11` on this project's pinned compiler).
`Unix.waitpid`'s `WSIGNALED` — which `Eio.Process.exit_status`'s
`` `Signaled `` wraps, and which `Serve_process.string_of_exit_status`
prints verbatim — reports in this same portable encoding. "signaled -11"
is an ordinary SIGTERM, not a segfault. The likely original sequence:
stopping the foreground supervisor (Ctrl-C) right after a manual `curl`
repro triggers the supervisor's own graceful-shutdown path, which SIGTERMs
its worker(s); a worker installs no SIGTERM handler of its own, so the OS
default disposition (process termination) applies, and the resulting
`` `Signaled (-11) `` (portable SIGTERM) is what got logged and misread as
a crash. Separately, Eio itself already globally disables `SIGPIPE`
(`eio_linux.ml`/`eio_posix.ml` both set `Sys.sigpipe` to `Signal_ignore`
at module load, before any of this repository's code runs), so a write to
an already-reset peer cannot deliver a process-fatal signal through that
path either — ruling out the other classic cause of a "write to a dead
socket kills the process" bug.

No source fix was needed for a crash that does not reproduce. What S6
does instead: makes "an abrupt disconnect survives" a structural property
(see the parking design below — a client-close, of any shape, never
reaches a code path that tears the worker down) and adds a permanent
regression test, `test/test_serve_reconnect.ml`'s `prereq_a` scenario,
which exercises exactly this invariant against a real worker process on
every `dune runtest` run.

### PREREQ-B: Origin check moved before `ensure_worker`

`Serve_proxy.resolve` (which may call `Serve_session.ensure_worker`,
spawning a worker) now runs strictly after `handle_connection` has read
the request head and evaluated the FR-045 Origin check — previously the
Origin check lived inside the `` `Forward `` branch, after `resolve` had
already run. A valid-token-but-foreign-Origin controller request is now
refused before any worker is ever spawned, rather than spawning one that
is refused before being contacted.

### The reconnect implementation

The design spike above (§2) predicted the change was localized to three
points in `run_tui` plus a same-worker-reconnect lookup in the session
table, without needing to touch `Matrix_main_loop`. That held, with one
simplification the spike didn't anticipate: `Matrix_main_loop.run`
already handles a `Matrix_io.Resize` event by writing `"\027[2J\027[H"`
and calling `Matrix_buffer.mark_all_dirty` (`matrix_main_loop.ml`'s
`Matrix_io.Resize` case, used for an ordinary xterm.js window resize
during a live session) — exactly the FR-050 full-redraw behavior a
reattach needs. Reconnect reuses this *existing, already-tested* path by
injecting a synthetic `Matrix_io.Resize` event, rather than duplicating
the clear/redraw sequence in `web_driver.ml`.

`Web_driver.Session.t` (the worker's own single-controller-slot record,
distinct from `Serve_session.t`) gained:
- `controller_parked : bool` — true once a controller has attached and
  its connection has since closed (any close, clean or abrupt) without
  the app reaching a terminal outcome.
- `reattach : (Web_websocket.t -> Eio.Buf_read.t -> close:(unit -> unit)
  -> unit) option` — installed once by `run_tui`, right before it starts
  running the main loop; captures `run_tui`'s own private mutable state
  (the current-transport cell, the switch reader fibers are forked
  under, the event stream), so `Session` itself never needs to know any
  of `run_tui`'s internals.

`run_tui` gained a mutable `current_ws`/`close_current` cell (the "current
transport" the spike named) and a `park_if_current` function (a
physical-equality-guarded reset, same pattern as
`Serve_session.reap_and_log`'s `w == worker` guard) called by the reader
fiber's close-handling *instead of* injecting `Matrix_io.Quit`. The
flusher fiber now reads through `current_ws` on every tick instead of
closing over a fixed `ws`, and drops (does not buffer) output while
parked — a reattach forces a full redraw via the synthetic Resize event,
so replaying whatever accumulated while nobody was listening would be
wasted work at best and stale content at worst. The accept loop's `/ws`
branch routes a new connection to a session that is `Session.can_reattach`
(parked, with a live `reattach` callback) to that callback instead of
spawning a fresh `page_loop`/`run_tui` call or refusing "slot taken".

App Quit (or `Back` with an empty page stack, or `SwitchTo` naming a page
the registry doesn't have) is the one outcome that still ends `run_tui`'s
call for good; `Web_driver.run_on` gained an `?on_session_end` hook
(default a no-op, preserving this generic driver's pre-S6 behavior for
non-serve callers such as `example/gallery/main_web.ml`) fired exactly
once at that point. `Serve_worker.run` wires this hook to
`exit Serve_worker.quit_exit_code` — an arbitrary, distinguishing exit
code — so the worker process itself ends. `Serve_session.reap_and_log`
recognizes that specific exit code and marks the session permanently
`dead` (the same terminal state `kill_worker_escalating`'s idle-timeout
reap already uses), rather than self-healing back to `Not_spawned`: a
deliberate app-quit is a dead end (FR-050: "reconnect-after-quit = dead
token"), not a crash to recover from.

### FR-051 (documented non-goal)

There is no input sequence numbering across a reconnect. A keystroke sent
by the client in the brief window between the old connection parking and
a new one reattaching can be lost (the reader fiber that would have
delivered it no longer exists, and the new one hasn't started yet) — this
is an accepted limitation, not a bug: implementing exactly-once delivery
across an arbitrary client-side transport swap would require a
sequence-numbered ack/replay protocol the spec explicitly scopes out of
this slice (`briefs/miaou-serve-spec.md`'s FR-051 entry). A lost keystroke
in that window is silently dropped, exactly as if the user had typed it a
moment before the tab closed.

### Verification

`test/test_serve_reconnect.ml` drives a real supervisor + worker (via
`Supervisor.accept_loop`, the same harness pattern as
`test_serve_multi_session.ml`) with a stateful counter page, over raw
RFC 6455 sockets: the `prereq_a` scenario asserts an abrupt disconnect
(`Unix.shutdown` + close) leaves the worker's pid unchanged and the
session reattachable; the `reconnect` scenario attaches, bumps the
counter to a known value, drops the connection abruptly, reconnects
within a bounded retry window (accommodating the supervisor's own
bounded controller-live-detach race — a real reconnecting client would
retry the same way), and asserts the same worker pid answers, the first
post-reconnect frame carries a full-screen clear, and the repainted
content reflects the preserved counter value rather than the page's
initial state. A manual runtime check drove an actual `miaou serve`
process (not the test binary) through the identical
attach→navigate→abrupt-drop→worker-alive→reconnect→state-preserved
sequence over raw sockets in a live terminal session, confirming the same
result outside of Alcotest.
