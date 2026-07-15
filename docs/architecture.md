# MIAOU Architecture

This document describes the core architecture of MIAOU, a terminal/SDL UI framework for OCaml.

## Overview

MIAOU uses a **state-view-handlers** architecture. Each page has immutable state, a pure view function, and key handlers that return new state. Applications are built from:

- **Pages** - Self-contained UI screens with state and rendering
- **Widgets** - Reusable UI components (buttons, tables, charts, etc.)
- **Modals** - Overlay dialogs managed by a stack
- **Capabilities** - Runtime dependency injection for services

```
┌─────────────────────────────────────────────────────┐
│                    Application                       │
├─────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────┐    │
│  │                   Page                       │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐     │    │
│  │  │ Widget  │  │ Widget  │  │ Widget  │     │    │
│  │  └─────────┘  └─────────┘  └─────────┘     │    │
│  └─────────────────────────────────────────────┘    │
│                        │                             │
│  ┌─────────────────────┴───────────────────────┐    │
│  │              Modal Manager                   │    │
│  │  ┌─────────┐  ┌─────────┐                   │    │
│  │  │ Modal 1 │  │ Modal 2 │  ...              │    │
│  │  └─────────┘  └─────────┘                   │    │
│  └─────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────┤
│  Capabilities: System | Logger | Palette | ...      │
├─────────────────────────────────────────────────────┤
│  Driver: Terminal (LambdaTerm) | SDL2               │
└─────────────────────────────────────────────────────┘
```

## Core Components

### Pages (`Miaou.Core.Tui_page`)

A **Page** is the primary UI unit. Each page implements the `PAGE_SIG` signature:

```ocaml
module type PAGE_SIG = sig
  type state                (* Page state *)
  type msg                  (* Message type for updates *)

  val init : unit -> state
  val update : state -> msg -> state
  val view : state -> focus:bool -> size:LTerm_geom.size -> string

  (* Navigation helpers *)
  val move : state -> int -> state
  val refresh : state -> state
  val enter : state -> state
  val back : state -> state

  (* Key handling *)
  val handle_key : state -> string -> size:LTerm_geom.size -> state
  val handle_modal_key : state -> string -> size:LTerm_geom.size -> state
  val keymap : state -> (string * (state -> state) * string) list
  val handled_keys : unit -> Keys.t list

  (* Service interaction *)
  val service_select : state -> int -> state
  val service_cycle : state -> int -> state

  (* Page transitions *)
  val next_page : state -> string option
  val has_modal : state -> bool
end
```

**Key concepts:**

- `view` returns an ANSI-formatted string (the driver handles rendering)
- `handle_key` receives raw key strings like `"Enter"`, `"Up"`, `"a"`
- `next_page` triggers navigation when returning `Some "page_name"`
- `has_modal` tells the driver when a modal is consuming input

### Registry (`Miaou.Core.Registry`)

The **Registry** manages page registration and lookup:

```ocaml
(* Register a page *)
Miaou.Core.Registry.register "my_page" (module My_page : PAGE_SIG)

(* Check existence *)
Miaou.Core.Registry.exists "my_page"

(* Lazy registration (deferred initialization) *)
Miaou.Core.Registry.register_lazy "heavy_page" (fun () ->
  (module Heavy_page : PAGE_SIG)
)
```

**Page navigation flow:**

1. Page's `handle_key` sets `next_page = Some "target_page"`
2. Driver calls `next_page` and gets the target name
3. Driver looks up target in Registry
4. Driver switches to new page, calling its `init`

### Modal Manager (`Miaou.Core.Modal_manager`)

The **Modal Manager** maintains a stack of overlay dialogs:

```ocaml
(* Push a modal *)
Modal_manager.push
  (module My_modal)
  ~init:(My_modal.init ())
  ~ui:{
    title = "My Modal";
    left = Some 20;           (* Optional left offset *)
    max_width = Some (Fixed 60);
    dim_background = true;
  }
  ~commit_on:["Enter"]        (* Keys that trigger commit *)
  ~cancel_on:["Esc"]          (* Keys that trigger cancel *)
  ~on_close:(fun state outcome ->
    match outcome with
    | `Commit -> (* handle confirmation *)
    | `Cancel -> (* handle cancellation *)
  )

(* High-level helpers *)
Modal_manager.alert (module Alert_page) ~init ~title ()
Modal_manager.confirm (module Confirm_page) ~init ~title ~on_result ()
Modal_manager.prompt (module Input_page) ~init ~title ~extract ~on_result ()
```

**Width specifications:**

```ocaml
type max_width_spec =
  | Fixed of int                                (* Exact character width *)
  | Ratio of float                              (* Fraction of terminal width *)
  | Clamped of {ratio: float; min: int; max: int}  (* Bounded ratio *)
```

**Modal stack behavior:**

- Modals are rendered on top of the page content
- The topmost modal receives keyboard input
- Background can be dimmed for visual focus
- Duplicate titles replace existing modals (prevents stacking)

### Widgets

Widgets are composable UI building blocks. They follow a consistent pattern:

```ocaml
(* Create a widget *)
let button = Button_widget.create ~label:"Click me" ~on_click:callback ()

(* Render returns ANSI string *)
let rendered = Button_widget.render button ~focus:true

(* Handle input returns (updated_widget, event_fired) *)
let button', fired = Button_widget.handle_key button ~key:"Enter"
```

**Widget categories:**

| Category | Modules | Purpose |
|----------|---------|---------|
| Input | `Button_widget`, `Checkbox_widget`, `Radio_button_widget`, `Switch_widget`, `Textbox_widget`, `Validated_textbox_widget`, `Select_widget` | User input controls |
| Display | `Table_widget`, `Pager_widget`, `Line_chart_widget`, `Bar_chart_widget`, `Sparkline_widget`, `Image_widget`, `Qr_code_widget` | Data visualization |
| Layout | `Flex_layout`, `Card_widget`, `Sidebar_widget`, `Pane_layout` | Structural containers |
| Navigation | `Tabs_widget`, `Breadcrumbs_widget`, `Link_widget` | Navigation controls |
| Feedback | `Spinner_widget`, `Progress_widget`, `Toast_widget` | Status indicators |

### Flex Layout (`Miaou_widgets_layout.Flex_layout`)

Flexbox-inspired layout system:

```ocaml
let layout = Flex_layout.create
  ~direction:Row
  ~gap:1
  ~children:[
    { basis = Px 20; content = left_panel };
    { basis = Fill; content = main_content };
    { basis = Px 15; content = right_sidebar };
  ]
  ()

let rendered = Flex_layout.render layout ~width:80 ~height:24
```

**Basis types:**

- `Px n` - Fixed pixel/character width
- `Percent f` - Percentage of available space
- `Ratio f` - Ratio relative to siblings
- `Fill` - Take remaining space
- `Auto` - Size to content

### Keys (`Miaou.Core.Keys`)

Key code parsing and matching:

```ocaml
match Miaou.Core.Keys.of_string key_str with
| Some Keys.Enter -> (* handle enter *)
| Some Keys.Up -> (* handle up arrow *)
| Some (Keys.Char "q") -> (* handle 'q' key *)
| Some (Keys.Ctrl 'c') -> (* handle Ctrl+C *)
| None -> (* unknown key *)
| _ -> (* other keys *)
```

**Common key codes:**

- Navigation: `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`
- Actions: `Enter`, `Tab`, `BackTab`, `Backspace`, `Delete`, `Escape`
- Modifiers: `Ctrl 'x'`, `Alt 'x'`
- Characters: `Char "a"`, `Char "A"`, `Char " "`

## Styling (`Miaou_widgets_display.Widgets`)

Helper functions for ANSI styling:

```ocaml
let module W = Miaou_widgets_display.Widgets in

(* Colors *)
W.green "Success"
W.red "Error"
W.yellow "Warning"
W.blue "Info"
W.dim "Secondary text"

(* Formatting *)
W.bold "Important"
W.underline "Link"
W.titleize "Header"

(* Conditional *)
W.if_true condition W.green "text"

(* Box drawing *)
W.box ~title:"Panel" content
```

## Drivers

MIAOU supports multiple rendering backends:

### Terminal Driver (`miaou-driver-term`)

- Uses LambdaTerm for terminal rendering
- Supports 256 colors and Unicode
- Handles terminal resize events
- Works in any terminal emulator

### SDL Driver (`miaou-driver-sdl`)

- Uses SDL2 for graphical rendering
- True-color support
- Mouse input (future)
- Custom fonts via SDL_ttf

**Driver selection:**

```bash
# Terminal (default)
dune exec -- myapp.exe

# SDL
MIAOU_DRIVER=sdl dune exec -- myapp.exe
```

## Package Structure

```
miaou-core          # Core: pages, modals, registry, capabilities
miaou-driver-term   # Terminal driver (LambdaTerm)
miaou-driver-sdl    # SDL2 driver
miaou-runner        # Driver selection and runtime
miaou-tui           # Meta-package: terminal only (no SDL dependency)
miaou               # Full meta-package (includes SDL)
```

**Dependency graph:**

```
miaou-tui ──────────────┬──> miaou-core
                        └──> miaou-driver-term

miaou ──────────────────┬──> miaou-tui
                        └──> miaou-driver-sdl
```

## Application Lifecycle

```
1. Initialize runtime
   └─> Eio_main.run → Eio.Switch.run → Fiber_runtime.init

2. Register capabilities
   └─> System, Logger, Palette, custom services

3. Create initial page
   └─> (module My_page : PAGE_SIG)

4. Run driver
   └─> Runner.run page

5. Event loop (driver manages)
   ├─> Render: page.view → modal overlay → terminal/SDL
   ├─> Input: key event → modal or page.handle_key
   ├─> Navigation: page.next_page → registry lookup → switch
   └─> Resize: update dimensions → re-render
```

## Best Practices

1. **Keep pages focused** - One responsibility per page
2. **Use capabilities** - Don't hardcode dependencies
3. **Compose widgets** - Build complex UIs from simple parts
4. **Handle all keys** - Return state unchanged for unhandled keys
5. **Reset ANSI codes** - Always reset styling at line ends
6. **Test with workflows** - Use `Miaou.Core.Workflow` for testing

## `miaou serve` — process-per-session web supervisor

`miaou serve` (package `miaou-serve`, `src/miaou_serve/`) exposes a MIAOU app
over HTTP/WebSocket for remote/browser access. Chosen architecture:
**process-per-session** — a supervisor process spawns one full-process worker
per session (each an ordinary, unmodified single-controller `Web_driver.run`
app instance), rather than running multiple sessions as concurrent Eio fibers
inside one process. This sidesteps the process-global mutable state shared by
`Modal_manager`/`Registry`/`Fiber_runtime` (none of which is mutex-guarded or
per-instance today) without requiring any of that state to be made
context-aware first — isolation is enforced by the OS process boundary, not
by OCaml-level discipline.

### Slice 0 measurement (worker baseline memory footprint)

Before picking a numeric `max_sessions`/per-worker-limit default (Slice 4),
one worker's baseline RSS was measured running today's `Web_driver.run`
unmodified, via `example/gallery/main_web.exe` (the existing gallery demo,
Matrix driver + a modest widget tree), started with no client connected:

```
$ MIAOU_WEB_PORT=8099 ./_build/default/example/gallery/main_web.exe &
$ grep VmRSS /proc/<pid>/status
VmRSS:      6048 kB
```

**~6 MB RSS per idle worker** (measured on this development machine, x86_64
Linux, OCaml 5.3.0, opam switch `miaou`). This is a baseline figure (no
client attached, no sustained render activity) — it is a lower bound, not a
worst case; Slice 4's numeric `max_sessions`/`setrlimit` defaults should add
headroom rather than budgeting exactly to this number, and the figure should
be re-measured on the actual target deployment host before it is trusted
operationally (container memory limits, different OCaml runtime GC settings,
etc. can all shift it). Recorded here per FR-071 ("measure before inventing a
number"), not fabricated.

### Slice 1 (current) scope

`src/miaou_serve/` currently provides only the CLI/token/auth-default
surface (`Serve_token`, `Serve_policy`, `Serve_config`, `Serve_cli`,
`Miaou_serve.run`) with a single, hardcoded worker — no supervisor,
no process spawning, no per-session Unix-socket proxy yet (Slice 2). See
`src/miaou_serve/serve_run.mli` for the documented Slice 1 bridging
behavior and its known gaps (query-param token instead of path-based
`/s/<token>`, and `Web_driver.run`'s pre-existing all-interfaces bind
regardless of the requested `bind` address).

## See Also

- [Capabilities Guide](capabilities.md) - Dependency injection system
- [Getting Started](getting-started.md) - Build your first app
- [Examples](../example/README.md) - Demo applications
