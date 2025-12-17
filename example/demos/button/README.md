# Button Widget

A simple button that can be clicked with Enter or Space.

## Usage

```ocaml
let button = Button.create
  ~label:"Deploy"
  ~on_click:(fun () -> Logs.info (fun m -> m "Clicked"))
  ()
```

## Key Features

- Responds to Enter and Space keys
- Visual feedback on press
- Callback on activation
- Focus styling support
