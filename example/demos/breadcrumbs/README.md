# Breadcrumbs Widget Demo

Navigation breadcrumbs for hierarchical navigation.

## Keys

- ←/→ - Move between crumbs
- Home/End - Jump to first/last crumb
- Enter - Activate current crumb
- x - Test bubbled key handling
- Esc - Return to launcher

## Usage

```ocaml
let trail = Breadcrumbs.make [
  Breadcrumbs.crumb ~id:"root" ~label:"Root" ();
  Breadcrumbs.crumb ~id:"cluster" ~label:"Cluster" ();
  Breadcrumbs.crumb ~id:"node" ~label:"Node-01" ();
]
```
