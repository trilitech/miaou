# Validated Textbox Widget

A textbox with real-time validation feedback.

## Usage

```ocaml
let validate_int s =
  match int_of_string_opt s with
  | Some v when v >= 0 -> Vtextbox.Valid v
  | _ -> Vtextbox.Invalid "Enter a non-negative integer"

let box = Vtextbox.create
  ~title:"Instances"
  ~placeholder:(Some "e.g. 3")
  ~validator:validate_int
  ()
```

## Key Features

- Real-time validation as user types
- Visual feedback for valid/invalid states
- Custom validator function support
- Placeholder text support
