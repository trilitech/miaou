# miaou_internals - Internal Implementation Details for Miaou TUI

This library contains the internal implementation details and helper modules for the Miaou TUI framework. These modules are not part of the public API and are not intended for direct consumption by external applications. They provide the underlying mechanisms for rendering, modal management, and key event handling.

It can be packaged separately as `miaou_internals` if desired.

## Key Components:
- **Modal Renderer:** Handles the rendering of modal overlays on top of the main page content.
- **Key Handler Stack:** Manages the prioritization and dispatching of key events to the currently active UI components (pages and modals).
- **Modal Snapshot:** Provides mechanisms for capturing and restoring the state of modals.

## Build & Use

In this repository:

- Preferred workflow: `make deps && make build && make test` (optional: `make fmt`)
- Fallback: `eval $(opam env) && dune build @all && dune runtest`

For consumers (other projects):

- Public library name: `miaou.internals`
- OCaml module at call sites: `Miaou_internals` (note: this is internal; prefer depending on the umbrella `miaou` or `miaou.core` and the split widget libraries)

Example dune stanza (if you really need it):

```
(library
 (name my_driver)
 (libraries miaou) ; prefer umbrella
)
```
