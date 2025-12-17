# Miaou UI Toolkit TODO (from octez-setup WIP plan)

Source prompts (octez_setup/prompts/wip_plan):
- M5_01: prompts/wip_plan/M5_ui_toolkit/01_implement_layout_widgets.md
- M5_02: prompts/wip_plan/M5_ui_toolkit/02_implement_feedback_widgets.md
- M5_03: prompts/wip_plan/M5_ui_toolkit/03_implement_navigation_widgets.md
- M5_90: prompts/wip_plan/M5_ui_toolkit/90_gardening_round_1.md
- M6_01: prompts/wip_plan/M6_ux_overhaul/01_refactor_pages_to_table_widget.md

## Session 2025-12-17
- [x] 2025-12-17: Add changelog entry for modal dynamic width (`max_width_spec`) and breaking API note.

## Session 2025-12-15
- [x] 2025-12-15: Fix File_pager cleanup hang by scoping tail fibers to page lifecycle and updating docs/tests as needed.
- [x] 2025-12-15: Fix modal sizing so modal pages render to the actual modal content height and don’t scroll into invisible items.

## Tasks
- [ ] Gardening (M5_90)
  - [x] Run/update module catalog (`docs/gardening/m5_module_catalog.md`).
  - Deduplicate widget APIs (buttons/renderers), ensure `.mli` coverage, consistent naming/palette hooks.
  - Record follow-ups for redesigns if needed.
- [x] Flex layout (gap-closing step 1 from `docs/gardening/m5_followups.md`)
  - Finalize the public API/docs in `src/miaou_widgets_layout/flex_layout.mli` (align with `docs/gardening/flex_api_design.md`, clarify basis semantics: px/percent/ratio/fill/auto).
  - Lock down alignment rules (`align_items`, `justify`, gap/padding) with examples and invariants documented in the `.mli`.
  - Add sizing property tests in `test/test_flex_layout.ml` to cover padding/gap/percent/ratio/cross-axis stretch vs center.
  - Add a small demo snippet (in `example/demo_lib.ml`) exercising row+column with mixed bases to validate ergonomics.
- [ ] Demo coverage planning
  - Audit the gallery (`example/demo_lib.ml`, run via `dune exec -- miaou.demo` or `miaou.demo-sdl`) and add TODO entries here for every widget that currently lacks a demo. The goal is to spawn one sub-task per missing widget (not to implement all at once) so that every widget eventually has a labeled, minimal interaction in the launcher.
  - [x] Add demo entry for `Link_widget` (`src/miaou_widgets_navigation/link_widget.{ml,mli}`); simple navigation hint and styling showcase.
  - [x] Add demo entry for `Checkbox_widget` (`src/miaou_widgets_input/checkbox_widget.{ml,mli}`); include toggling and disabled state.
  - [x] Add demo entry for `Radio_button_widget` (`src/miaou_widgets_input/radio_button_widget.{ml,mli}`); showcase grouped selection.
  - [x] Add demo entry for `Switch_widget` (`src/miaou_widgets_input/switch_widget.{ml,mli}`); include on/off animation and key bindings.
  - [x] Add demo entry for `Button_widget` (`src/miaou_widgets_input/button_widget.{ml,mli}`); show focus/press states.
  - [x] Add demo entry for `Validated_textbox_widget` (`src/miaou_widgets_input/validated_textbox_widget.ml`); include validation error display.
