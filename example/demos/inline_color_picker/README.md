# Inline Color Picker

A 16-colour ANSI palette picker that combines two features:

1. `Miaou_widgets_layout.Responsive.pick` chooses the swatch grid layout based
   on the current terminal width:
   - **Wide** (>= 60 cols) — an 8 x 2 grid (8 columns, 2 rows).
   - **Narrow** (< 60 cols) — a 4 x 4 grid.
2. The provided `run.sh` launches the demo in **inline mode**
   (`MIAOU_INLINE_MODE=1`), so the final swatch strip stays in your scrollback
   after quit.

## Running

```sh
./example/demos/inline_color_picker/run.sh
```

That is equivalent to:

```sh
MIAOU_DRIVER=matrix MIAOU_INLINE_MODE=1 \
  dune exec example/demos/inline_color_picker/main.exe
```

## Keys

- `Left` / `Right` / `Up` / `Down` (or `h`/`l`/`k`/`j`) — move cursor.
- `Enter` or `Space` — confirm selection.
- `r` — reset the picker.
- `q` or `Esc` — quit.
- `t` — open this tutorial.

The selected swatch's ANSI index and human-readable name are shown beneath
the grid.

The demo also runs cleanly in alt-screen mode (e.g., from the gallery
launcher); the responsive grid swap still works there. Inline mode is the
launcher's contribution, not the page's.
