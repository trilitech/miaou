# MIAOU Examples

This directory contains comprehensive examples demonstrating MIAOU's widgets and patterns.

## Quick Start

```bash
# Run the demo gallery (terminal)
dune exec -- example/gallery/main.exe

# Run with SDL backend (requires SDL2)
MIAOU_DRIVER=sdl dune exec -- example/gallery/main.exe
```

## Directory Structure

```
example/
├── gallery/      # Demo launcher - browse and launch all demos
├── demos/        # Individual widget demonstrations
├── modals/       # Reusable modal implementations
└── shared/       # Shared utilities for demos
```

## Demo Gallery

The **gallery** provides a unified launcher to explore all demos interactively:

- Use `Up`/`Down` or `j`/`k` to navigate
- Press `Enter` or `Space` to launch a demo
- Press `t` in any demo to view its tutorial
- Press `Esc` to return to the launcher

## Widget Demos

### Input Widgets

| Demo | Description | Documentation |
|------|-------------|---------------|
| [button](demos/button/) | Simple clickable button with Enter/Space activation | [README](demos/button/README.md) |
| [checkbox](demos/checkbox/) | Toggle checkboxes with Space key | [README](demos/checkbox/README.md) |
| [radio](demos/radio/) | Radio button groups for single selection | [README](demos/radio/README.md) |
| [switch](demos/switch/) | On/off toggle switches | [README](demos/switch/README.md) |
| [validated_textbox](demos/validated_textbox/) | Text input with real-time validation | [README](demos/validated_textbox/README.md) |

### Display Widgets

| Demo | Description | Documentation |
|------|-------------|---------------|
| [bar_chart](demos/bar_chart/) | Vertical and horizontal bar charts | [README](demos/bar_chart/README.md) |
| [line_chart](demos/line_chart/) | Line charts with ASCII and Braille rendering | [README](demos/line_chart/README.md) |
| [sparkline](demos/sparkline/) | Compact inline sparkline charts | [README](demos/sparkline/README.md) |
| [braille](demos/braille/) | High-resolution Braille canvas rendering | [README](demos/braille/README.md) |
| [table](demos/table/) | Scrollable tables with cursor navigation | [README](demos/table/README.md) |
| [tree](demos/tree/) | Collapsible tree view widget | [README](demos/tree/README.md) |
| [pager](demos/pager/) | Paginated content display | [README](demos/pager/README.md) |
| [image](demos/image/) | Image rendering with ANSI colors | [README](demos/image/README.md) |
| [qr_code](demos/qr_code/) | QR code generation and display | [README](demos/qr_code/README.md) |
| [description_list](demos/description_list/) | Key-value description lists | [README](demos/description_list/README.md) |

### Layout Widgets

| Demo | Description | Documentation |
|------|-------------|---------------|
| [flex_layout](demos/flex_layout/) | Flexbox-like layout system | [README](demos/flex_layout/README.md) |
| [card_sidebar](demos/card_sidebar/) | Cards and sidebar layouts | [README](demos/card_sidebar/README.md) |
| [layout_helpers](demos/layout_helpers/) | Layout utility functions | [README](demos/layout_helpers/README.md) |

### Navigation Widgets

| Demo | Description | Documentation |
|------|-------------|---------------|
| [breadcrumbs](demos/breadcrumbs/) | Breadcrumb navigation trail | [README](demos/breadcrumbs/README.md) |
| [tabs](demos/tabs/) | Tab-based navigation | [README](demos/tabs/README.md) |
| [link](demos/link/) | Clickable link widgets | [README](demos/link/README.md) |

### Feedback & Status

| Demo | Description | Documentation |
|------|-------------|---------------|
| [spinner_progress](demos/spinner_progress/) | Spinners and progress bars | [README](demos/spinner_progress/README.md) |
| [toast](demos/toast/) | Toast notification system | [README](demos/toast/README.md) |
| [logger](demos/logger/) | Integrated logging display | [README](demos/logger/README.md) |
| [palette](demos/palette/) | Color palette sampler | [README](demos/palette/README.md) |

### Advanced

| Demo | Description | Documentation |
|------|-------------|---------------|
| [system_monitor](demos/system_monitor/) | Real-time system metrics showcase | [README](demos/system_monitor/README.md) |
| [key_handling](demos/key_handling/) | Keyboard input handling patterns | [README](demos/key_handling/README.md) |

## Modal Examples

The `modals/` directory contains reusable modal implementations:

- **textbox_modal.ml** - Text input dialog
- **select_modal.ml** - Selection list dialog
- **file_browser_modal.ml** - File system browser
- **poly_select_modal.ml** - Polymorphic selection (records)

## Shared Utilities

The `shared/` directory provides common infrastructure:

- **demo_page.ml** - Functor that adds tutorial support to demo pages
- **demo_config.ml** - Capability registration for demos
- **tutorial_modal.ml** - Tutorial display modal
- **mock_*.ml** - Mock implementations for testing

## Creating a New Demo

1. Create a directory: `example/demos/my_widget/`
2. Add your page implementation:

```ocaml
(* page.ml *)
module Inner = struct
  let tutorial_title = "My Widget"
  let tutorial_markdown = [%blob "README.md"]

  type state = { (* your state *) ; next_page : string option }
  type msg = unit

  let init () = { (* initial state *); next_page = None }
  let view s ~focus ~size = (* render your widget *)
  let handle_key s key_str ~size = (* handle input *)
  (* ... other PAGE_SIG functions *)
end

include Demo_shared.Demo_page.Make (Inner)
```

3. Create `main.ml`:

```ocaml
let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw ;
  Demo_shared.Demo_config.register_mocks () ;
  let page : Miaou.Core.Registry.page = (module Page : Miaou.Core.Tui_page.PAGE_SIG) in
  ignore (Miaou_runner_tui.Runner_tui.run page)
```

4. Add a `README.md` documenting your widget
5. Add to `dune` file and gallery launcher

## Further Reading

- [Architecture Overview](../docs/architecture.md) - Core components and design
- [Capabilities Guide](../docs/capabilities.md) - Dependency injection system
- [Getting Started](../docs/getting-started.md) - Building your first app
- [Contributing](../CONTRIBUTING.md) - How to contribute
