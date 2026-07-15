#!/usr/bin/env bash
# S0 smoke scenario: the Matrix-driver demo starts, renders something, and
# responds to a quit key inside a real tmux pty. Establishes that the
# harness (test/tmux/lib.sh) works end-to-end before relying on it for the
# S6/S7 crash/signal scenarios.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/example/gallery/main_matrix.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build example/gallery/main_matrix.exe)"
  exit 0
fi

SESSION="miaou_smoke_$$"
tmux_new_session "$SESSION" 80 24 "$BIN"
sleep 1.0

if ! tmux_session_exists "$SESSION"; then
  echo "FAIL: session exited before we could interact with it"
  exit 1
fi

pane="$(tmux_capture_pane "$SESSION")"
if [ -z "$pane" ]; then
  echo "FAIL: pane content is empty after 1s"
  exit 1
fi
echo "PASS: pane rendered non-empty content"

tmux_send_keys "$SESSION" "q"
if tmux_wait_gone "$SESSION" 3; then
  echo "PASS: quit key terminated the session within 3s"
else
  echo "FAIL: session still alive 3s after quit key"
  tmux_kill_session "$SESSION"
  exit 1
fi

echo "SMOKE OK"
