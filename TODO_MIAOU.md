# Miaou UI Toolkit TODO (from octez-setup WIP plan)

Source prompts (octez_setup/prompts/wip_plan):
- M5_01: prompts/wip_plan/M5_ui_toolkit/01_implement_layout_widgets.md
- M5_02: prompts/wip_plan/M5_ui_toolkit/02_implement_feedback_widgets.md
- M5_03: prompts/wip_plan/M5_ui_toolkit/03_implement_navigation_widgets.md
- M5_90: prompts/wip_plan/M5_ui_toolkit/90_gardening_round_1.md
- M6_01: prompts/wip_plan/M6_ux_overhaul/01_refactor_pages_to_table_widget.md

## Tasks
- [ ] Layout widgets (M5_01)
  - Implement `Card_widget` (title, body, optional footer, palette-aware borders) in `src/miaou_widgets_layout/`.
  - Implement `Sidebar_widget` with collapsible state (`[` toggle), graceful auto-collapse on narrow terminals.
  - Add `.mli` docs with usage examples; add demos/tests (e.g., widget gallery).
- [ ] Feedback widgets (M5_02)
  - Implement `Toast_widget` with position (`Top_right`, `Bottom_right`, etc.), severity (info/success/warn/error), auto-dismiss queue.
  - Integrate with existing flash bus (`Tui_flash_messages` or new bus); add unit tests and a demo page.
- [ ] Navigation widgets (M5_03)
  - Implement `Tabs_widget` (tab list, Left/Right/Home/End navigation, selection callback).
  - Implement `Breadcrumbs_widget` (hierarchical path rendering, optional enter handler per crumb).
  - Add `.mli` docs, headless/tests, and gallery demos.
- [ ] Gardening (M5_90)
  - Run/update module catalog (`docs/gardening/m5_module_catalog.md`).
  - Deduplicate widget APIs (buttons/renderers), ensure `.mli` coverage, consistent naming/palette hooks.
  - Record follow-ups for redesigns if needed.
- [ ] Demo coverage planning
  - Create a sub-checklist of missing demo entries per widget (existing + upcoming) and add them to this TODO. Scope: demo gallery in `example/demo_lib.ml` (launcher via `dune exec -- miaou.demo` or `miaou.demo-sdl`), each with a labeled entry and minimal interaction.
