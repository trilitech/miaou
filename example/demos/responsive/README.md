# Responsive Layout Demo

Demonstrates `Miaou_widgets_layout.Responsive.pick`, choosing between several
dashboard layouts at render time based on the current terminal width.

The page renders a four-tile dashboard. Each tile is a labelled coloured box.
The arrangement of the tiles changes as you resize the terminal:

- **Wide**  (>= 120 cols) — four tiles side-by-side in a single row.
- **Medium** (60–119 cols) — a 2 x 2 grid.
- **Narrow** (< 60 cols)  — a single stacked column.

The current breakpoint label is shown at the top of the page.

## Keys

- `Esc` — return to the launcher.
- `t` — open this tutorial.

## How it works

```ocaml
let layout =
  Responsive.pick
    ~width:size.cols
    ~default:wide_layout
    [
      { max_width = 59; layout = narrow_layout };
      { max_width = 119; layout = medium_layout };
    ]
```

Breakpoints are walked in order, and the first one whose `max_width` is at
least the current width wins. If none match, `default` is returned.
