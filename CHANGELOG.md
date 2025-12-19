# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added (2025-12-19)

#### Debounced Validation for Validated Textbox Widget

- **`debounce_ms` parameter** for `Validated_textbox_widget.create` (default: 250ms)
- Validation now defers during rapid typing, running after the debounce period elapses
- Text input remains immediate for responsive UX
- New functions:
  - `tick` - Check and run pending validation (call in `service_cycle`)
  - `flush_validation` - Force immediate validation (useful before form submission)
  - `has_pending_validation` - Check if validation is pending
- Set `debounce_ms=0` to disable debouncing (legacy immediate behavior)

#### Global Render Notification System

- **`Miaou_helpers.Render_notify`** module for widgets to request async UI updates
- `request_render()` - Request a re-render from any widget
- `should_render()` - Check if a render was requested (called by driver)
- Used by validated textbox to trigger validation after debounce period

#### Generic Debounce Module

- **`Miaou_helpers.Debounce`** module for generic debounce timing
- Thread-safe implementation using `Atomic` operations
- Functions: `create`, `mark`, `is_ready`, `clear`, `has_pending`, `check_and_clear`
- Configurable debounce period in milliseconds (default: 250ms)

#### File Browser Performance Optimization

- **Caching for directory listings** - `list_entries_with_parent` now caches results
- **Caching for writable status** - `is_writable` checks are cached per-directory
- Cache automatically invalidates when navigating to a different directory
- Cache manually invalidated after directory creation (`mkdir_and_cd`, inline mkdir)
- New `invalidate_cache()` function for manual cache clearing
- Significantly reduces filesystem calls during rapid Up/Down navigation

### Added (2025-12-17)

- Modal sizing supports dynamic width specs (`Fixed`, `Ratio`, `Clamped`) resolved at render time, including fallback terminal size detection via `/dev/tty` so modals resize with the terminal even when `System` is mocked.

### Changed (2025-12-17)

#### Opam package restructuring for optional SDL

Restructured opam packages to allow terminal-only builds without SDL2 dependency:

- **`miaou-core`**: Standalone core package with all widgets, no SDL dependencies
- **`miaou-driver-term`**: Terminal driver, depends only on `miaou-core`
- **`miaou-driver-sdl`**: SDL driver with SDL2 dependencies (`tsdl`, `tsdl-ttf`, `tsdl-image`)
- **`miaou-widgets-display-sdl`**: SDL-specific widget implementations
- **`miaou-runner`**: Runner with `miaou-driver-sdl` as optional dependency
- **`miaou-tui`**: Meta-package for terminal-only installs (no SDL)
- **`miaou`**: Meta-package for full install (includes SDL)
- **`miaou-core.lib`**: The convenience `Miaou` module (re-exporting Core, Widgets, etc.) is now part of `miaou-core`, available to terminal-only users

Terminal-only users can now: `opam install miaou-tui`

### Breaking Changes (2025-12-17)

- Library public names changed to use package prefixes:
  - `miaou.lib` → `miaou-core.lib`
  - `miaou.core` → `miaou-core.core`
  - `miaou.widgets.display` → `miaou-core.widgets.display`
  - `miaou.driver.term` → `miaou-driver-term.driver`
  - `miaou.driver.sdl` → `miaou-driver-sdl.driver`
  - And similar for other libraries
- `Miaou_widgets_display.Sparkline_widget_sdl` moved to `Miaou_widgets_display_sdl.Sparkline_widget_sdl` (and similar for other SDL widgets)
- `Modal_manager.ui.max_width` (and related helpers) now expects `max_width_spec option` instead of `int option`; wrap existing fixed widths with `Fixed n` or switch to ratio/clamped specs.

### Changed (2025-12-15)

- File pager tail fibers are now scoped to per-page switches and auto-cancel on navigation; terminal, SDL, and headless drivers wrap pages in `Fiber_runtime.with_page_switch` for structured cleanup; `Fiber_runtime` exposes page switch helpers. Adds regression coverage for pager cleanup.
- Pager UX fixes: follow hint only shown when streaming, static pager test added, markdown renderer hides inline backticks and underlines H1 titles.
- Service lifecycle: removing instance files no longer requires a role value.
- File browser navigation: canonicalize paths so parent navigation works from relative paths, scroll the viewport earlier, and tighten Enter navigation checks; demo uses the real filesystem so Enter now changes directories.
- Modal sizing: modal pages now receive the actual modal content geometry (rows/cols) so list widgets don’t scroll into invisible items due to modal height clipping.

### Added (2025-12-11)

#### Input Buffer Draining for Navigation Keys
- **Navigation key coalescing** to prevent scroll lag in list widgets
- When arrow keys are held down and released, consecutive identical navigation events are automatically drained from the input buffer
- Only the final navigation event is processed, making the UI feel more responsive
- Debug logging available with `MIAOU_DEBUG=1` to track drain operations
- Fixes issue where selection continues scrolling for ~0.5s after releasing arrow keys

#### Braille Rendering Mode
- **Unicode Braille patterns** for high-resolution chart rendering (2×4 dots per character cell)
- Braille mode support for `Line_chart_widget`, `Bar_chart_widget`, and `Sparkline_widget`
- `Braille_canvas` module for efficient braille dot manipulation
- 8x higher resolution compared to ASCII mode with only 2x performance cost
- Colored braille output with ANSI styling support
- Performance: 9,259 renders/second for line charts in braille mode

#### Global Keys API
- **Type-safe keyboard handling system** with variant-based key definitions
- Extended `Keys.t` with new key types: `PageUp`, `PageDown`, `Home`, `End`, `Escape`, `Delete`, `Function of int`
- Global key reservations for application-wide actions: `Settings`, `Help`, `Menu`, `Quit`
- Registry validation to prevent key conflicts at page registration time
- `Registry.check_all_conflicts()` for detecting inter-page key conflicts
- `Registry.conflict_report()` for human-readable conflict summaries
- Helper functions: `Keys.is_global_key`, `Keys.get_global_action`, `Keys.show_global_keys`

### Changed (2025-12-10)

#### Performance Optimizations
- **Significant performance improvements** across all widgets (8-24x faster in some cases)
- Replaced `String.concat` with buffer-based rendering throughout codebase
- Introduced `Helpers.pad_to_width` eliminating O(n²) padding allocations
- Optimized pager widget: 9.1s → 1.2s (8x faster)
- Optimized layout widget: 9.0s → 0.8s (12x faster)
- Optimized card_sidebar: 15.1s → 1.0s (15x faster)
- All other widgets show 20-40% performance improvements

### Breaking Changes (2025-12-12)

#### ⚠️ Runtime Migrated from Lwt to Eio

**Impact:** Applications must initialize the Eio runtime before using Miaou.

**What changed:**
- All async/concurrency now uses Eio instead of Lwt
- `cohttp-lwt-unix` replaced with `cohttp-eio`
- Terminal driver uses `Eio_unix.await_readable` for input polling
- Background tasks use `Eio.Fiber` instead of `Thread.create`

**Migration guide:**

1. Wrap your main function in `Eio_main.run` and initialize the runtime:
```ocaml
(* Before *)
let () =
  let page = ... in
  Miaou_runner_tui.Runner_tui.run page

(* After *)
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw;
  let page = ... in
  Miaou_runner_tui.Runner_tui.run page
```

2. Update opam dependencies:
```
- lwt
- cohttp-lwt-unix
+ eio
+ eio_main
+ cohttp-eio
```

**New modules:**
- `Miaou_helpers.Fiber_runtime` — shared Eio runtime management
- `Miaou_widgets_display.File_pager` — Eio-based file tailing pager

#### ⚠️ Pager Widget: Notification Callback Now Per-Instance

**Impact:** Code using `Pager_widget.set_notify_render` must be updated.

**What changed:**
```ocaml
(* OLD - Global callback (removed) *)
Pager_widget.set_notify_render (Some callback);
let pager = Pager_widget.open_lines ~title:"Log" lines in

(* NEW - Per-instance callback *)
let pager = Pager_widget.open_lines ~title:"Log" ~notify_render:callback lines in
```

**Migration guide:**

1. Remove calls to `set_notify_render`
2. Pass `~notify_render` parameter to `open_lines`/`open_text`

**Before:**
```ocaml
let pager = Pager_widget.open_lines ~title:"My Pager" [] in
Pager_widget.set_notify_render (Some render_callback);
```

**After:**
```ocaml
let pager = Pager_widget.open_lines ~title:"My Pager"
              ~notify_render:render_callback [] in
```

**Why this change?**
- Eliminates global mutable state
- Enables multiple independent pagers with different callbacks
- Makes callback lifetime explicit (tied to pager instance)
- Better composability and testability

**Type signature changes:**
- `open_lines : ?title:string -> ?notify_render:(unit -> unit) -> string list -> t`
- `open_text : ?title:string -> ?notify_render:(unit -> unit) -> string -> t`
- `set_notify_render` function removed

**Compiler error you'll see:**
```
Error: Unbound value Pager_widget.set_notify_render
```

### Breaking Changes (2025-12-11)

#### ⚠️ PAGE_SIG Requires `handled_keys` Function

**Impact:** All page implementations must be updated.

**What changed:**
```ocaml
module type PAGE_SIG = sig
  (* ... existing fields ... *)
  
  (* NEW - REQUIRED *)
  val handled_keys : unit -> Keys.t list
end
```

**Migration guide:**

For **minimal migration**, add this to every page:
```ocaml
let handled_keys () = []
```

For **proper key declaration** (recommended):
```ocaml
let handled_keys () = [
  Keys.Char "a";      (* Declare all keys your page handles *)
  Keys.Enter;
  Keys.Up;
  Keys.Down;
  (* ... *)
]
```

**Why this change?**
- Enables compile-time key conflict detection
- Self-documents key bindings
- Foundation for auto-generated help system
- Enables future page registry and navigation features

**Compiler error you'll see:**
```
Error: Signature mismatch:
       The value `handled_keys' is required but not provided
       File "src/miaou_core/tui_page.mli", line 38, characters 2-40:
         Expected declaration
```

**Benefits:**
- ✅ Type-safe key handling (variants, not strings)
- ✅ Prevents global key conflicts automatically
- ✅ Runtime validation catches inter-page conflicts
- ✅ Clear error messages when conflicts occur

## [Previous Releases]

<!-- Previous changelog entries would go here -->
