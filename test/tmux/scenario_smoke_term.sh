#!/usr/bin/env bash
# G3.1 smoke scenario for the term (lambda-term) driver: the gallery launcher
# starts under MIAOU_DRIVER=term, renders something, and responds to the
# quit key inside a real tmux pty. Mirrors scenario_smoke.sh (Matrix driver)
# so both backends share the same baseline liveness guarantee.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/example/gallery/main_tui.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build example/gallery/main_tui.exe)"
  exit 77
fi

SESSION="miaou_smoke_term_$$"
tmux_new_session "$SESSION" 80 24 sh -c "MIAOU_DRIVER=term $BIN"
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

echo "SMOKE_TERM OK"
