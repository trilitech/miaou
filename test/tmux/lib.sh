#!/usr/bin/env bash
# Minimal tmux harness for MIAOU runtime scenarios (crash-ub-fixes slice S0).
#
# Not wired into `dune runtest`: tmux availability in CI/sandbox is not
# guaranteed, and these scenarios exercise real terminal/signal behavior
# that alcotest cannot observe (raw mode, SIGTERM delivery, stty state).
# Run scenario scripts directly, e.g.:
#
#   bash test/tmux/scenario_sigterm.sh
#
# Each scenario sources this file, then:
#   1. tmux_new_session <name> <cmd...>
#   2. tmux_send_keys / tmux_capture_pane / assertions
#   3. tmux_kill_session <name>   (also happens automatically via the EXIT
#      trap installed by tmux_new_session, so scenarios are safe to `exit`
#      early on assertion failure without leaking sessions)
#
# All functions print one-line PASS/FAIL-style diagnostics; scenarios
# should `exit 1` on the first failed assertion.

set -u

TMUX_HARNESS_SESSIONS=()

tmux_cleanup_all() {
  local s
  for s in "${TMUX_HARNESS_SESSIONS[@]:-}"; do
    [ -z "$s" ] && continue
    tmux kill-session -t "$s" >/dev/null 2>&1 || true
  done
}
trap tmux_cleanup_all EXIT

# tmux_new_session <session_name> <cols> <rows> <command...>
tmux_new_session() {
  local name="$1" cols="$2" rows="$3"
  shift 3
  tmux new-session -d -s "$name" -x "$cols" -y "$rows" "$@"
  TMUX_HARNESS_SESSIONS+=("$name")
}

# tmux_send_keys <session_name> <keys...>
tmux_send_keys() {
  local name="$1"
  shift
  tmux send-keys -t "$name" "$@"
}

# tmux_capture_pane <session_name> -> prints pane content to stdout
tmux_capture_pane() {
  local name="$1"
  tmux capture-pane -p -t "$name"
}

# tmux_pane_pid <session_name> -> prints the PID of the pane's process
tmux_pane_pid() {
  local name="$1"
  tmux list-panes -t "$name" -F '#{pane_pid}'
}

# tmux_session_exists <session_name> -> exit 0 if alive, 1 if gone
tmux_session_exists() {
  tmux has-session -t "$1" >/dev/null 2>&1
}

# tmux_wait_gone <session_name> <timeout_seconds> -> exit 0 if the session
# (and its process tree) disappeared within the timeout, 1 otherwise.
tmux_wait_gone() {
  local name="$1" timeout="$2" waited=0
  while tmux_session_exists "$name"; do
    sleep 0.1
    waited=$(awk -v w="$waited" 'BEGIN { print w + 0.1 }')
    if awk -v w="$waited" -v t="$timeout" 'BEGIN { exit !(w >= t) }'; then
      return 1
    fi
  done
  return 0
}

tmux_kill_session() {
  local name="$1"
  tmux kill-session -t "$name" >/dev/null 2>&1 || true
}
