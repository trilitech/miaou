#!/usr/bin/env bash
# Launches the inline_color_picker demo in inline mode.
# After quit, the swatch strip stays in your scrollback because
# MIAOU_INLINE_MODE=1 tells the matrix driver to skip the alt-screen.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cd "$REPO_ROOT"

MIAOU_DRIVER=matrix MIAOU_INLINE_MODE=1 \
  exec dune exec example/demos/inline_color_picker/main.exe "$@"
