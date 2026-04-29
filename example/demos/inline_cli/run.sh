#!/usr/bin/env bash
# Launches the inline_cli demo in inline mode.
# After quit, the final TUI frame stays in your scrollback because
# MIAOU_INLINE_MODE=1 tells the matrix driver to skip the alt-screen.

set -e

# Locate the repo root relative to this script so the demo can be launched
# from any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cd "$REPO_ROOT"

MIAOU_DRIVER=matrix MIAOU_INLINE_MODE=1 \
  exec dune exec example/demos/inline_cli/main.exe "$@"
