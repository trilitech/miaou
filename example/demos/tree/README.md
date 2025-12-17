# Tree Widget Demo

Displays hierarchical JSON data as a tree structure.

## Usage

```ocaml
let json = Yojson.Safe.from_string "{\"key\": \"value\"}"
let node = Tree.of_json json
let tree = Tree.open_root node
```

## Key Features

- JSON visualization
- Expandable/collapsible nodes
- Nested structure display
