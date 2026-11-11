#!/usr/bin/env bash
# Renders the main scene to a PNG via a virtual display.  scripts/shot.sh out=/tmp/shot.png plays=2
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
xvfb-run -a -s "-screen 0 720x1280x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 720x1280 \
  -s res://tools/screenshot.gd -- "$@" 2>&1 | grep -E "saved|SCRIPT ERROR|^ERROR|at: " | awk '!seen[$0]++' | head -30
