#!/usr/bin/env bash
# One line per card with generated text.   scripts/cards.sh ember
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . -s res://tools/cards.gd -- "$@" 2>&1 | grep -vE "^Godot Engine|^$"
