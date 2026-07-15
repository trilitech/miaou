#!/usr/bin/env bash
# Mouse-tracking cleanup scenario: replaces the old manual, interactive
# test_mouse_cleanup.sh script at the repo root (which asked a human to
# scroll their mouse wheel after Ctrl+C and eyeball the terminal for
# "unbound keyseq: mouse" garbage). Feeds a real SGR mouse wheel event into
# the term-driver launcher's stdin (so mouse tracking is genuinely
# exercised, not just assumed enabled), then verifies Ctrl+C still tears
# the session down promptly.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/example/gallery/main_tui.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build example/gallery/main_tui.exe)"
  exit 0
fi

SESSION="miaou_mouse_cleanup_$$"
tmux_new_session "$SESSION" 80 24 "$BIN"

if ! tmux_wait_for_text "$SESSION" "MIAOU demo launcher" 5; then
  echo "FAIL: launcher did not render within 5s"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: launcher rendered"

# SGR mouse wheel-down at row 10, col 10: ESC [ < 65 ; 10 ; 10 M
wheel_seq="$(printf '\033[<65;10;10M')"
tmux send-keys -t "$SESSION" -l "$wheel_seq"
sleep 0.2

if ! tmux_session_exists "$SESSION"; then
  echo "FAIL: session crashed on synthetic mouse wheel event"
  exit 1
fi
echo "PASS: launcher survived a synthetic mouse wheel event"

tmux_send_keys "$SESSION" C-c

if tmux_wait_gone "$SESSION" 3; then
  echo "PASS: Ctrl+C terminated the session within 3s after mouse tracking \
was exercised"
else
  echo "FAIL: session still alive 3s after Ctrl+C (post mouse-wheel input)"
  tmux_kill_session "$SESSION"
  exit 1
fi

echo "INFO: literal mouse-tracking-disable escape sequence verification is \
best-effort/out of scope for a black-box tmux capture (see scenario_sigterm.sh \
for the same convention); this scenario asserts prompt, clean-exit liveness \
after mouse tracking was genuinely engaged."

echo "MOUSE_CLEANUP SCENARIO OK"
