# Box Widget

Decorative border around string content with optional title, padding,
and border styling.

## Usage

```ocaml
let box = Box_widget.render
  ~title:"Hello"
  ~style:Single
  ~padding:{ left = 1; right = 1; top = 0; bottom = 0 }
  ~width:30
  "Some content"
```

## Border styles

- **Single**: `+-+` (Unicode: thin lines)
- **Double**: double-line borders
- **Rounded**: rounded corners
- **Heavy**: thick lines
- **Ascii**: `+`, `-`, `|` always

## Features

- Optional title in the top border
- Configurable padding (left, right, top, bottom)
- Fixed height with clipping or padding
- ANSI color for border characters
- Automatic ASCII fallback via `MIAOU_TUI_UNICODE_BORDERS`
- Content truncation with ellipsis
