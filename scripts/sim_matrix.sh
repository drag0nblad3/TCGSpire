#!/usr/bin/env bash
# Standard balance matrix: 200 runs per cell, new heat 0-3, veteran 1-4, max 2-6.
cd "$(dirname "$0")/.."
for spec in new:0:3 veteran:1:4 max:2:6; do
  IFS=: read -r p lo hi <<<"$spec"
  for h in $(seq "$lo" "$hi"); do
    scripts/sim.sh mode=run n=200 job=all heat="$h" profile="$p" | grep "^\[" | cut -c1-170
  done
done
