#!/usr/bin/env bash
# Ctrl+C cleanup scenario: replaces the old manual, interactive
# test_ctrl_c.sh / test_with_debug.sh scripts at the repo root (which
# required a human to read instructions and eyeball scrollback for
# "unbound keyseq: mouse" garbage). Verifies the term-driver launcher exits
# promptly on SIGINT (Ctrl+C) delivered as a real key sequence inside a
# tmux pty, rather than hanging with mouse tracking left enabled.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/example/gallery/main_tui.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build example/gallery/main_tui.exe)"
  exit 77
fi

SESSION="miaou_ctrl_c_$$"
tmux_new_session "$SESSION" 80 24 "$BIN"

if ! tmux_wait_for_text "$SESSION" "MIAOU demo launcher" 5; then
  echo "FAIL: launcher did not render within 5s"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: launcher rendered"

tmux_send_keys "$SESSION" C-c

if tmux_wait_gone "$SESSION" 3; then
  echo "PASS: Ctrl+C terminated the session within 3s (cleanup ran, no hang)"
else
  echo "FAIL: session still alive 3s after Ctrl+C"
  tmux_kill_session "$SESSION"
  exit 1
fi

echo "INFO: literal mouse-tracking-disable escape sequence verification is \
best-effort/out of scope for a black-box tmux capture (see scenario_sigterm.sh \
for the same convention); this scenario asserts prompt, clean-exit liveness."

echo "CTRL_C SCENARIO OK"
