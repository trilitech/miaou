# Validated Textbox Widget

A textbox with real-time validation feedback and optional debouncing for
expensive validators.

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

## Debounce Support

When validators perform expensive operations (filesystem checks, database
lookups, network calls), use `debounce_ms` to avoid lag:

```ocaml
(* Validate after 300ms of no typing *)
let box = Vtextbox.create
  ~debounce_ms:300
  ~validator:expensive_validator
  ()

(* Disable debounce for instant validation *)
let box = Vtextbox.create
  ~debounce_ms:0
  ~validator:cheap_validator
  ()
```

Before form submission, force validation with `flush_validation`:

```ocaml
let box = Vtextbox.flush_validation box in
if Vtextbox.is_valid box then submit ()
```

## Key Features

- Real-time validation as user types
- Debounced validation for expensive validators (default: 250ms)
- Visual feedback for valid/invalid states
- Custom validator function support
- Placeholder text support
- `has_pending_validation` to check if validation is in progress
- `flush_validation` to force immediate validation

## Demo

This demo shows two textboxes side-by-side:
- **Debounced (250ms)**: Smooth typing, validation runs after you stop
- **Immediate (0ms)**: Noticeable lag with each keystroke

Press Tab to switch focus between them and compare the typing experience.
