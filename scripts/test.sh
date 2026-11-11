#!/usr/bin/env bash
# Runs all tests headless. Output: failures + one summary line (~1 line when green).
#   scripts/test.sh            # everything
#   scripts/test.sh combat     # only files/methods containing "combat"
#   scripts/test.sh -v         # also list passing tests
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG="${TMPDIR:-/tmp}/tcgspire-test.log"
# Refresh the class_name cache (needed after adding/renaming classes). Quiet unless it breaks.
"$GODOT" --headless --path . --import >"$LOG.import" 2>&1 || { tail -20 "$LOG.import"; exit 1; }
"$GODOT" --headless --path . -s res://tests/run_tests.gd -- "$@" >"$LOG" 2>&1
code=$?
# UI smoke: boot the real main scene headless and auto-play a few cards (full run only).
if [ $# -eq 0 ]; then
  "$GODOT" --headless --path . -s res://tools/screenshot.gd -- plays=3 frames=10 >>"$LOG" 2>&1 || code=1
fi
if grep -qE "SCRIPT ERROR|Parse Error" "$LOG"; then code=1; fi
if [ $code -eq 0 ]; then
  grep -E "^(ok |OK:)" "$LOG"
else
  # Failures, script errors (deduped, with location), summary. Full log: $LOG
  grep -E "^(FAIL|FAILED:|OK:)|SCRIPT ERROR|^ERROR:|^ +at: " "$LOG" | awk '!seen[$0]++' | head -40
  echo "(full log: $LOG)"
fi
exit $code
