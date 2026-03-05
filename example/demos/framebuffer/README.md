# Framebuffer & Octant Charts Demo

This demo showcases pixel-level rendering in the terminal using the new
`Framebuffer_widget` and the `Octant` chart rendering mode.

## What's New

### Framebuffer Widget

A mutable RGB pixel buffer that renders to the terminal using the best
available sub-pixel mode, selected automatically via `Terminal_caps.detect()`:

```
Sixel → Octant → Sextant → Half_block → Braille
```

- **Octant** (Unicode 16, U+1CD00): 2×4 sub-pixels per cell with fg+bg color
- **Sextant** (Unicode 13, U+1FB00): 2×3 sub-pixels per cell with fg+bg color
- **Half_block** (▀/▄): 1×2 pixels per cell — universal fallback
- **Braille**: monochrome 2×4 dots

Override the auto-detection with `MIAOU_PIXEL_MODE=octant|sextant|half_block|braille`.

### Octant Charts

All three chart widgets (sparkline, bar chart, line chart) now support
`~mode:Octant`, which provides the same 2×4 resolution as Braille but with
**per-series color** instead of monochrome dots.

## Keys

- **m** — Cycle framebuffer render mode (Octant → Sextant → Half_block → Braille → Octant…)
- **c** — Cycle chart mode (ASCII → Braille → Octant → ASCII…)
- **Space** — Regenerate random pixel data
- **Esc** — Return to launcher
