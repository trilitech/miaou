# MIAOU Agent Protocol — v1.0 (TEXT-FIRST)

<!-- protocol_version: 1.0 -->

This document describes the MIAOU agent protocol: a JSON envelope for
driving a MIAOU TUI app headlessly (`MIAOU_DRIVER=headless`), available over
two transports — line-delimited JSON-over-stdio (`miaou-headless-json`,
the existing runner) and MCP (`miaou-mcp`, new). Both transports share one
dispatcher, `Miaou_protocol.Protocol_core.handle_cmd`, so their command
semantics are identical by construction, not by convention.

The version stamped as `schema_version` on every response, and asserted by
`test/protocol/*` against this document's own version header (the HTML
comment above), is **1.0**. A test fails CI if this file's header and
`Protocol_version.current` (`src/miaou_protocol/protocol_version.ml`) ever
drift apart.

## Scope: TEXT-FIRST v1

This is the scope actually implemented, per the spec's
`SCOPE DECISION (human, 2026-07-15): TEXT-FIRST v1`
(`briefs/agent-protocol-mcp-spec.md`). It deliberately **excludes** a
semantic widget/focus tree, `role:name` locators, spatial `click`,
`fill`, `scroll`, and `assert_snapshot` — those require a typed view tree
(a future, separate project) and are not implementable as an additive
render-time side channel, per that spec's adversarial review. Everything
below observes/drives the app via its **ANSI-stripped text frame** and
low-level key synthesis, never widget structure.

## Commands (JSON-over-stdio and MCP tool names are identical)

| Command | Kind | Description |
|---|---|---|
| `render` | read-only | Re-render and return the current frame. |
| `key` | mutating | Send one key (`{"key": "Down"}`) through the driver, then re-render. |
| `tick` | mutating | Advance `n` idle iterations (clocks/timers/refresh), then re-render. |
| `resize` | mutating | Change the simulated terminal size (`{"rows":..,"cols":..}`). |
| `quit` | mutating | End the session. |
| `wait_for` | read-only | Block server-side until a condition holds or `timeout_ms` elapses (see below). |
| `assert_screen` | read-only | Single non-blocking text-predicate check against the current frame. |

Every response carries `"schema_version": "1.0"` (FR-001). Unknown/extra
request fields are ignored, not rejected (FR-002). `render`/`key`/`tick`/
`resize`/`quit` are unchanged in shape beyond the additive `schema_version`
field — a pre-existing recorded transcript
(`test/protocol/golden/baseline_v1.jsonl`) is replayed in
`test/protocol/replay_test.ml` and diffed against a fresh run, ignoring only
added keys, to guard this (FR-003/FR-100).

An optional top-level `"protocol_version"` field on any request is validated
against the server's supported set (`Protocol_version.supported`, currently
just `["1.0"]`); an unsupported version yields `E_BAD_REQUEST`. Omitting the
field entirely (every pre-existing v1 client) is always accepted.

### `wait_for` conditions (FR-040)

Exactly one of:

- `{"modal": true|false}` — `Modal_manager.has_active ()` equals the given
  boolean.
- `{"text_contains": "needle"}` — literal substring match against the
  ANSI-stripped frame text.
- `{"text_matches": "regex"}` — `Str`-syntax regex match against the same
  text.
- `{"page": "name"}` — the currently installed page's registry name equals
  `name`.

Optional `timeout_ms` (default 500) and `poll_interval_ms` (default 10)
mirror `Workflow.await_modal`'s defaults (`max_iters=50, sleep=0.01`). This
is always **one request, one response** (FR-041): polling happens entirely
inside the server, never as repeated client round-trips. The condition is
checked *before* any refresh/tick, so an already-true condition is observed
without mutating anything; only a false check advances one idle iteration
and sleeps before the next check. Because each subsequent poll does call
`HD.Stateful.idle_wait`, which ticks clocks/timers and refreshes the page,
`wait_for` is not a fully passive observer in the general case — this is
accepted for TEXT-FIRST v1 (it never calls `send_key`/`switch_to_page`, so
it stays in the read-only classification, FR-081) and documented here per
the spec's risk table.

**Implementation note**: the poll loop runs on the *main* Eio fiber via
`Eio_unix.sleep` between checks. It must **not** run inside
`Eio_unix.run_in_systhread` — `idle_wait`'s fiber-yield path has no effect
handler installed in a systhread and crashes, and a systhread would race the
viewer daemon fiber's concurrent reads of the shared screen buffer.

On timeout, the response mirrors `Workflow.error` (`step`, `message`,
`attempt`, `screen`) field-for-field, plus `"code": "E_TIMEOUT"` and
`schema_version` (FR-042). A parity test
(`test/protocol/wait_for_test.ml`) checks this structural equivalence
against an in-process `Workflow_error`.

### `assert_screen` (FR-050)

`{"contains": "needle"}` or `{"matches": "regex"}` → `{"ok": true}` or
`{"ok": false, "error": {...}}`. The nested `error` object carries `step`/
`message`/`screen`/`schema_version` but **no `code`** — like
`Workflow.expect`, an assertion failure is not one of the five protocol
error codes, just a Workflow-shaped diagnostic.

## Error taxonomy (FR-090/FR-091)

A closed set of five codes, never an ad hoc string:

- `E_BAD_REQUEST` — malformed JSON, missing/invalid field, an unsupported
  `protocol_version`, or a `wait_for`/`assert_screen` `text_matches`/`matches`
  pattern that doesn't compile as a regex (e.g. an unclosed `[` character
  class).
- `E_UNSUPPORTED_COMMAND` — unrecognized `cmd`.
- `E_TIMEOUT` — a `wait_for` condition never became true.
- `E_READ_ONLY` — a mutating tool was called against `miaou-mcp --read-only`.
- `E_INTERNAL` — any *unanticipated* dispatch failure. `handle_cmd` never
  raises: every known-fallible input (regex compilation included) is
  validated and reported as one of the codes above, and a top-level
  catch-all in `handle_cmd` converts anything else into `E_INTERNAL` rather
  than letting an exception escape into the transport loop — neither the
  stdio shim nor `miaou-mcp`'s tool handlers guard this call themselves, so
  an uncaught exception here would otherwise crash the whole process on
  attacker-controlled input (e.g. a malformed regex over stdin/MCP). Eio's
  own cancellation exception is re-raised unchanged so structured-concurrency
  shutdown is unaffected.

Every error response carries `schema_version` so a client can distinguish
"old server, new code it doesn't understand" from "malformed response".

## Session recording (FR-060–062)

Every protocol session is recorded by default: `Tui_capture.force_enable ()`
is called before the first frame (both `miaou-headless-json` and
`miaou-mcp`), which turns on keystroke/frame JSONL capture unless the
operator already set the classic `MIAOU_DEBUG_KEYSTROKE_CAPTURE`/
`MIAOU_DEBUG_FRAME_CAPTURE` env vars explicitly (those still win, unchanged
from before this feature). `MIAOU_NO_RECORD=1` or the `--no-record` CLI flag
disables recording entirely, and always wins over the default-on behavior.

The default output directory, when `MIAOU_DEBUG_CAPTURE_DIR` is unset, is
`recordings/sessions/` (not the current working directory).

Consecutive identical frames are deduplicated in the recording path: a
`wait_for` poll loop that re-renders the same unchanged screen many times
over produces only one JSONL frame line, not one per poll.

## `miaou-mcp` (FR-070–081)

`miaou-mcp` is an MCP server over stdio (`Mcp_kit_stdio.run_channels`)
driving the gallery launcher demo (`example/gallery/launcher.ml`) — the same
fixture the conformance suite exercises.

- **Tools** (mutating actions + everything requiring a live driver call):
  `render`, `key`, `tick`, `resize`, `quit`, `wait_for`, `assert_screen`.
  Every tool's `arguments` object is merged onto `{"cmd": <tool name>}` and
  handed to the exact same `Protocol_core.handle_cmd` the stdio transport
  uses.
- **Resources** (static, addressable by URI): `miaou://pages` (JSON array
  from `Registry.list_names ()`), `miaou://protocol/version` (JSON object
  with `schema_version`).
- **`--read-only`**: mutating tools (`key`, `tick`, `resize`, `quit`) are
  registered as stubs that unconditionally return `E_READ_ONLY` *at
  `Server.create`/`add_tools` time* — the refusal lives in the dispatch
  table mcp-kit itself calls, not a list-time-only or client-side gate.
  `render`/`wait_for`/`assert_screen` are unaffected. A conformance test
  (`test/mcp/mcp_tools_test.ml`) iterates every registered tool name and
  asserts it is classified in exactly one of {read-only, mutating}
  (`Mcp_tools.classification`), so a future tool added without updating that
  list fails CI loudly instead of silently re-exposing a mutation.
- **`--no-record`**: see Session recording above.
- Structured errors have no dedicated MCP content type, so they are
  serialized as JSON text inside the tool result's `content` block *and*
  duplicated into `structured_content` for clients that read the
  machine-readable copy (FR-073).
- No MCP notifications/streaming are used anywhere: `wait_for` is the only
  "waiting" primitive, and it blocks server-side for the single request
  (FR-076).

### Root-build story: the mcp-kit pin

`mcp-kit`/`mcp-kit-eio` are **not published** to the default opam
repository yet, and their transport-split packages live only on the
unreleased branch `feat/split-transport-packages` of the public repo
`github.com/epure-team/ocaml-mcp`.

**Decision**: `miaou-mcp` is a **build-only target, deliberately not an
installable opam package.** There is intentionally no root
`miaou-mcp.opam`, and the `dune-project` has no `miaou-mcp` package
stanza, so CI's `opam install --deps-only --with-test -y .` never tries to
resolve the unreleased pin (a bare-commit `pin-depends` is not reliably
fetchable — GitHub cannot serve a loose SHA that only exists on a
non-default branch, which is exactly what broke the first CI attempt). The
library (`mcp_tools`) and executable (`miaou_mcp_main`) are marked
`(optional)` in `src/miaou_mcp/dune`, and the test suite
(`test/mcp/mcp_tools_test.ml`) is an `(executable)` + `(rule (alias
runtest) ...)` (`(test)` doesn't support `(optional)`), so both are
skipped, not failed, without the pin. This means:

- A developer on a fresh switch without the pin gets a fully green
  `dune build @all` / `dune runtest` — `miaou-mcp` and its tests are
  silently absent from the build graph.
- CI stays green with **no ci.yml changes**: no `miaou-mcp.opam` for
  `opam install .` to choke on, and `test/tmux/scenario_mcp_stdio.sh`
  `SKIP`s (exit 77) when the binary isn't built.
- To build/test `miaou-mcp` locally, add the pin (branch ref, which is
  always fetchable — unlike a loose commit) and build the directory:

  ```
  opam pin add -n mcp-kit     git+https://github.com/epure-team/ocaml-mcp#feat/split-transport-packages
  opam pin add -n mcp-kit-eio git+https://github.com/epure-team/ocaml-mcp#feat/split-transport-packages
  opam install mcp-kit mcp-kit-eio
  dune build src/miaou_mcp
  ```

- **Promotion path**: once mcp-kit's transport-split lands on the default
  opam repository (or a tagged release), add a real `miaou-mcp` package
  stanza + `depends` and drop the `(optional)` markers.

## FR-coverage manifest

TEXT-FIRST v1 in-scope requirements and where each is checked:

| FR | Covered by |
|---|---|
| FR-001, FR-002, FR-003 | `test/protocol/replay_test.ml` |
| FR-100 | `test/protocol/replay_test.ml` (golden transcript: `test/protocol/golden/baseline_v1.jsonl`) |
| FR-040 (all 4 condition kinds) | `test/protocol/wait_for_test.ml` |
| FR-041 (single request/response) | `test/protocol/wait_for_test.ml` |
| FR-042 (Workflow.error parity) | `test/protocol/wait_for_test.ml` |
| FR-043 (timeout/poll defaults) | `src/miaou_protocol/protocol_core.ml` (`default_timeout_ms`/`default_poll_interval_ms`), exercised in `wait_for_test.ml` |
| FR-050 | `test/protocol/wait_for_test.ml` |
| FR-060, FR-061 | `test/protocol/recording_test.ml` |
| FR-062 | n/a beyond JSONL completeness (no `.cast` conversion tooling; explicitly out of scope) |
| FR-070–FR-076 | `test/mcp/mcp_tools_test.ml`, `test/tmux/scenario_mcp_stdio.sh` |
| FR-080, FR-081 | `test/mcp/mcp_tools_test.ml` (`test_classification_exhaustive`, `test_read_only_stubs_every_mutating_tool`) |
| FR-090, FR-091 | `test/protocol/wait_for_test.ml` (`test_error_taxonomy_closed_set`, timeout/assert-failure shape tests, malformed-regex-is-`E_BAD_REQUEST` regression tests); `test/protocol/internal_error_test.ml` (unanticipated-exception-is-`E_INTERNAL` regression test) |

**Deferred (not implemented, tracked separately per the spec's scope
decision)**: FR-010–FR-014 (semantic snapshot tree), FR-020–FR-025 (locator
grammar), FR-031–FR-034 as originally specified (spatial `click`, `fill`,
`scroll` — the `click` command remains the pre-existing row/col-ignoring
stub), FR-051 (`assert_snapshot`).
