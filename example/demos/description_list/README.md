# Description List Demo

Displays key-value pairs in a structured list format.

## Usage

```ocaml
let items = [
  ("Name", "Alice");
  ("Role", "Developer");
  ("Location", "Remote");
]
let widget = Description_list.create ~title:"Profile" ~items ()
```

## Features

- Title header
- Key-value alignment
- Long value wrapping
