# Bootstrapping Miaou Agents

**Mission**: pick up the Miaou TUI gap-closing work (flex layout, wrapping, focus/bubbling, tutorials) and keep the codebase healthy while we close the Mosaic/Nottui feature and UX gaps.

## Quick context
- Repo: `miaou` (branch `feature/miaou-widgets` unless told otherwise).
- Drivers: term (lambda-term), SDL, headless. Tests run with `dune runtest --no-buffer`; demo with `dune exec miaou.demo` (needs a terminal) or `MIAOU_DRIVER=sdl dune exec miaou.demo-sdl`.
- Key areas:
  - `src/miaou_widgets_layout/flex_layout.*`: flex rows/cols, gaps, alignment.
  - `src/miaou_widgets_display/widgets.ml`: wrapping utilities.
  - `src/miaou_internals/focus_chain.*`: focus rotation helper.
  - `src/miaou_widgets_navigation`: tabs/breadcrumbs/link bubbling.
  - `example/demo_lib.ml`: gallery pages, hints, tutorials (`t` key).
  - `example/tutorial_modal.ml`: Markdown tutorial modal for demos.
  - `docs/gardening/m5_followups.md`: prioritized gap-closing plan; mark items done and advance.

## Working instructions
- Read `AGENTS.md` (repo root) before coding; follow coding style, testing, and commit discipline.
- Keep gardening notes in `docs/gardening/` and update TODOs as you complete items. Do not commit ad-hoc gardening scratch files unless intended.
- Favor typesafety (OCaml types, phantom/GADTs where useful), avoid `Obj.magic`, prefer `Eio` over `Lwt`, and reuse `result`-based flows.
- Keep demos in sync: when adding widgets/features, add a demo entry (in `example/demo_lib.ml`) and a short developer-oriented tutorial via `t`.
- Tests: extend headless tests for new behaviours; snapshot/footers are in `test/`. Prefer driver-agnostic tests when possible.

## Current state (handoff)
- Flex layout implemented and demoed; wrapping support added to pager/table/description list; bubbling for tabs/breadcrumbs/link; focus_chain available; tutorial modal wired for some pages.
- Known open issue: checkbox demo in `example/demo_lib.ml` still does not toggle on Enter in the terminal driver (Space works). Driver dispatch was adjusted, but the demo still misses Enter—please trace key flow and fix. Add a regression test if feasible.
- Untracked gardening drafts: `docs/gardening/add_charts_widget.md`, `docs/gardening/add_image_widget.md`—leave uncommitted unless explicitly requested.

## How to proceed
1. Skim `docs/gardening/m5_followups.md`; mark completed items; start the next high-priority gap.
2. Fix the checkbox Enter issue end-to-end (driver + demo), add a test that would have caught it.
3. Ensure each demo page has a correct hint/footer and a `t` tutorial (developer-oriented: what it shows, how to use, how it’s built).
4. Keep commits small and run `dune runtest --no-buffer` before committing. Do not push unless requested.
5. When adding widgets/features, retrofit existing demos and update TODOs to ensure every widget is represented in the gallery.

## Quick commands
- Tests: `dune runtest --no-buffer`
- Build: `dune build`
- Term demo: `dune exec miaou.demo`
- SDL demo: `MIAOU_DRIVER=sdl dune exec miaou.demo-sdl`

## When unsure
- Prefer adding a small headless regression test.
- Update `docs/gardening/m5_followups.md` with decisions and progress.
- Ask for clarification before altering untracked gardening drafts.
