#!/usr/bin/env bash
# Per-card balance sim: each pack card forced into the starter picks (2 copies),
# scored by floor reached vs paired baseline runs. Runs shards in parallel.
#   scripts/card_sim.sh [n=60] [profile=new] [heat=0] [cards=a,b] [jobs=4] [out=/tmp/card_sim]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
JOBS=4
OUT=/tmp/card_sim
ARGS=()
for a in "$@"; do
  case "$a" in
    jobs=*) JOBS="${a#jobs=}" ;;
    out=*) OUT="${a#out=}" ;;
    *) ARGS+=("$a") ;;
  esac
done
mkdir -p "$OUT" && rm -f "$OUT"/shard_*.json
"$GODOT" --headless --path . --import >/dev/null 2>&1
for ((k = 0; k < JOBS; k++)); do
  "$GODOT" --headless --path . -s res://tools/card_sim.gd -- "${ARGS[@]}" "shard=$k/$JOBS" "out=$OUT" 2>&1 | grep -vE "^Godot Engine|^$" &
done
wait
"$GODOT" --headless --path . -s res://tools/card_sim.gd -- "merge=$OUT" 2>&1 | grep -vE "^Godot Engine|^$"
