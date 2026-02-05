# Focus Container

GADT-based heterogeneous widget container with automatic key routing.

## Usage

```ocaml
module FC = Miaou_internals.Focus_container

let counter_ops : counter FC.widget_ops = {
  render = (fun c ~focus -> ...);
  handle_key = (fun c ~key -> ...);
}

let c = FC.create [
  FC.slot "a" counter_ops { value = 0 };
  FC.slot "b" counter_ops { value = 10 };
]

let c', status = FC.handle_key c ~key:"Tab"
```

## Adapters

```ocaml
(* For widgets returning just t *)
let checkbox_ops = FC.ops_simple
  ~render:Checkbox_widget.render
  ~handle_key:Checkbox_widget.handle_key

(* For widgets returning t * bool *)
let button_ops = FC.ops_bool
  ~render:Button_widget.render
  ~handle_key:Button_widget.handle_key
```

## Keys

- **Tab / Shift+Tab**: cycle focus between slots
- **Other keys**: routed to the focused widget

## Features

- Existential GADT packing for heterogeneous widget types
- Automatic Tab/Shift+Tab focus cycling via Focus_ring
- Key routing to focused widget
- Type-safe state extraction via witnesses
- Adapter constructors for common widget signatures
