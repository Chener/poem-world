#!/bin/sh
# Six fixed cameras, one round, one-shot headless Chrome for Testing.
#   sh chunjiang/shots.sh <round> [port]
# No long-lived browser: every camera launches CTF headless, writes a PNG and exits.
# A single mkdir lock is shared by all three worlds so at most one CTF runs at a time.
set -e
R="${1:?usage: shots.sh <round> [port]}"
PORT="${2:-8732}"
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/shots/$R"; mkdir -p "$OUT"
CTF="${POEM_CTF:-/Users/chener/.cache/puppeteer/chrome/mac_arm-150.0.7871.24/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"
LOCK=/tmp/poem-world-shot.lock
NAMES="1-moonrise 2-moon-path 3-flower-grove 4-sandbar 5-boat 6-river-trees"

# don't open a browser while the machine is already under memory pressure
free=$(memory_pressure 2>/dev/null | awk -F': ' '/percentage/ {print $2+0; exit}')
[ -n "$free" ] && [ "$free" -lt 30 ] 2>/dev/null && { echo "memory free ${free}% < 30%, waiting"; sleep 20; }

i=0
for n in $NAMES; do
  i=$((i+1))
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries+1)); [ "$tries" -gt 120 ] && { echo "lock busy, giving up"; exit 1; }
    sleep 2
  done
  TMP=$(mktemp -d)
  "$CTF" --headless=new --disable-gpu --use-angle=swiftshader --hide-scrollbars \
         --virtual-time-budget=4000 --window-size=1280,800 \
         --user-data-dir="$TMP" --screenshot="$OUT/$n.png" \
         "http://127.0.0.1:$PORT/chunjiang/index.html?shot=$i" >/dev/null 2>&1 || true
  rm -rf "$TMP"; rmdir "$LOCK" 2>/dev/null || true
  echo "  $OUT/$n.png"
done
echo "round $R: 6 shots in $OUT"
