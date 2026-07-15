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
  exit 77
fi

SESSION="miaou_mouse_cleanup_$$"
tmux_new_session "$SESSION" 80 24 "$BIN"

# `tmux capture-pane -e` only reconstructs the SGR attributes of *rendered*
# cells; DEC private-mode toggles like the mouse-tracking disable sequence
# never produce visible cell content, so tmux's terminal emulation consumes
# them silently and -e cannot see them. `pipe-pane -o`, however, tees the
# pane's raw pty byte stream — exactly what the child process wrote, before
# tmux interprets it — to a file, which does let us assert the literal
# disable sequence was sent. Best-effort: if pipe-pane itself can't be
# started (e.g. an old/restricted tmux build), skip just that assertion
# with a documented reason rather than failing the whole scenario.
RAW_LOG="$(mktemp)"
# Chain onto lib.sh's own EXIT trap (tmux_cleanup_all) instead of replacing
# it, so the tmux session is still torn down on every exit path.
trap 'rm -f "$RAW_LOG"; tmux_cleanup_all' EXIT
pipe_pane_ok=1
tmux pipe-pane -t "$SESSION" -o "cat >> '$RAW_LOG'" 2>/dev/null || pipe_pane_ok=0

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

# Give pipe-pane's `cat` a moment to flush the last bytes the child wrote
# during teardown.
sleep 0.2

if [ "$pipe_pane_ok" -eq 1 ] && [ -s "$RAW_LOG" ]; then
  if grep -qF $'\033[?1000l' "$RAW_LOG"; then
    echo "PASS: mouse-tracking disable sequence (ESC[?1000l) observed in \
the raw pty stream after Ctrl+C"
  else
    echo "FAIL: mouse-tracking disable sequence not observed in the raw pty \
stream after Ctrl+C"
    exit 1
  fi
else
  echo "INFO: could not capture the raw pty stream via 'tmux pipe-pane' \
(unsupported/restricted tmux build?); falling back to the liveness-only \
assertion above — 'capture-pane -e' cannot see this sequence either, since \
DEC private-mode toggles are consumed by tmux's terminal emulation and \
never appear as rendered cell content."
fi

echo "MOUSE_CLEANUP SCENARIO OK"
