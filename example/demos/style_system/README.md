# Style System Demo

This demo showcases the cascading style system in Miaou.

## Highlights

- Semantic styles: `themed_text`, `themed_error`, `themed_success`, etc.
- Contextual styles: background changes via `flex-child:nth-child(...)` rules
- Theme switching at runtime

## Controls

- `1` / `2` / `3`: Switch theme (dark / light / high-contrast)
- `Left` / `Right`: Move focus across tiles
- `Esc`: Return to launcher

## Theme File

The demo also ships a CSS-like theme file you can edit live:

- `example/demos/style_system/theme.json`

If the file exists, the demo will load it as the **dark** theme.
