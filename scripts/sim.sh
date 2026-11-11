#!/usr/bin/env bash
# Balance sim. Prints one line per encounter.   scripts/sim.sh n=500 enc=golem
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . -s res://tools/sim.gd -- "$@" 2>&1 | grep -vE "^Godot Engine|^$"
