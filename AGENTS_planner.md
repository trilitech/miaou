# Planner Guide — Miaou Repository

This document complements the octez-setup planner guide. Use it when creating
or reviewing prompts under `prompts/` in the standalone Miaou repo.

## Mandate
- Translate Supervisor requirements for reusable TUI widgets, drivers,
  demos, capture tooling, and documentation into actionable prompts for
  Agent2.
- Keep Miaou prompts focused on generic functionality. Any Octez-specific
  wiring must stay in the octez-setup backlog.
- Ensure every prompt defines: Execution Mandate, Goal, Actions, Workflow
  Algorithm, Error Handling, Commit Message, Deliverables, and Verification
  Plan.

## Repository-Specific Notes
- **Verification:** Default build/test gates are `dune build @all`,
  `dune runtest`, and `dune fmt --check`. Add additional commands (e.g.,
  demo capture scripts) when necessary.
- **Captures & Recordings:** Store new playback assets under
  `recordings/` and reference them from prompts when needed by Octez UX.
- **Versioning:** Keep `dune-project`, `miaou.opam`, and README metadata
  accurate. Planner should schedule release-prep prompts whenever new
  widgets require a published tag before Octez-setup can depend on them.

## Cross-Repo Coordination
- When Octez-setup depends on a Miaou change, stage **paired prompts**:
  1. A Miaou prompt implementing the reusable feature.
  2. A follow-up Octez prompt (in its repo) to bump the dependency and wire
     the feature.
- Reference the matching task IDs in both prompts so Agent2s on each side
  understand the sequencing.
- Avoid duplicating instructions; instead, link back to the canonical plan
  documents (e.g., baker plans, UX specs) stored in the private workspace.

## Prompt Lifecycle
```
active → ongoing → done → reviewed
```
`reviewed/` is write-only for Agent2; only the Planner moves files there
after evaluation.

Keep this guide in sync with process changes and document any new tooling
requirements (e.g., CI jobs, lint rules) that affect Miaou development.
