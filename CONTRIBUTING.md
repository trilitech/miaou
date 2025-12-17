# Contributing to MIAOU

Thank you for your interest in contributing to MIAOU! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Code Style](#code-style)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [License](#license)

## Code of Conduct

We are committed to providing a welcoming and inclusive environment. Please be respectful and constructive in all interactions.

## Getting Started

1. **Fork the repository** and clone your fork locally
2. **Set up the development environment** (see below)
3. **Create a branch** for your changes
4. **Make your changes** following our guidelines
5. **Submit a pull request**

## Development Setup

### Prerequisites

- OCaml 5.1 or later (5.3.x recommended)
- opam 2.x
- dune >= 3.15
- For SDL backend: SDL2, SDL2_ttf, SDL2_image development libraries

### Installation

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/miaou.git
cd miaou

# Install dependencies
make deps

# Build the project
make build

# Run tests
make test
```

### Useful Commands

| Command | Description |
|---------|-------------|
| `make deps` | Install all dependencies |
| `make build` | Build the project |
| `make test` | Run the test suite |
| `make fmt` | Format code with ocamlformat |
| `make coverage` | Generate test coverage report |
| `make clean` | Clean build artifacts |

### Running Demos

```bash
# Run the demo gallery (terminal)
dune exec -- example/gallery/main.exe

# Run with SDL backend (requires SDL2)
MIAOU_DRIVER=sdl dune exec -- example/gallery/main.exe
```

## Making Changes

### Branch Naming

Use descriptive branch names with a prefix:

- `feat/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `refactor/` - Code refactoring
- `test/` - Test additions or fixes
- `chore/` - Maintenance tasks

Example: `feat/add-progress-bar-widget`

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/). Format:

```
type(scope): description

[optional body]

[optional footer]
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `style` - Formatting (no code change)
- `refactor` - Code restructuring
- `test` - Adding tests
- `chore` - Maintenance

**Examples:**
```
feat(widgets): add circular progress bar widget

fix(modal): prevent double-close on escape key

docs(readme): add SDL backend setup instructions
```

## Code Style

### OCaml Formatting

We use `ocamlformat`. Run before committing:

```bash
make fmt
```

The configuration is in `.ocamlformat`.

### File Headers

All `.ml` and `.mli` files must include the license header:

```ocaml
(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)
```

### Interface Files

Public modules should have corresponding `.mli` interface files with:
- Type definitions
- Function signatures with documentation comments
- Module documentation at the top

### Documentation Comments

Use OCamldoc style:

```ocaml
(** Short description of the function.

    Longer description if needed, explaining behavior,
    edge cases, and usage.

    @param name Description of parameter
    @return Description of return value
    @raise Exception When this exception is raised
*)
val function_name : param_type -> return_type
```

## Testing

### Running Tests

```bash
# Run all tests
make test

# Run specific test file
dune exec -- test/test_widgets.exe

# Run with verbose output
dune exec -- test/test_widgets.exe --verbose
```

### Writing Tests

- Tests live in the `test/` directory
- Use [Alcotest](https://github.com/mirage/alcotest) for unit tests
- Name test files `test_<module>.ml`
- Group related tests in test suites

Example test structure:

```ocaml
let test_widget_creation () =
  let widget = Widget.create ~label:"Test" () in
  Alcotest.(check string) "label" "Test" (Widget.label widget)

let tests = [
  Alcotest.test_case "creation" `Quick test_widget_creation;
]

let () =
  Alcotest.run "Widget" [
    ("basic", tests);
  ]
```

### Test Coverage

Generate coverage reports:

```bash
make coverage
# Open _coverage/html/index.html in a browser
```

## Submitting Changes

### Pull Request Process

1. **Ensure all tests pass**: `make test`
2. **Format your code**: `make fmt`
3. **Update documentation** if needed
4. **Update CHANGELOG.md** for user-facing changes
5. **Create a pull request** with a clear description

### Pull Request Template

Your PR description should include:

- **Summary**: What does this PR do?
- **Motivation**: Why is this change needed?
- **Testing**: How was this tested?
- **Breaking Changes**: Any breaking changes?

### Review Process

- All PRs require at least one review
- CI must pass (build, tests, formatting)
- Address review feedback promptly
- Squash commits if requested

## Adding New Widgets

When adding a new widget:

1. Create `widget_name.ml` and `widget_name.mli` in the appropriate directory
2. Add license header to both files
3. Export from the parent module
4. Add the module to the dune file
5. Create a demo in `example/demos/widget_name/`
6. Write tests in `test/test_widget_name.ml`
7. Document in README if it's a major feature

## Package Structure

The project is split into multiple opam packages:

| Package | Description |
|---------|-------------|
| `miaou-core` | Core library, widgets, no SDL |
| `miaou-driver-term` | Terminal driver |
| `miaou-driver-sdl` | SDL2 driver |
| `miaou-runner` | Runner with backend selection |
| `miaou-tui` | Meta-package for terminal-only |
| `miaou` | Full meta-package |

When adding dependencies, consider which package they belong to.

## Getting Help

- **Issues**: Open an issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions

## License

By contributing, you agree that your contributions will be licensed under the MIT License. All contributions must include the appropriate license headers.

---

Thank you for contributing to MIAOU!
