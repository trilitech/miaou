# AGENTS.md for miaou

Guidelines for AI agents and contributors working on the miaou repository.

## Project Overview

Miaou is a TUI (Text User Interface) library for OCaml with a state-view-handlers architecture. It provides widgets, layout helpers, and multiple rendering backends for building terminal applications.

**Key distinction:** Miaou is a *library*, not an application. Changes here affect all downstream users.

### Repository Layout

```
src/
├── miaou_core/              # Core page lifecycle, navigation, modals
├── miaou_widgets_display/   # Display widgets (charts, pager, tables, images)
├── miaou_widgets_layout/    # Layout widgets (panes, vsection, file browser)
├── miaou_widgets_input/     # Input widgets (textbox, select)
├── miaou_internals/         # Internal modules (modal renderer, snapshots)
├── miaou_interfaces/        # Capability interfaces (System, Logger, etc.)
├── miaou_helpers/           # Shared utilities (fibers, debounce, helpers)
├── miaou_driver_matrix/     # High-performance diff-based terminal driver
├── miaou_driver_term/       # Lambda-term based terminal driver
├── miaou_driver_sdl/        # SDL2 graphical driver
├── miaou_driver_common/     # Shared driver utilities
├── miaou_runner/            # Multi-backend runner
├── lib_miaou_internal/      # Headless driver for tests
example/                     # Demo application
test/                        # Unit and integration tests
docs/                        # Documentation
```

## Build & Verification

Before any commit:

```bash
dune build          # Verify compilation
dune runtest        # Run tests
dune fmt            # Format code (MUST pass before commit)
```

**Critical:** Every commit must be properly formatted. The pre-commit hook enforces this.

## OCaml Coding Standards

### General Rules
- Interface-first: provide `.mli` before `.ml` for public modules
- Documentation in `.mli` using `(** ... *)` with `@param`, `@return` where helpful
- Prefer immutability and functional style
- Error handling: use `Result` and `Option`, avoid exceptions for control flow

### Forbidden
- `Obj.magic`
- Mutable globals (use proper state management)
- Incomplete pattern matches

### Discouraged
- `List.hd`, `Option.get` (use pattern matching or `_opt` variants)
- Stringly-typed code (use variants/records)
- Partial functions

---

## TUI Architecture (CRITICAL)

### The PAGE_SIG Interface

All pages implement the `PAGE_SIG` interface from `Miaou_core.Tui_page`:

```ocaml
module type PAGE_SIG = sig
  type state                              (* Page's internal state *)
  type msg                                (* Message type for updates *)
  type pstate = state Navigation.t        (* State wrapped with navigation *)
  type key_binding = pstate key_binding_desc

  val init : unit -> pstate
  val view : pstate -> focus:bool -> size:LTerm_geom.size -> string
  val handle_key : pstate -> string -> size:LTerm_geom.size -> pstate
  val handle_modal_key : pstate -> string -> size:LTerm_geom.size -> pstate
  val keymap : pstate -> key_binding list
  val handled_keys : unit -> Keys.t list
  val refresh : pstate -> pstate
  val service_cycle : pstate -> int -> pstate
  val has_modal : pstate -> bool
  (* ... other functions *)
end
```

### Navigation API

Pages use the `Navigation` module for page transitions:

```ocaml
(* Navigate to another page *)
Navigation.goto "page_name" ps

(* Go back *)
Navigation.back ps

(* Quit application *)
Navigation.quit ps

(* Update inner state *)
Navigation.update (fun s -> { s with cursor = s.cursor + 1 }) ps

(* Access inner state in view *)
let view ps ~focus ~size =
  let s = ps.s in  (* Access via .s field *)
  render s.items
```

### Keymap Format

Keymaps use records with `key_binding_desc`:

```ocaml
let keymap ps =
  let kb key action help =
    { Miaou_core.Tui_page.key; action; help; display_only = false }
  in
  [
    kb "Enter" do_action "Perform action";
    kb "Esc" Navigation.back "Back";
    (* display_only for reserved keys shown in help but not dispatched *)
    { key = "?"; action = (fun ps -> ps); help = "Help"; display_only = true };
  ]
```

### View Functions: No Heavy Computation

View functions run on every render tick. Keep them fast:

**CORRECT:**
```ocaml
let view ps ~focus ~size =
  (* Simple string formatting from pre-computed state *)
  let s = ps.s in
  Widgets.render_table s.cached_rows ~cols:size.cols
```

**WRONG:**
```ocaml
let view ps ~focus ~size =
  (* BAD: Complex computation on every render *)
  let rows = List.map expensive_transform (load_data ()) in
  Widgets.render_table rows ~cols:size.cols
```

Move heavy computation to `refresh`, `service_cycle`, or handle it in the application layer.

---

## Driver Architecture

Miaou has three rendering backends:

### Matrix Driver (Default)
- High-performance diff-based rendering
- Uses OCaml 5 Domains: render domain (60 FPS) + main domain (30 TPS)
- Cell-based double buffering with O(1) swap
- Only changed cells written to terminal
- Files: `src/miaou_driver_matrix/`

### Lambda-Term Driver
- Line-based differential rendering
- Single-threaded, simpler architecture
- Good compatibility across terminals
- Files: `src/miaou_driver_term/`

### SDL Driver (Experimental)
- Hardware-accelerated graphics
- Pixel-perfect rendering for charts/images
- Files: `src/miaou_driver_sdl/`

### Driver Selection

Priority: Matrix > SDL > Lambda-Term (configurable via `MIAOU_DRIVER` env var)

---

## Widget Development

### Widget Categories

1. **Display widgets** (`miaou_widgets_display/`): Read-only output (charts, tables, pager)
2. **Layout widgets** (`miaou_widgets_layout/`): Structural containers (panes, vsection)
3. **Input widgets** (`miaou_widgets_input/`): User input (textbox, select)

### Widget Patterns

Widgets typically expose:

```ocaml
(* Creation *)
val create : ... -> t
val open_centered : ... -> t  (* For modal-style widgets *)

(* Rendering *)
val render : t -> focus:bool -> string
val view : t -> focus:bool -> size:LTerm_geom.size -> string

(* State updates *)
val handle_key : t -> key:string -> t
val update : t -> ... -> t

(* Accessors *)
val get_value : t -> 'a
val is_valid : t -> bool
```

### ANSI Output

Widgets return ANSI-formatted strings. Use themed helpers from `Miaou_widgets_display.Widgets`:

```ocaml
let open Miaou_widgets_display.Widgets in
(* Use semantic styles - NOT raw fg/bg with hardcoded numbers *)
let line = themed_emphasis "Title" ^ " - " ^ themed_muted "subtitle" in
let box = render_frame ~title:"Box" ~cols:40 ~body:content () in
```

### Performance

- Use `Buffer` for string concatenation, not `^` or `String.concat`
- Pre-compute expensive layouts in state, not in render
- Use `Helpers.pad_to_width` instead of manual padding

---

## Styling System (CRITICAL)

Miaou uses a **cascading style system** with CSS-like selectors. Understanding this is essential for creating consistent, themeable widgets.

### Two-Layer Styling

1. **Semantic Styles (explicit)** - Widget authors choose these based on content meaning
2. **Contextual Styles (automatic)** - Applied by parent widgets based on position/state

### MANDATORY: Use Semantic Style Functions

**NEVER use hardcoded color numbers.** Always use the themed functions from `Miaou_widgets_display.Widgets`:

```ocaml
(* CORRECT - semantic styling *)
let render_status status msg =
  let open Miaou_widgets_display.Widgets in
  match status with
  | `Error   -> themed_error msg
  | `Warning -> themed_warning msg
  | `Success -> themed_success msg
  | `Info    -> themed_info msg
  | `Normal  -> themed_text msg

(* WRONG - hardcoded colors *)
let render_status status msg =
  match status with
  | `Error -> fg 196 msg    (* BAD: hardcoded red *)
  | `Normal -> fg 255 msg   (* BAD: hardcoded white *)
```

### Available Semantic Functions

| Function | Use Case |
|----------|----------|
| `themed_primary` | Main UI elements, important content |
| `themed_secondary` | Less prominent elements |
| `themed_accent` | Highlights, links, interactive elements |
| `themed_error` | Errors, failures, critical issues |
| `themed_warning` | Cautions, potential problems |
| `themed_success` | Confirmations, completed actions |
| `themed_info` | Neutral information, tips |
| `themed_text` | Normal readable content (DEFAULT for text) |
| `themed_muted` | Secondary info, hints, disabled text |
| `themed_emphasis` | Bold/highlighted content |
| `themed_border` | Widget frames, separators |
| `themed_selection` | Selected items in lists/tables |
| `themed_background` | Primary background |
| `themed_background_alt` | Alternate background (zebra stripes) |

### Contextual Styling (Automatic)

Parent widgets (like `Flex_layout`, `Grid_layout`) automatically set up style context for children. This enables CSS-like rules in themes:

```json
{
  "rules": [
    { "selector": "table-row:nth-child(even)", "style": { "bg": 236 } },
    { "selector": "list-item:selected", "style": { "bg": 24, "bold": true } },
    { "selector": "button:focus", "style": { "fg": 81, "bold": true } }
  ]
}
```

Widgets can access their contextual style with:

```ocaml
(* Apply contextual style (respects :nth-child, :focus, etc.) *)
let content = themed_contextual "my content" in

(* Or get the full style record for complex rendering *)
let ws = current_widget_style () in
let border = ws.border_style in  (* Border.Single, Border.Rounded, etc. *)
```

### When Raw Colors Are Acceptable

Use `fg`/`bg` with numbers ONLY for:
- **Gradients and charts** where you need precise color interpolation
- **SDL rendering** that doesn't use ANSI
- **Legacy code** being migrated (add TODO comment)

```ocaml
(* Acceptable: gradient for progress bar *)
let gradient_colors = [| 21; 27; 33; 39; 45 |] in
let color = gradient_colors.(progress * 4 / 100) in
fg color block
```

### Style Context in Custom Widgets

If your widget renders children, set up the style context:

```ocaml
let render_children children =
  children |> List.mapi (fun i child ->
    Style_context.with_child_context
      ~widget_name:"my-widget-item"
      ~index:i
      ~count:(List.length children)
      (fun () -> child.render ())
  )
```

This enables theme rules like `my-widget-item:nth-child(even)` to work.

---

## Modal System

### Basic Modal Usage

```ocaml
(* Simple modal with default Enter/Esc handling *)
Modal_manager.push_default
  (module My_modal)
  ~init:(My_modal.init ())
  ~ui:{ title = "Modal"; left = None; max_width = None; dim_background = true }
  ~on_close:(fun state outcome ->
    match outcome with
    | `Commit -> (* handle commit *)
    | `Cancel -> (* handle cancel *))
```

### Nested Modals

For modals that open other modals, use `push` with empty `commit_on`/`cancel_on`:

```ocaml
Modal_manager.push
  (module My_modal)
  ~init:(My_modal.init ())
  ~ui:{ ... }
  ~commit_on:[]   (* Handle Enter manually *)
  ~cancel_on:[]   (* Handle Esc manually *)
  ~on_close:(fun state outcome -> ...)
```

### Key Consumption

When closing modals programmatically, prevent key propagation:

```ocaml
Modal_manager.set_consume_next_key () ;
Modal_manager.close_top `Commit
```

---

## Testing

### Headless Driver

Use the headless driver for testing without a terminal:

```ocaml
let test_page () =
  Headless_driver.run_with_keys
    ["Down"; "Down"; "Enter"; "Esc"]
    (module My_page)
```

### Test Organization

- `test/test_*.ml`: Unit tests for specific modules
- Widget tests should cover: creation, key handling, edge cases
- Use `Alcotest` for test framework

---

## Commit Messages

Use conventional commit format:

```
type(scope): description

[optional body]

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ci`

**Scopes:** `core`, `widgets`, `matrix`, `lterm`, `sdl`, `runner`, etc.

Keep the first line under 72 characters.

## Git Hygiene

- **Use pull requests** for significant changes
- Keep diffs minimal and focused on the task
- Don't opportunistically fix unrelated issues
- Never commit secrets or credentials
- Update CHANGELOG.md for user-facing changes
- Bump version in `dune-project` for releases

## Breaking Changes

Miaou is a library with downstream users. For breaking changes:

1. Document in CHANGELOG.md under "Breaking Changes"
2. Provide migration guide with before/after examples
3. Consider deprecation period for major changes
4. Update README.md if public API changes

## Questions or Uncertainty

When unsure about:
- API design that affects downstream users
- Architectural decisions
- Breaking changes
- Performance implications

Ask for confirmation before proceeding.

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `MIAOU_DRIVER` | Backend selection: `matrix`, `term`, `sdl` |
| `MIAOU_ENABLE_MOUSE` | Enable/disable mouse tracking: `0`, `1`, `true`, `false` |
| `MIAOU_OVERLAY` | Show FPS/TPS overlay: `1` |
| `MIAOU_MATRIX_FPS` | Matrix render FPS cap (default: 60) |
| `MIAOU_MATRIX_TPS` | Matrix tick rate (default: 60) |
| `MIAOU_MATRIX_SCRUB_FRAMES` | Periodic full redraw interval (default: 30, `0` disables) |
| `MIAOU_DEBUG` | Enable debug logging: `1` |

## Quick Reference

### Creating a New Page

```ocaml
module My_page : Miaou_core.Tui_page.PAGE_SIG = struct
  type state = { cursor : int; items : string list }
  type msg = unit
  type pstate = state Navigation.t
  type key_binding = pstate Miaou_core.Tui_page.key_binding_desc

  let init () = Navigation.make { cursor = 0; items = [] }

  let view ps ~focus ~size =
    let s = ps.s in
    (* render using s.cursor, s.items *)
    "content"

  let handle_key ps key ~size =
    match key with
    | "j" | "Down" -> Navigation.update (fun s -> { s with cursor = s.cursor + 1 }) ps
    | "k" | "Up" -> Navigation.update (fun s -> { s with cursor = max 0 (s.cursor - 1) }) ps
    | "q" -> Navigation.quit ps
    | _ -> ps

  let keymap ps =
    let kb key action help = { Miaou_core.Tui_page.key; action; help; display_only = false } in
    [ kb "j/Down" (fun ps -> ps) "Move down";
      kb "k/Up" (fun ps -> ps) "Move up";
      kb "q" Navigation.quit "Quit" ]

  let handled_keys () = [Keys.Char "j"; Keys.Char "k"; Keys.Char "q"; Keys.Down; Keys.Up]

  (* Implement remaining PAGE_SIG functions... *)
  let handle_modal_key ps _ ~size = ps
  let update ps _ = ps
  let move ps _ = ps
  let refresh ps = ps
  let service_select ps _ = ps
  let service_cycle ps _ = ps
  let back ps = Navigation.back ps
  let has_modal _ = false
end
```
