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
