#!/usr/bin/env bash
# Runs every test/tmux/scenario_*.sh in turn and reports a PASS/SKIP/FAIL
# summary. Exits non-zero iff at least one scenario FAILed; a SKIP (e.g. a
# scenario binary wasn't built, or tmux itself isn't available) never fails
# the run. Not wired into `dune runtest` (see test/tmux/lib.sh header) —
# invoke directly, e.g. from CI: `bash test/tmux/run_all.sh`.
#
# Scenarios signal SKIP via the conventional exit code 77 (as used by
# autotools test harnesses), which is the authoritative signal below; the
# "^SKIP:" line they also print is kept as a human-readable explanation and
# as a fallback classifier for any scenario that hasn't adopted the exit
# code yet.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux not installed; skipping all tmux scenarios"
  exit 0
fi

scenarios=(test/tmux/scenario_*.sh)
if [ ${#scenarios[@]} -eq 0 ]; then
  echo "SKIP: no scenario scripts found"
  exit 0
fi

declare -a passed=() skipped=() failed=()

for scenario in "${scenarios[@]}"; do
  name="$(basename "$scenario")"
  echo "=== running $name ==="
  output="$(bash "$scenario" 2>&1)"
  status=$?
  echo "$output"
  if [ $status -eq 77 ]; then
    skipped+=("$name")
  elif [ $status -ne 0 ]; then
    failed+=("$name")
  elif printf '%s\n' "$output" | grep -q '^SKIP:'; then
    skipped+=("$name")
  else
    passed+=("$name")
  fi
  echo ""
done

echo "=== tmux scenario summary ==="
echo "PASS: ${#passed[@]} (${passed[*]:-none})"
echo "SKIP: ${#skipped[@]} (${skipped[*]:-none})"
echo "FAIL: ${#failed[@]} (${failed[*]:-none})"

if [ ${#failed[@]} -gt 0 ]; then
  exit 1
fi
exit 0
