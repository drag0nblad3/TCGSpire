#!/usr/bin/env bash
# Builds the card/enemy data browser page (one self-contained HTML file) and checks
# that its rules-text port matches the game.   scripts/browser.sh [out_dir=build/browser]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${1:-build/browser}"
TMP="$(mktemp -d)"
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . -s res://tools/export_browser.gd -- "$TMP/text.json" 2>&1 | grep -vE "^Godot Engine|^$"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null)" node tools/browser/build.js "$TMP/text.json" "$OUT"
