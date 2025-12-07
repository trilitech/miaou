# M5 Gardening Follow-ups

Target: tighten APIs/UX consistency for the widgets added in M5 (layout/feedback/navigation/input) and keep demos/docs/tests aligned.

- Align APIs across navigation/input widgets:
  - Ensure all expose `render : t -> focus:bool -> string` and `handle_key : t -> key:string -> ...` and document it in `.mli`.
  - Consider optional `disabled` state and label handling consistency (button/checkbox/radio/switch).
- Extract shared helpers:
  - Small common module for padding/highlight/separators used by tabs/breadcrumbs/link.
  - Shared label rendering (bold/dim on focus) for input widgets to reduce duplication.
- Docstring/examples:
  - Add short usage snippets/key hints to `.mli` for tabs, breadcrumbs, toast, link, and input widgets.
- Tests to tighten:
  - [x] Disabled-state tests for checkbox/radio/switch/button (handle_key is no-op when disabled).
  - [ ] Snapshot-like checks for tabs/breadcrumbs separators/highlight; link key handling.
- Demo consistency:
  - Ensure demo list labels/hints match widget names and show key hints (e.g., “1/2/3 to toggle”).
  - Add a minimal “API panel” string per demo with key bindings.
- Styling consistency:
  - Normalize separators/dimming (`|` vs `>` vs `│`) per widget family and document the choice.
  - Prefer palette helpers over hard-coded colors (e.g., buttons).
- Cleanup:
  - Drop unnecessary warning suppressions where possible.
  - Ensure new helpers aren’t duplicated across modules.

## Closing major gaps (prioritized)
- Layout engine first:
  - [ ] Flex API design: define minimal flex row/col API (percentages/ratios, gap, padding, borders) and document expected usage.
  - [ ] Core implementation: build row/col primitives and padding/border helpers; expose via layout utils.
  - [ ] Retrofits: migrate a handful of demos/pages to the flex API to validate ergonomics.
  - [ ] Tests: add layout correctness/property tests for flex sizing/alignment; snapshot migrated demos.
- Text and input fidelity:
  - [ ] Add text wrapping and selection support in display helpers (pager/table/description lists).
  - [ ] Add focus management and optional event bubbling so mouse/keyboard events can propagate through composites.
- Terminal protocol and input support:
  - [ ] Mouse event plumbing: add mouse parsing/forwarding in term/SDL drivers; expose a common `pointer_event` type to widgets (start with click/scroll).
  - [ ] Modern terminal protocols: kitty keyboard, bracketed paste, focus tracking.
- Performance/allocations:
  - [ ] Phase 1: replace heavy `String.concat`/`List.init` patterns in hot paths (table, pager, pane, toast, drivers) with buffer/bytes building; reduce intermediate list allocs.
  - [ ] Phase 2 (prototype): grid-based render target with damage tracking/double buffering, keeping string rendering for compatibility during migration.
- Essential widgets/content:
  - [ ] Slider widget: keyboard+mouse slider (min/max/step, label, value display) with demo + tests.
  - [ ] Scrollbox widget: vertical scroll container with scrollbar thumb; keyboard + mouse wheel; demo + tests.
  - [ ] Markdown renderer: minimal markdown→ANSI (headers, lists, code, emphasis); demo + snapshot tests.
- Nice-to-have/backlog:
  - [ ] Code block renderer: monospace block with optional line numbers / basic syntax highlighting hooks; demo + tests.
  - [ ] Canvas-lite: simple 2D drawing API over a char grid (set pixel, line, rect); demo (e.g., rain/life) + deterministic render tests.
  - [ ] Diff rendering: optional line-diff renderer for the terminal driver to reduce overdraw/flicker.
  - [ ] Terminal emulator/PTY: optional VTE wrapper to display subprocess output with scroll; higher effort, needs mouse scroll support.
