#!/usr/bin/env bash
# Modal multiline title scenario: drives the `modal_multiline_test` binary
# (test/modal_multiline_test.ml, previously only runnable interactively —
# see its header comment) through tmux to confirm the multi-line modal
# title renders ("Confirm Action" title line plus wrapped message body)
# and that the modal can be dismissed and the app quit cleanly.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/test/modal_multiline_test.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build test/modal_multiline_test.exe)"
  exit 77
fi

SESSION="miaou_modal_multiline_$$"
tmux_new_session "$SESSION" 80 30 "$BIN"

if ! tmux_wait_for_text "$SESSION" "Multiline Modal Title Test" 5; then
  echo "FAIL: base page did not render within 5s"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: base page rendered"

tmux_send_keys "$SESSION" "m"

if ! tmux_wait_for_text "$SESSION" "Confirm Action" 3; then
  echo "FAIL: modal title did not appear within 3s of pressing 'm'"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: multiline modal title rendered"

if ! tmux_wait_for_text "$SESSION" "node-seoulnet" 1; then
  echo "FAIL: multiline modal body text is missing"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: multiline modal body rendered"

tmux_send_keys "$SESSION" "Enter"
sleep 0.2
if ! tmux_session_exists "$SESSION"; then
  echo "FAIL: session exited unexpectedly after dismissing the modal"
  exit 1
fi
echo "PASS: session survived modal dismissal"

tmux_send_keys "$SESSION" "q"
if tmux_wait_gone "$SESSION" 3; then
  echo "PASS: 'q' quit the app within 3s"
else
  echo "FAIL: session still alive 3s after 'q'"
  tmux_kill_session "$SESSION"
  exit 1
fi

echo "MODAL_MULTILINE SCENARIO OK"
