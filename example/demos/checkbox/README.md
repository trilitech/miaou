# Checkbox widget quick tour

## Keyboard + focus flow
- Terminal, SDL, and headless drivers normalize `"Enter"`/`"Space"`, so the page only forwards those canonical strings to each checkbox.
- `Tab`/`BackTab` are delegated to [`Focus_chain`](../src/miaou_internals/focus_chain.ml), which keeps wrap-around behavior consistent with the other input demos.
- Small demo sets can expose number shortcuts (1/2/3 here) to make toggling instant without moving focus.

## Rendering patterns
- Prefix each checkbox with a dimmed label (e.g., `"1) "`) to hint at shortcuts while keeping widths stable.
- Compose checkboxes with `Flex_layout` when you need multi-column grids—the widget renders a short ANSI snippet so alignment is predictable.
- Highlight the focused entry by dimming the unfocused ones rather than inserting extra glyphs; this keeps reflow minimal when resizing.

## State management & testing
- Keep your model as `Checkbox.t list` plus the focus chain; updates are just `List.mapi` passes that call `Checkbox.handle_key`.
- Lifted state can be serialized for configuration panes, and snapshot tests of `Checkbox.render ~focus:true` are cheap regressions for styling changes.
- Add headless tests that simulate `"Enter"`/`" "` events and Tab rotation so driver tweaks cannot silently break the interaction contract.
