#!/usr/bin/env bash
# S4 miaou-mcp scenario: the real miaou-mcp binary, driven over its stdio
# JSON-RPC transport inside a real tmux pty (rather than an in-process
# scripted client), completes an initialize -> notifications/initialized ->
# tools/call handshake and returns a well-formed MCP response.
#
# miaou-mcp only exists in a switch that has pinned the mcp-kit commit named
# in miaou-mcp.opam.template (see docs/agent-protocol.md); if the binary
# isn't built, this scenario SKIPs (exit 77) rather than failing, matching
# every other scenario_*.sh's convention for an unbuilt optional binary.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/tmux/lib.sh

BIN="_build/default/src/miaou_mcp/miaou_mcp_main.exe"
if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not built (requires the mcp-kit pin; see docs/agent-protocol.md)"
  exit 77
fi

SESSION="miaou_mcp_stdio_$$"
tmux_new_session "$SESSION" 200 50 "env MIAOU_NO_RECORD=1 $BIN"
sleep 0.5

if ! tmux_session_exists "$SESSION"; then
  echo "FAIL: miaou-mcp exited before we could interact with it"
  exit 1
fi

# tmux send-keys writes the *displayed* keystrokes into the pty; miaou-mcp
# reads them as a line of stdin once Enter is pressed, exactly as it would
# read a line piped in from a real MCP client.
send_line() {
  tmux_send_keys "$SESSION" "$1" Enter
}

send_line '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"tmux-scenario","version":"0"}}}'
sleep 0.3
send_line '{"jsonrpc":"2.0","method":"notifications/initialized"}'
sleep 0.3
send_line '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"render","arguments":{}}}'
sleep 0.5

if ! tmux_wait_for_text "$SESSION" '"serverInfo"' 3; then
  echo "FAIL: initialize response ('serverInfo') not observed within 3s"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: initialize handshake response observed"

if ! tmux_wait_for_text "$SESSION" '"schema_version"' 3; then
  echo "FAIL: render tool-call response ('schema_version') not observed within 3s"
  tmux_kill_session "$SESSION"
  exit 1
fi
echo "PASS: tools/call render response observed"

tmux_kill_session "$SESSION"
echo "MCP_STDIO SCENARIO OK"
