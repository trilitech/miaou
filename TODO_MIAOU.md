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
- [x] Navigation widgets (M5_03)
  - `Tabs_widget` (tab list, Left/Right/Home/End navigation) with docs/tests/demo (`src/miaou_widgets_navigation/tabs_widget.{ml,mli}`, `test/test_navigation_widgets.ml`, demo "Tabs Navigation" in `example/demo_lib.ml`).
  - `Breadcrumbs_widget` (hierarchical path rendering + Enter callbacks) with docs/tests/demo (`src/miaou_widgets_navigation/breadcrumbs_widget.{ml,mli}`, `test/test_navigation_widgets.ml`, demo "Breadcrumbs" in `example/demo_lib.ml`).
- [ ] Gardening (M5_90)
  - Run/update module catalog (`docs/gardening/m5_module_catalog.md`).
  - Deduplicate widget APIs (buttons/renderers), ensure `.mli` coverage, consistent naming/palette hooks.
  - Record follow-ups for redesigns if needed.
- [ ] Demo coverage planning
  - Audit the gallery (`example/demo_lib.ml`, run via `dune exec -- miaou.demo` or `miaou.demo-sdl`) and add TODO entries here for every widget that currently lacks a demo. The goal is to spawn one sub-task per missing widget (not to implement all at once) so that every widget eventually has a labeled, minimal interaction in the launcher.
  - [ ] Add demo entry for `Link_widget` (`src/miaou_widgets_navigation/link_widget.{ml,mli}`); simple navigation hint and styling showcase.
  - [ ] Add demo entry for `Checkbox_widget` (`src/miaou_widgets_input/checkbox_widget.{ml,mli}`); include toggling and disabled state.
  - [ ] Add demo entry for `Radio_button_widget` (`src/miaou_widgets_input/radio_button_widget.{ml,mli}`); showcase grouped selection.
  - [ ] Add demo entry for `Switch_widget` (`src/miaou_widgets_input/switch_widget.{ml,mli}`); include on/off animation and key bindings.
  - [ ] Add demo entry for `Button_widget` (`src/miaou_widgets_input/button_widget.{ml,mli}`); show focus/press states.
  - [ ] Add demo entry for `Validated_textbox_widget` (`src/miaou_widgets_input/validated_textbox_widget.ml`); include validation error display.
