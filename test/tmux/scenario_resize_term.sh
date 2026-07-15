#!/usr/bin/env bash
# G3.4 SIGWINCH scenario for the term (lambda-term) driver: resizing a live
# pane from >=80 to <80 columns must immediately redraw with the narrow
# banner (no waiting for a stray keypress or the idle refresh tick),
# proving the consolidated signal installer keeps BOTH SIGWINCH effects —
# the session's size-cache invalidation (Terminal_raw) and the driver's
# local resize_pending flag — rather than one silently overwriting the
# other's Sys.set_signal handler.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/example/gallery/main_tui.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build example/gallery/main_tui.exe)"
  exit 77
fi

SESSION="miaou_resize_term_$$"
tmux_new_session "$SESSION" 100 24 sh -c "MIAOU_DRIVER=term $BIN"

if ! tmux_wait_for_text "$SESSION" "MIAOU demo launcher" 3; then
  echo "FAIL: launcher did not render within 3s at 100 cols"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: launcher rendered at 100 cols"

pane="$(tmux_capture_pane "$SESSION")"
case "$pane" in
*"Narrow terminal:"*)
  echo "FAIL: narrow banner present at 100 cols (test precondition violated)"
  tmux_kill_session "$SESSION"
  exit 1
  ;;
esac

tmux resize-window -t "$SESSION" -x 60 -y 24

if ! tmux_wait_for_text "$SESSION" "Narrow terminal:" 2; then
  echo "FAIL: narrow banner did not appear within 2s of crossing to 60 cols (SIGWINCH redraw regression)"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: SIGWINCH resize to 60 cols redrew the narrow banner within 2s"

# Crossing into narrow also pushes the one-time narrow modal, which
# consumes the next keystroke to dismiss itself; send a throwaway key
# first so the following 'q' actually reaches the page.
tmux_send_keys "$SESSION" "j"
sleep 0.3

tmux_send_keys "$SESSION" "q"
if tmux_wait_gone "$SESSION" 3; then
  echo "PASS: 'q' quit the app within 3s"
else
  echo "FAIL: session still alive 3s after 'q'"
  tmux_kill_session "$SESSION"
  exit 1
fi

echo "RESIZE_TERM SCENARIO OK"
