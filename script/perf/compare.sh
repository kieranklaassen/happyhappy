#!/usr/bin/env bash
# Visual check for performance work: SSIM of each page screenshot against a baseline set
# (1.0 is identical). Screenshots come from `SCREENSHOTS=dir node script/perf/browser.mjs`.
#
#   script/perf/compare.sh baseline-dir candidate-dir
set -euo pipefail
for before in "$1"/*.png; do
  name=$(basename "$before")
  score=$(ffmpeg -hide_banner -i "$before" -i "$2/$name" -lavfi ssim -f null - 2>&1 | grep -o 'All:[0-9.]*' | cut -d: -f2)
  echo "$name $score"
done
