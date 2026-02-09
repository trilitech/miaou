# Canvas

The **Canvas** module provides a driver-agnostic, cell-level 2D surface
for TUI rendering.

## Key Concepts

- A canvas is a mutable grid of **cells**, each holding a UTF-8 grapheme
  and a **style** (foreground, background, bold, dim, underline, reverse).
- Drawing operations silently clip to bounds — no exceptions.
- `blit` composites one canvas onto another (spaces are transparent).
- `to_ansi` renders the canvas to a string with minimal SGR escape codes.

## Drawing Primitives

```ocaml
Canvas.draw_text  c ~row ~col ~style "Hello"
Canvas.draw_hline c ~row ~col ~len:10 ~char:"─" ~style
Canvas.draw_vline c ~row ~col ~len:5  ~char:"│" ~style
Canvas.draw_box   c ~row ~col ~width:20 ~height:8 ~border:Single ~style
Canvas.fill_rect  c ~row ~col ~width:10 ~height:3 ~char:"░" ~style
```

## Border Styles

Five built-in styles: `Single`, `Double`, `Rounded`, `Heavy`, `Ascii`.

## Composition

```ocaml
(* Transparent blit — spaces don't overwrite *)
Canvas.blit ~src:overlay ~dst:base ~row:2 ~col:5

(* Opaque blit — copies everything including spaces *)
Canvas.blit_all ~src:overlay ~dst:base ~row:2 ~col:5
```

## Controls

- **b**: Cycle border style
- **c**: Cycle color scheme
- **t**: Open this tutorial
- **Esc**: Return to launcher
