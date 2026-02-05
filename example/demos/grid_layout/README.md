# Grid Layout

A CSS Grid-style 2D layout engine.

## Track types

- `Px n` — fixed size in cells
- `Fr f` — fractional unit, shares remaining space proportionally
- `Percent p` — percentage of total available space
- `Auto` — equal share of remaining space (same as `Fr 1.`)
- `MinMax (min, max)` — clamped between min and max

## Placement

Place children at `(row, col)` with optional row/column spans.

```ocaml
let grid = Grid_layout.create
  ~rows:[Px 3; Fr 1.; Px 1]
  ~cols:[Px 20; Fr 1.]
  ~col_gap:1
  [
    span ~row:0 ~col:0 ~row_span:1 ~col_span:2 render_header;
    cell ~row:1 ~col:0 render_sidebar;
    cell ~row:1 ~col:1 render_main;
    span ~row:2 ~col:0 ~row_span:1 ~col_span:2 render_footer;
  ]
```

## Features

- Row and column gaps
- Padding around container
- Cell spanning (row_span, col_span)
- Fractional and percentage track sizing
- MinMax clamped tracks
