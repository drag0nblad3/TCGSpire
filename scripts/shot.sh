#!/usr/bin/env bash
# Renders the main scene to a PNG via a virtual display.  scripts/shot.sh out=/tmp/shot.png plays=2
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
# res=WxH (e.g. res=1080x2400) renders at a phone's window size; the 720-wide viewport stretches to fit.
RES=720x1280
for a in "$@"; do case "$a" in res=*) RES="${a#res=}";; esac; done
xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path . --rendering-driver opengl3 --resolution "$RES" \
  -s res://tools/screenshot.gd -- "$@" 2>&1 | grep -E "saved|SCRIPT ERROR|^ERROR|at: " | awk '!seen[$0]++' | head -30
