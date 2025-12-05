# AGENT.md — Miaou Repository

This guide defines how automation agents work on the standalone Miaou TUI
library. Follow it whenever a prompt inside `prompts/` references Agent2
(Builder/Implementer).

## Scope & Responsibilities
- Work only inside this repository unless a prompt explicitly links to
  octez-setup for integration follow-ups.
- Modify library code (`src/`), tests (`test/`), docs, examples, and CI
  files as required by the assigned prompt.
- Keep commits scoped to Miaou. Octez-setup will bump the dependency via a
  separate task once your work is merged here.

## Workflow Overview
1. Claim a prompt from `prompts/active/` (or `prompts/lite/`) by moving it
   to `prompts/ongoing/`.
2. Implement the requested changes, keeping UX/DX quality high for library
   consumers.
3. Run the required checks (defaults):
   - `dune build @all`
   - `dune runtest`
   - `dune fmt --check` (or `dune fmt` before committing)
4. Record capture assets if the prompt requests TUI demos (store them under
   `recordings/` and reference in completion notes).
5. Commit with the provided message, push, and move the prompt to
   `prompts/done/`.

## Cross-Repository Coordination
- When a prompt exists here because Octez-setup needs a new capability,
  mention the downstream task number in your completion notes so the
  Planner can trigger the dependency bump.
- Do **not** edit Octez-setup from this repo. Instead, add a follow-up entry
  in `prompts/active/` (here) describing the required Octez changes, or ping
  the Planner if unclear.

## Completion Notes Template
Each prompt should end with a Markdown block similar to:
```
---
**Completion Notes**
- Prompt: <name>
- Commits: <hash message>
- Build: dune build @all (PASS/FAIL + summary)
- Tests: dune runtest (PASS/FAIL + summary)
- Captures: <files or n/a>
- Follow-ups: <list or none>
```

Keep this file updated if repository processes evolve.
