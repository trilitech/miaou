# Table Widget Demo

Displays tabular data with cursor navigation and selection.

## Usage

```ocaml
let columns = [
  {Table.header = "Name"; to_string = (fun (n, _, _) -> n)};
  {header = "Score"; to_string = (fun (_, s, _) -> s)};
  {header = "Status"; to_string = (fun (_, _, st) -> st)};
]
let rows = [("Alice", "42", "Active"); ("Bob", "7", "Inactive")]
let table = Table.create ~columns ~rows ()
```

## Key Features

- Arrow keys for navigation
- Enter to select/log current row
- Customizable columns with headers
- Row highlighting for current selection
