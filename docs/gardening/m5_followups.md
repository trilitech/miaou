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
  - Disabled-state tests for checkbox/radio/switch/button (handle_key is no-op when disabled).
  - Snapshot-like checks for tabs/breadcrumbs separators/highlight; link key handling.
- Demo consistency:
  - Ensure demo list labels/hints match widget names and show key hints (e.g., “1/2/3 to toggle”).
  - Add a minimal “API panel” string per demo with key bindings.
- Styling consistency:
  - Normalize separators/dimming (`|` vs `>` vs `│`) per widget family and document the choice.
  - Prefer palette helpers over hard-coded colors (e.g., buttons).
- Cleanup:
  - Drop unnecessary warning suppressions where possible.
  - Ensure new helpers aren’t duplicated across modules.

## Closing gaps vs. Mosaic (prioritized)
- [ ] Mouse event plumbing: add mouse parsing/forwarding in term/SDL drivers; expose a common `pointer_event` type to widgets (start with click/scroll).
- [ ] Slider widget: keyboard+mouse slider (min/max/step, label, value display) with demo + tests.
- [ ] Scrollbox widget: vertical scroll container with scrollbar thumb; keyboard + mouse wheel; demo + tests.
- [ ] Markdown renderer: minimal markdown→ANSI (headers, lists, code, emphasis); demo + snapshot tests.
- [ ] Code block renderer: monospace block with optional line numbers / basic syntax highlighting hooks; demo + tests.
- [ ] Canvas-lite: simple 2D drawing API over a char grid (set pixel, line, rect); demo (e.g., rain/life) + deterministic render tests.
- [ ] Diff rendering: optional line-diff renderer for the terminal driver to reduce overdraw/flicker.
- [ ] Flexbox-like layout: evaluate integrating a minimal flex row/col API (Toffee-like) over existing renderers; demo + tests.
- [ ] Terminal emulator/PTY: optional VTE wrapper to display subprocess output with scroll; higher effort, needs mouse scroll support.
