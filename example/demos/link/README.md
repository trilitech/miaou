# Link Widget Demo

Demonstrates clickable links for navigation, including OSC 8 terminal hyperlinks.

## Link Widget

```ocaml
let target = Link.Internal "docs"
let link = Link.create
  ~label:"Open internal page"
  ~target
  ~on_navigate:(fun _ -> ())
```

### Link Types

- `Internal id` - Navigate to internal page
- `External url` - Open external URL

## OSC 8 Hyperlinks

Terminal hyperlinks that render display text as a clickable URL
(like HTML `<a href="...">text</a>`). Supported by kitty, iTerm2,
GNOME Terminal, Windows Terminal, and others.

```ocaml
(* Short display text, full URL on click *)
Widgets.hyperlink ~url:"https://example.com/very/long/path" "example.com"

(* Combine with styled text *)
Widgets.hyperlink ~url:"https://ocaml.org" (Widgets.themed_accent "OCaml")
```

Terminals without OSC 8 support show the display text as plain text
(graceful degradation).

### tmux / screen

Terminal multiplexers (tmux, screen) strip OSC sequences by default.
Miaou auto-detects this and disables hyperlinks. To test, run
**outside** of tmux or set `MIAOU_TUI_HYPERLINKS=on` to force
(requires tmux `set -g allow-passthrough on`).

## Keys

- Enter/Space - Activate link widget
- Esc - Return to launcher
