# Miaou UI Toolkit TODO (from octez-setup WIP plan)

Source prompts (octez_setup/prompts/wip_plan):
- M5_01: prompts/wip_plan/M5_ui_toolkit/01_implement_layout_widgets.md
- M5_02: prompts/wip_plan/M5_ui_toolkit/02_implement_feedback_widgets.md
- M5_03: prompts/wip_plan/M5_ui_toolkit/03_implement_navigation_widgets.md
- M5_90: prompts/wip_plan/M5_ui_toolkit/90_gardening_round_1.md
- M6_01: prompts/wip_plan/M6_ux_overhaul/01_refactor_pages_to_table_widget.md

## Tasks
- [x] Layout widgets (M5_01)
  - `Card_widget` lives in `src/miaou_widgets_layout/card_widget.{ml,mli}` with tests (`test/test_layout_widgets_new.ml`) and demo launcher entry ("Card & Sidebar" in `example/demo_lib.ml`).
  - `Sidebar_widget` implemented in `src/miaou_widgets_layout/sidebar_widget.{ml,mli}` with toggle logic (Tab in demo), tests, and gallery entry.
- [x] Feedback widgets (M5_02)
  - `Toast_widget` implemented with position/severity/auto-dismiss queue (`src/miaou_widgets_layout/toast_widget.{ml,mli}`) + tests (`test/test_feedback_widgets.ml`) and demo entry "Toast Notifications".
  - [ ] Integrate with flash bus (`Tui_flash_messages` or new bus); expand headless tests and wire bus into demo once ready.
- [ ] Navigation widgets (M5_03)
  - Implement `Tabs_widget` (tab list, Left/Right/Home/End navigation, selection callback).
  - Implement `Breadcrumbs_widget` (hierarchical path rendering, optional enter handler per crumb).
  - Add `.mli` docs, headless/tests, and gallery demos.
- [ ] Gardening (M5_90)
  - Run/update module catalog (`docs/gardening/m5_module_catalog.md`).
  - Deduplicate widget APIs (buttons/renderers), ensure `.mli` coverage, consistent naming/palette hooks.
  - Record follow-ups for redesigns if needed.
- [ ] Demo coverage planning
  - Audit the gallery (`example/demo_lib.ml`, run via `dune exec -- miaou.demo` or `miaou.demo-sdl`) and add TODO entries here for every widget that currently lacks a demo. The goal is to spawn one sub-task per missing widget (not to implement all at once) so that every widget eventually has a labeled, minimal interaction in the launcher.
