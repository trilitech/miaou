# Layout Helpers Demo

Demonstrates Pane_layout and Vsection layout widgets.

## Pane Layout

Split content into left/right panes with configurable ratios.

```ocaml
let pane = Pane.create
  ~left:"Left content"
  ~right:"Right content"
  ~left_ratio:0.45
  ()
```

## Vsection Layout

Create sections with header, footer, and child content areas.

```ocaml
Vsection.render
  ~size
  ~header:["Header"]
  ~footer:["Footer"]
  ~child:(fun inner -> "Child content")
```
