# Agent Playbook for `miaou`

You maintain **Miaou**, a TUI toolkit and drivers used by Octez tools. Keep scope tight: robust widgets, drivers, and core UI primitives. Maximize reliability, clarity, compiler-checked safety, and type-driven design.

## Process guardrails
- Maintain a timestamped TODO/checklist; after each item run `dune build @all`, `dune test`, coverage target (if available), and `dune fmt`/`ocamlformat`. Do not proceed with warnings or failures.
- Commit per item (small, logical commits). Keep the tree clean between items; CI should fail on dirty trees. Never amend unless required.
- Preserve/raise coverage; if a change would drop coverage, add/adjust tests first.
- Keep docs/demos aligned with behavior in the same commit as changes. Avoid scope creep; stay toolkit/driver-focused.

## OCaml type discipline (push hard)
- Prefer rich types over ad-hoc strings/booleans; encode state transitions with sum types, abstract types, and module boundaries. Lean on `result` for error-aware APIs; prefer `result`/`option` over exceptions for recoverable errors.
- Use phantom types/GADTs to make invalid states unrepresentable (e.g., focus modes, navigation state, validated dimensions).
- Expose minimal public signatures; keep concrete representations private. Let the compiler enforce invariants; avoid partial functions and unchecked exceptions.
- Use type-directed parsers/formatters instead of stringly-typed configs. Prefer `eio` over `lwt` for async/concurrency. Do not use `Obj.magic` (forbidden).

## Style/tooling defaults
- Pin OCaml/toolchain and `ocamlformat` versions; document them in README/TODO.
- Prefer `-warn-error +A` (or equivalent) in dune for library code. Require `.mli` for public modules; keep concrete types abstract.
- Avoid global mutable state; pass capabilities explicitly.

## Security/permissions stance
- Default to least privilege; no secrets in logs; sanitize paths/URLs before printing.
- Treat external inputs (terminal events, file paths) as untrusted; bound timeouts where applicable.

## Error/telemetry
- Standardize result/error reporting and logging format for drivers/widgets; no silent failures. Each external call should surface errors in a parseable/loggable way.

## Release/ops checklist
- Before release/branch cut: run full build/test/coverage, refresh docs/demos, note dependency pins, ensure clean tree.

## Miaou-specific priorities (from octez-setup WIP plan)
- Implement UI toolkit widgets (layout: card/sidebar; feedback: toast; navigation: tabs/breadcrumbs) with pure APIs, docs, demos, and tests.
- Garden the widget library (deduplicate renderers, ensure `.mli` coverage, keep module catalog updated).
- Refactor list-heavy pages to the standardized `Table_widget` once widgets are in place; keep key hints consistent.
- Keep drivers thin and testable; headless/test harness support is desirable for regression tests.

## Daily discipline
- Before coding: update TODO, restate goal, ensure clean tree.
- During coding: add only succinct comments where logic isn’t obvious; design types first.
- After coding: format, test, coverage, docs/demos, update TODO, then commit with a clear message.
- Never revert user changes or run destructive commands without explicit instruction.
