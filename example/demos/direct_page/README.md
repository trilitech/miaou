# Direct Page

Direct_page lets you build Miaou pages with just 3 functions instead
of the 13 required by PAGE_SIG.  Navigation uses OCaml 5 algebraic
effects -- call `navigate`, `go_back`, or `quit` from anywhere.

## Before / After

**Traditional PAGE_SIG** (20+ lines):

```ocaml
module Counter : PAGE_SIG = struct
  type state = int
  type msg = unit
  type pstate = state Navigation.t
  type key_binding = state Tui_page.key_binding_desc
  let init () = Navigation.make 0
  let update ps _ = ps
  let view ps ~focus:_ ~size:_ = string_of_int ps.Navigation.s
  let handle_key ps key ~size:_ = match key with
    | "Up" -> Navigation.update (fun n -> n+1) ps
    | "q"  -> Navigation.quit ps
    | _ -> ps
  let handle_modal_key ps _ ~size:_ = ps
  let move ps _ = ps
  let refresh ps = ps
  let service_select ps _ = ps
  let service_cycle ps _ = ps
  let back ps = Navigation.back ps
  let keymap _ = []
  let handled_keys () = []
  let has_modal _ = false
end
```

**Direct_page** (8 lines):

```ocaml
module Counter = Direct_page.Make (Direct_page.With_defaults (struct
  type state = int
  let init () = 0
  let view n ~focus:_ ~size:_ = string_of_int n
  let on_key n key ~size:_ = match key with
    | "Up" -> n + 1
    | "q"  -> Direct_page.quit () ; n
    | _    -> n
end))
```

## Required functions

| Function | Purpose |
|----------|---------|
| `init`   | Return initial state (plain value, no `Navigation.make`) |
| `view`   | Render state to string |
| `on_key` | Handle key press, return new state |

## Optional overrides

Override these by using `include With_defaults(...)` then redefining:

| Function | Default | Purpose |
|----------|---------|---------|
| `keymap` | `[]` | Key/help pairs for the help overlay |
| `refresh` | identity | Called on each tick for background updates |
| `has_modal` | `false` | Whether a modal is currently active |
| `on_modal_key` | identity | Handle keys when a modal is active |

## Navigation effects

Call these from `on_key`, `on_modal_key`, or `refresh`:

```ocaml
Direct_page.navigate "page_name"   (* go to a named page *)
Direct_page.go_back ()             (* return to previous page *)
Direct_page.quit ()                (* exit the application *)
```

Effects are composable -- call them from helper functions without
threading return types:

```ocaml
let confirm_and_go state =
  if state.confirmed then Direct_page.navigate "next" ;
  state

let on_key state key ~size:_ = match key with
  | "Enter" -> confirm_and_go state
  | _ -> state
```

## Testing

Use `Direct_page.run` to test `on_key` logic directly:

```ocaml
let state', nav = Direct_page.run (fun () ->
  My_page.on_key initial_state "q" ~size)
in
assert (nav = Some `Quit)
```
