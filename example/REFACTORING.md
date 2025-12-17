# Demo Refactoring - Work in Progress

This document describes the ongoing refactoring to split the monolithic `demo_lib.ml` into individual demo directories.

## Current State

### Completed
- Directory structure created: `demos/`, `gallery/`, `shared/`, `modals/`
- Shared utilities moved to `shared/`:
  - `demo_config.ml` - Common config (launcher_page_name, register_mocks)
  - `tutorial_modal.ml` - Tutorial display system
  - `mock_*.ml` - Mock system implementations
  - `system_metrics.ml` - System metrics utilities

### Extracted Demos (fully working)
Each has its own directory with `page.ml`, `main.ml`, `README.md`, and `dune`:
- `demos/checkbox/` → `miaou.checkbox-demo`
- `demos/radio/` → `miaou.radio-demo`
- `demos/switch/` → `miaou.switch-demo`
- `demos/button/` → `miaou.button-demo`
- `demos/validated_textbox/` → `miaou.validated_textbox-demo`
- `demos/sparkline/` → `miaou.sparkline-demo`
- `demos/key_handling/` → `miaou.key_handling-demo`

### Legacy (still working)
- `demo_lib.ml` - Contains all demos (including ones being extracted)
- `demo_tui.ml` / `demo_sdl.ml` - Original launchers using demo_lib.ml
- `miaou.demo` / `miaou.demo-sdl` - Gallery executables

## How to Extract a Demo

### 1. Create the directory structure
```bash
mkdir -p example/demos/<demo_name>
```

### 2. Create README.md
Extract the `tutorial_markdown` content from demo_lib.ml, or create a basic description:
```markdown
# Demo Name

Description of what this demo shows.

## Usage
...

## Key Features
- Feature 1
- Feature 2
```

### 3. Create page.ml
```ocaml
let tutorial_markdown = [%blob "README.md"]

(* Copy the demo module from demo_lib.ml *)
(* Replace: *)
(*   launcher_page_name -> Demo_shared.Demo_config.launcher_page_name *)
(*   show_tutorial_modal -> Demo_shared.Tutorial_modal.show ~title:"..." ~markdown:tutorial_markdown () *)

type state = ...
type msg = ...
let init () = ...
let view s ~focus ~size = ...
(* ... rest of PAGE_SIG implementation ... *)
```

### 4. Create main.ml
```ocaml
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  Demo_shared.Demo_config.register_mocks () ;
  Demo_shared.Demo_config.ensure_system_capability () ;
  let page : Miaou.Core.Registry.page = (module <Demo_name>_demo.Page : Miaou.Core.Tui_page.PAGE_SIG) in
  ignore (Miaou_runner_tui.Runner_tui.run page)
```

### 5. Create dune
```scheme
(library
 (name <demo_name>_demo)
 (modules page)
 (preprocess (pps ppx_blob))
 (preprocessor_deps (file README.md))
 (libraries demo_shared miaou miaou.lib_miaou_internal))

(executable
 (name main)
 (public_name miaou.<demo_name>-demo)
 (package miaou)
 (modules main)
 (libraries <demo_name>_demo miaou.runner.tui miaou.helpers eio_main))
```

### 6. Build and test
```bash
dune build example/demos/<demo_name>/main.exe
dune exec miaou.<demo_name>-demo
```

## Remaining Demos to Extract

From demo_lib.ml:
- [ ] table
- [ ] palette
- [ ] logger
- [ ] pager
- [ ] tree
- [ ] layout_helpers
- [ ] flex_layout
- [ ] link
- [ ] breadcrumbs
- [ ] tabs
- [ ] toast
- [ ] card_sidebar
- [ ] spinner_progress
- [ ] line_chart
- [ ] bar_chart
- [ ] description_list
- [ ] qr_code
- [ ] image
- [ ] system_monitor

Modal demos (in modals/ directory, no standalone launcher):
- [ ] textbox_modal
- [ ] select_modal
- [ ] file_browser_modal
- [ ] poly_select_modal

## Final Steps (after all demos extracted)

1. Create `gallery/launcher.ml` that imports all extracted demo modules
2. Create `gallery/main_tui.ml` and `gallery/main_sdl.ml`
3. Update `example/dune` to use gallery instead of demo_lib
4. Remove legacy files: `demo_lib.ml`, `demo_tui.ml`, `demo_sdl.ml`
5. Move braille demo to `demos/braille/`

## Building

```bash
# Build everything
dune build

# Build specific standalone demo
dune build example/demos/checkbox/main.exe

# Run standalone demo
dune exec miaou.checkbox-demo

# Run legacy gallery
dune exec miaou.demo
```
