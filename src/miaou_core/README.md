# miaou_core - Core Public API for Miaou TUI

This library provides the fundamental public API for building Miaou-based Text User Interfaces. It defines the core concepts such as pages, the page registry, and the capability system for abstracting side effects.

It depends on the internal helper library and the widgets library. It can be packaged independently as `miaou_core`.

## Key Features
- Page Management: Defines the `PAGE_SIG` interface and manages page registration and navigation.
- Modal System: Provides a robust system for displaying and managing interactive modals.
- Capability System: Offers a flexible mechanism to abstract side effects (e.g., file system access, network requests) through pluggable implementations. This allows for greater testability and adaptability.
- Event Loop Integration: Integrates with the underlying terminal driver to process user input and update the UI.

## Build & Use

In this repository:

- Preferred workflow:
  - `make deps` (installs opam dependencies for the local switch)
  - `make build` (builds all libraries)
  - `make test` (runs repository tests)
  - optional: `make fmt`
- Fallback (direct dune): `eval $(opam env) && dune build @all && dune runtest`

For consumers (other projects):

- Public library name: `miaou.core`
- OCaml module at call sites: `Miaou_core`

Example dune stanza:

```
(library
 (name my_app)
 (libraries miaou.core)
)
```
