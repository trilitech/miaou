# Link Widget Demo

Demonstrates clickable links for navigation.

## Usage

```ocaml
let target = Link.Internal "docs"
let link = Link.create
  ~label:"Open internal page"
  ~target
  ~on_navigate:(fun _ -> ())
```

## Link Types

- `Internal id` - Navigate to internal page
- `External url` - Open external URL

## Keys

- Enter/Space - Activate link
- Esc - Return to launcher
