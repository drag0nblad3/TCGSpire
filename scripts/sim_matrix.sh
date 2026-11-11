#!/usr/bin/env bash
# Standard balance matrix: 150 runs per cell, new heat 0-2, experienced 1-3, veteran 2-5, max 4-6.
cd "$(dirname "$0")/.."
for spec in new:0:2 experienced:1:3 veteran:2:5 max:4:6; do
  IFS=: read -r p lo hi <<<"$spec"
  for h in $(seq "$lo" "$hi"); do
    scripts/sim.sh mode=run n=150 job=all heat="$h" profile="$p" | grep "^\[" | cut -c1-170
  done
done
