# Focus Ring

Named-slot focus management with nested scope support.

## Flat ring

```ocaml
let ring = Focus_ring.create ["search"; "filter"; "tree"] in
let focused = Focus_ring.is_focused ring "search" in
let ring, _ = Focus_ring.handle_key ring ~key:"Tab"
```

## Nested scopes

```ocaml
let parent = Focus_ring.create ["sidebar"; "main"] in
let sidebar = Focus_ring.create ["search"; "filter"] in
let main = Focus_ring.create ["editor"; "preview"] in
let sc = Focus_ring.scope ~parent
  ~children:[("sidebar", sidebar); ("main", main)]
```

## Keys

- **Tab / Shift+Tab**: cycle focus within the active ring
- **Enter**: enter a child scope (drill down)
- **Esc**: exit child scope (back to parent)

## Features

- Named slots with `is_focused` for rendering
- Per-slot enable/disable via `set_focusable`
- Wrap-around navigation
- Nested parent/child scopes
