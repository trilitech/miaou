# Module Catalog: pager-improvements

Milestone tracking for pager widget improvements and tail-follow functionality.

## Core Modules

### `Pager_widget` (src/miaou_widgets_display/pager_widget.ml[i])

**Purpose:** Scrollable text pager with search, follow-mode, and streaming support for log viewing.

**Key types:**
- `t` - Mutable pager state with lines buffer, offset, follow mode, search state, input mode
- `json_streamer` - Incremental JSON pretty-printer for streaming responses

**Key functions:**
- `open_lines/open_text` - Create pager from content
- `append_lines[_batched]` - Add content (immediate or batched with rate limiting)
- `start/stop_streaming` - Control streaming UI (spinner, follow mode)
- `flush_pending_if_needed` - Flush batched appends at controlled rate
- `render[_with_size]` - Generate frame with search highlighting and status
- `handle_key` - Process navigation, search, and control keys (mutates state in-place)
- `json_streamer_*` - Incremental JSON formatting for streaming APIs

**Recent changes:**
- Fixed functional/imperative style mixing - all key handlers now mutate in-place
- Fixed follow-mode resume logic to detect scrolling to/past bottom during streaming
- Added search input mode with inline editing and cursor
- Moved notify_render from global to per-instance field (breaking change)
- Batched append now uses per-pager notification callback

**Gardening notes:**
- State is mutable with imperative updates - consistent style now enforced
- No global state - notification callback is per-pager instance
- Could extract search/input handling to separate module if it grows
- JSON streamer is pager-specific but could be generalized if needed elsewhere

### `Widgets` (src/miaou_widgets_display/widgets.ml)

**Purpose:** Shared UI primitives and helpers for rendering frames, text styling, and layout.

**Key functions:**
- `highlight_matches` - Search term highlighting with ANSI escape preservation
- `wrap_text` - Text wrapping that preserves ANSI color codes
- `render_frame` - Frame rendering with title, header, body, footer
- `footer_hints_wrapped_capped` - Keyboard hint rendering with wrapping
- `fg/bg/dim/bold` - ANSI styling helpers

**Recent changes:**
- `highlight_matches` enhanced to preserve ANSI codes during highlighting

**Gardening notes:**
- Helper functions are well-contained
- Could benefit from organizing into sub-modules (Styling, Layout, Text) if it grows

### `File_pager` (src/miaou_widgets_display/file_pager.ml[i])

**Purpose:** File-backed pager with follow-mode (inotify/polling) that streams file changes into `Pager_widget`.

**Key types/functions:**
- `tail_state` - Tracks file position, polling interval, strategy (`Inotify` | `Polling`), and closed flag for idempotent cleanup.
- `open_file ~follow ~poll_interval` - Load file into a pager and start tailing when requested.
- `close` - Idempotent stop; cancels tail fiber, closes inotify/polling resources, stops streaming.
- Internal: `start_tail_watcher`, `tail_loop`, `read_new_lines` for background file watching.

**Recent changes:**
- Tail cleanup made idempotent to avoid EBADF when both the tail fiber and caller close inotify FDs.
- Tail fibers are scoped to per-page switches (see drivers) for automatic cancellation on navigation.
- Regression tests cover page-switch cancellation and double-close safety.

**Gardening notes:**
- `start_inotify` is currently a stub; reintroduce inotify carefully with consistent resource ownership.
- Keep tail closure captures minimal to avoid stale references when cancelling; prefer idempotent cleanup guards.
- Consider exposing per-page switch utilities in a helper to reduce driver duplication.

## Demo/Test Modules

### `Pager_demo_page` (example/demo_lib.ml)

**Purpose:** Interactive pager demo with live file tailing for testing.

**Key components:**
- `tail_state` - File position tracking with inotify/polling strategy
- `start_tail_watcher` - Background thread for continuous file monitoring
- `start_temp_writer` - Demo line generator (200ms intervals)
- `refresh` - Frame callback to flush pending lines (background thread handles reading)

**Recent changes:**
- Separated concerns: background thread handles all file I/O, refresh only flushes
- Removed competing file reads between refresh and tail_watcher
- Removed forced follow=true that fought user navigation
- Sped up demo append rate from 1s to 200ms for better testing

**Gardening notes:**
- Clean separation between background I/O and UI refresh
- Tail infrastructure is demo-specific but shows proper pattern for streaming widgets

## Gardening Opportunities

1. ✅ **Pager state mutation consistency** - Fixed in df88f6c
2. ✅ **Per-instance notification callback** - Completed in e265ed7
3. **Widget helpers organization** - Consider sub-modules if Widgets grows beyond ~500 LOC
4. **Search functionality extraction** - If search gets more complex, extract to Pager_search module

## Streaming Pattern Reference

The pager demo demonstrates a clean pattern for streaming content updates:

### Architecture
```
┌─────────────────────────────────────────┐
│ Background Thread                       │
│  ├─ Monitor source (file, socket, etc.) │
│  ├─ Read new data                       │
│  └─ pager.append_lines_batched(lines)   │
│      └─ notify_render() if callback set │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ Main UI Thread                          │
│  ├─ Receives render notification        │
│  ├─ pager.flush_pending_if_needed()     │
│  └─ pager.render()                      │
└─────────────────────────────────────────┘
```

### Key Components

1. **Background thread** reads source and appends:
   ```ocaml
   let rec poll_loop () =
     let new_lines = read_source () in
     Pager.append_lines_batched pager new_lines;
     Unix.sleepf interval;
     poll_loop ()
   ```

2. **Notification callback** requests UI refresh:
   ```ocaml
   let notify_render () =
     (* Set flag, send event, or wake event loop *)
     render_requested := true
   ```

3. **Pager creation** connects the callback:
   ```ocaml
   let pager = Pager.open_lines ~title:"Stream"
                 ~notify_render initial_lines
   ```

4. **UI refresh** flushes and renders:
   ```ocaml
   let refresh () =
     Pager.flush_pending_if_needed pager;
     let output = Pager.render ~win pager ~focus:true in
     display output
   ```

### Benefits
- **Responsive**: Notification wakes UI immediately when data arrives
- **Rate-limited**: Batched appends prevent render flood
- **Decoupled**: Source reading independent of UI rendering
- **Reusable**: Pattern works for files, sockets, APIs, message queues

See `Pager_demo_page` for complete implementation with inotify/polling fallback.

## Coverage Notes

- Pager_widget has comprehensive `.mli` with usage examples
- Test coverage via test_pager_extra.ml (100 new LOC)
- Demo provides manual testing with real streaming behavior
