🐱 MIAOU

MIAOU is a playful TUI library for OCaml built on the Model–View–Update (MVU) pattern.

Why the name?

It’s an acronym: Model, Interface, Application, OCaml, Update.

It’s also the French way of writing a cat’s meow—a nod to OCaml’s French roots.

And like a cat, it’s light, curious, and perfectly at home on your terminal. 🐾

## Project status & ownership

- **Owner / maintainer:** Nomadic Labs (<contact@nomadic-labs.com>)
- **Temporary home:** https://gitlab.com/mbourgoin/miaou (private at first, to be opened later)
- **License:** MIT (SPDX: MIT) with Nomadic Labs copyright notices in every source file

MIAOU started as an experiment in “cat-herded” development: code is authored by LLM/agent assistants under human direction. The two immediate goals are:

1. Explore what happens when assistants build an entire real-world library.
2. Ship a high-quality, easy-to-use TUI foundation for OCaml applications (installers, dashboards, service consoles, etc.).

Features at a glance
--------------------
- MVU-inspired page lifecycle with modal support and capability injection
- Ready-to-use widgets: tables, file browsers, pagers, modal forms, panes, text boxes, palette helpers, etc.
- Lambda-Term driver plus a headless driver for tests/CI
- Example demo wiring mocked capabilities so you can explore everything quickly

Backends
--------

MIAOU currently relies on λ-term as its primary backend. It exposes a small driver/backend interface so alternative low-level backends can be plugged in later.

Quick start — build & depend
----------------------------

Prerequisites

- OCaml (5.3.x recommended) and opam
- dune (>= 3.12)
- the runtime dependencies below (opam will install them)

Build in this repository (preferred):

```sh
# Install deps, build, test, format
make deps
make build
make test          # runs repo tests
# optional: make fmt
```

Alternative (direct dune):

```sh
eval $(opam env)
dune build @all
dune runtest
```

Using from another project
--------------------------

This repository exposes an umbrella library plus split sub-libraries with the following dune public names and module namespaces:

- Umbrella library: `miaou` exposing `Miaou.Core`, `Miaou.Widgets.{Display,Layout,Input}`, `Miaou.Internal`, and `Miaou.Net`.
- Direct sub-libraries (optional if you don't want the umbrella):
	- `miaou.core`       → module namespace `Miaou_core`
	- `miaou.widgets.display` → `Miaou_widgets_display`
	- `miaou.widgets.layout`  → `Miaou_widgets_layout`
	- `miaou.widgets.input`   → `Miaou_widgets_input`
	- `miaou.internals`  → `Miaou_internals`

Example dune stanza (consumer project):

```lisp
(library
 (name my_app)
 ;; simplest: depend on umbrella and use Miaou.* namespaces
 (libraries miaou)
)
```

Then in OCaml:

```ocaml
(* Prefer the umbrella to keep imports tidy *)
open Miaou

(* Example: use the layout Pane splitter and the display Widgets helpers *)
module Pane = Miaou.Widgets.Layout.Pane
module W    = Miaou.Widgets.Display.Widgets
```

Dependencies
------------

The core runtime dependencies used by MIAOU (also declared in `miaou.opam`):

- cohttp
- cohttp-lwt-unix
- lambda-term
- lwt
- rresult
- str
- uri
- yojson
- alcotest (test dependency)

Install via opam (example):

```sh
opam install --deps-only -y .
```

Minimal usage example
---------------------

This repository ships an `example/` directory with mocked capabilities plus a driver bridge demonstrating the public API. Build it with dune and run `dune exec miaou.demo` to see the widgets in action. For your own app, create a tiny program that registers a `Tui_page` and invoke the driver — see the library modules under `miaou_core` for the public API.

Examples
--------

```sh
dune exec miaou.demo           # launches the capability-mocked demo
dune exec -- miaou.demo --help # show CLI options if you add any
```

The demo registers mock System/Logger/Service_lifecycle implementations so you can inspect how capabilities are wired before integrating Miaou into your own driver.

Running tests
-------------

From the repo root:

```sh
make test
# or: eval $(opam env) && dune runtest
```

The `test/` directory contains widget/layout regression tests plus a synthetic adaptive page exercised through the headless driver shipped in `lib_miaou_internal`. You can also run the install rule (`dune build @install`) to ensure opam packaging stays healthy.

Capabilities
------------

Miaou relies on a capability system so the driver (or host application) can decide how to perform side-effects. Before launching the UI you should register implementations for the following interfaces (see `miaou_interfaces/`):

- `Miaou_interfaces.System` — file-system and process helpers (required by file browsers, log viewers, etc.).
- `Miaou_interfaces.Logger` — sink for structured log output from widgets and the driver (optional but recommended).
- `Miaou_interfaces.Service_lifecycle` — used by the service manager widgets; provide stubs if your app does not manage OS services.
- `Miaou.Net` — HTTP capability used by network-aware widgets; the repo ships a simple `cohttp_lwt_unix` provider (`cohttp_net.ml`).

Register your implementations via `Miaou_interfaces.Capability.set` (or the helper `register` functions exposed by each interface) before calling `Miaou.Core.Tui_driver.start`. Tests use the mock implementations in `example/` for reference.

Configuration & options
-----------------------

-- Logging/debug: enable debug output by setting `MIAOU_TUI_DEBUG_MODAL=1` (used by modal manager internals).
- Backend selection: MIAOU uses λ-term by default; the driver/backend interface makes alternate backends possible.

Debugging & environment variables
---------------------------------

- `MIAOU_TUI_DEBUG_MODAL=1` — verbose modal-manager logging (also honored by `Miaou_internals.Modal_renderer`).
- `MIAOU_TUI_UNICODE_BORDERS=false` — force ASCII borders if your terminal font lacks box-drawing glyphs.
- `MIAOU_TUI_ROWS` / `MIAOU_TUI_COLS` — override terminal geometry for the Lambda-Term driver during development.
- `MIAOU_TEST_ALLOW_FORCED_SWITCH=1` — enable the headless driver's `__SWITCH__:` escape hatch (useful in scripted tests).

Troubleshooting
---------------

- Package scope errors from dune: if you see errors about unknown packages when changing public names, ensure `(package (name miaou))` exists in `dune-project` and `miaou.opam` is present.
- Missing dependencies: run `opam install --deps-only .` from the repo root or `eval $(opam env)` before building.
- Dangling internal path / cmi errors during large refactors: update and compile libraries in small batches (fix one library, run `dune build`, then continue).

Design notes
------------

MIAOU is intentionally experimental. The library splits responsibilities into three conceptual parts:

- **Core:** Public API, page lifecycle, modal manager, driver-facing helpers. Now includes a robust capability system for abstracting side-effects.
- **Widgets:** Reusable UI widgets (tables, textboxes, selectors, file browser). Many widgets have been generalized and improved (e.g., `File_browser_widget` with advanced path editing).
- **Internals:** Renderer and implementation details that are not part of the public API.

This split helps enforce that only the driver composes overlays and that pages cannot directly call internal renderer APIs.

Status & Contributions
----------------------

MIAOU is early, experimental, and a little chaotic—like a kitten learning to climb curtains.

Pull requests are not welcome (yet). The whole point of the experiment is to practice cat-herded development: changes are coordinated by agents/LLMs under human direction.

Issues, bug reports, and feature requests are very welcome. If you spot something odd or dream of a feature, please open an issue in the project's tracker.

License
-------

MIAOU is released under the MIT License (SPDX: MIT).
The repository follows the project's licensing guidance: source-file license headers should attribute ownership to "Nomadic Labs <contact@nomadic-labs.com>" where appropriate. See `LICENSE.md` for full text.

Versioning & releases
---------------------

Miaou follows semantic versioning (MAJOR.MINOR.PATCH). Cut releases by tagging (`git tag vX.Y.Z && git push origin vX.Y.Z`), then use `dune-release tag && dune-release distrib && dune-release opam submit` to publish tarballs and submit the opam package update. Always run `opam install --deps-only --with-test .`, `dune build @all`, `dune runtest`, and `dune build @install` before tagging to ensure the release is reproducible.

Further reading
---------------

- Core API and driver: source under [miaou_core/](./miaou_core/)
- Widgets:
	- Display primitives and pager: [miaou_widgets_display/](./miaou_widgets_display/)
	- Layout (panes, vsection, progress, file browser): [miaou_widgets_layout/](./miaou_widgets_layout/)
	- Input (textbox, select): [miaou_widgets_input/](./miaou_widgets_input/)
- Internals (renderer, modal machinery internals): [miaou_internals/](./miaou_internals/)


## Project home

The temporary public home for MIAOU is https://gitlab.com/mbourgoin/miaou, maintained by Nomadic Labs (<contact@nomadic-labs.com>). Please open issues and feature requests there.
