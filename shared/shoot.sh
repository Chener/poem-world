#!/bin/sh
# Six fixed cameras, one round.   sh shared/shoot.sh <world> <round> [port]
# The cameras and the frozen clock live in the world's CAMS/FROZEN_T constants and
# never change, so shots/3/2-children.png and shots/7/2-children.png differ only by
# what those rounds actually changed.
set -e
W="${1:?usage: shoot.sh <world-dir> <round> [port]}"
R="${2:?round number}"
PORT="${3:-8731}"
CAMS="1-arrival 2-children 3-boats 4-horizon 5-shore-line 6-above"
OUT="$W/shots/$R"
mkdir -p "$OUT"
export CHROME_DEVTOOLS_AXI_SESSION="${CHROME_DEVTOOLS_AXI_SESSION:-g60}"
chrome-devtools-axi resize 1280 800 >/dev/null 2>&1 || true
for c in $CAMS; do
  n="${c%%-*}"
  chrome-devtools-axi open "http://127.0.0.1:$PORT/$W/index.html?shot=$n" >/dev/null 2>&1
  sleep 3
  chrome-devtools-axi screenshot "$OUT/$c.png" >/dev/null 2>&1
  echo "  $OUT/$c.png"
done
echo "round $R: 6 shots in $OUT"
