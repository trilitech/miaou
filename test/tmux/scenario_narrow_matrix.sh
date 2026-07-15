#!/usr/bin/env bash
# G3.3 narrow-terminal scenario for the Matrix driver: at 60x24 (< 80 cols)
# the launcher must show both the persistent narrow warning banner and the
# one-time "Narrow terminal" modal; any key dismisses the modal while the
# banner keeps rendering every frame; the app still quits cleanly
# afterwards. Paired with scenario_narrow_term.sh so the shared
# Narrow_warning helper (G3.3) is gated on both drivers.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/example/gallery/main_matrix.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (run: dune build example/gallery/main_matrix.exe)"
  exit 0
fi

SESSION="miaou_narrow_matrix_$$"
tmux_new_session "$SESSION" 60 24 "$BIN"

if ! tmux_wait_for_text "$SESSION" "Narrow terminal:" 3; then
  echo "FAIL: persistent narrow banner did not render within 3s"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: persistent narrow banner rendered"

if ! tmux_wait_for_text "$SESSION" "Your terminal is narrow" 3; then
  echo "FAIL: one-time narrow modal did not appear within 3s"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: one-time narrow modal rendered"

# Any key dismisses the modal.
tmux_send_keys "$SESSION" "j"
sleep 0.3
pane="$(tmux_capture_pane "$SESSION")"
case "$pane" in
*"Your terminal is narrow"*)
  echo "FAIL: narrow modal still visible after a key press"
  tmux_kill_session "$SESSION"
  exit 1
  ;;
esac
echo "PASS: narrow modal dismissed by key press"

case "$pane" in
*"Narrow terminal:"*) echo "PASS: narrow banner persists after modal dismissal" ;;
*)
  echo "FAIL: narrow banner disappeared after modal dismissal"
  tmux_kill_session "$SESSION"
  exit 1
  ;;
esac

tmux_send_keys "$SESSION" "q"
if tmux_wait_gone "$SESSION" 3; then
  echo "PASS: 'q' quit the app within 3s"
else
  echo "FAIL: session still alive 3s after 'q'"
  tmux_kill_session "$SESSION"
  exit 1
fi

echo "NARROW_MATRIX SCENARIO OK"
