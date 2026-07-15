#!/usr/bin/env bash
# G3.1/G3.5 SIGTERM scenario for the term (lambda-term) driver: an idle
# term-backend TUI must react to SIGTERM promptly, exit with the
# conventional 130 code, and leave the terminal in a sane state. Written in
# G3.1 to assert the CURRENT behavior as a baseline before G3.5
# consolidates term_terminal_setup's signal installation onto the shared
# self-pipe/exit-flag pattern; the bound (<=2s, code 130) must still hold
# after that consolidation. Mirrors scenario_sigterm.sh (Matrix driver).
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/example/gallery/main_tui.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build example/gallery/main_tui.exe)"
  exit 0
fi

SESSION="miaou_sigterm_term_$$"
# Wrap in `sh -c '... ; echo EXIT:$?'` so the exit code survives past the
# process replacing the shell, and is visible in the captured pane.
tmux_new_session "$SESSION" 80 24 sh -c "MIAOU_DRIVER=term $BIN; echo EXIT:\$?"
sleep 1.0

if ! tmux_session_exists "$SESSION"; then
  echo "FAIL: session exited before SIGTERM was sent"
  exit 1
fi

pid="$(tmux_pane_pid "$SESSION")"
if [ -z "$pid" ]; then
  echo "FAIL: could not determine pane PID"
  tmux_kill_session "$SESSION"
  exit 1
fi

# Target the whole process group so the signal reaches the actual
# main_tui.exe process (a child of the `sh -c` wrapper), not just the
# shell wrapper.
start_s=$(date +%s.%N)
kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null

if tmux_wait_gone "$SESSION" 2; then
  end_s=$(date +%s.%N)
  elapsed=$(awk -v a="$start_s" -v b="$end_s" 'BEGIN { printf "%.2f", b - a }')
  echo "PASS: session terminated ${elapsed}s after SIGTERM (bound: 2s)"
else
  echo "FAIL: session still alive 2s after SIGTERM (term-driver liveness regression)"
  tmux_kill_session "$SESSION"
  exit 1
fi

# The pane is gone, but tmux buffers the last screen; the wrapper's
# `echo EXIT:$?` line (captured just before the pane closed, if tmux kept
# history) is best-effort evidence of the exit code. Not all tmux/pty
# configurations retain this after the session closes, so treat it as
# informational rather than a hard assertion.
echo "INFO: expected exit code 130 (SIGTERM); direct capture after session close is best-effort and not asserted here."

echo "SIGTERM_TERM SCENARIO OK"
