#!/bin/sh
# Three fixed cameras, one round, one-shot headless Chrome for Testing.
#   sh chunjiang/shots.sh <round> [port]
# Per the 2026-09-17 machine-load ruling: 3 cameras (not 6), 960x600, nice -n 10,
# a load/memory gate before opening anything, the shared mkdir lock, and no
# long-lived browser — every camera launches CTF, writes a PNG and exits.
set -e
R="${1:?usage: shots.sh <round> [port]}"
PORT="${2:-8732}"
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/shots/$R"; mkdir -p "$OUT"
CTF="${POEM_CTF:-/Users/chener/.cache/puppeteer/chrome/mac_arm-150.0.7871.24/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"
LOCK=/tmp/poem-world-shot.lock
# cameras 1 / 4 / 5: the moon over the water, the sandbar underfoot, the drifting boat
NAMES="1-moonrise 4-sandbar 5-boat"
SHOTS="1 4 5"

gate() {                      # never open a browser onto a machine that is already full
  n=0
  while [ "$n" -lt 30 ]; do
    load=$(uptime | sed 's/.*load averages*: *//' | awk '{print int($1)}')
    free=$(memory_pressure 2>/dev/null | awk -F': ' '/percentage/ {print $2+0; exit}')
    [ -z "$free" ] && free=100
    if [ "${load:-99}" -lt 8 ] && [ "$free" -gt 30 ]; then return 0; fi
    echo "  waiting: load=${load} free=${free}%"
    sleep 60; n=$((n+1))
  done
  echo "machine stayed busy, giving up"; exit 1
}

set -- $SHOTS
for n in $NAMES; do
  s="$1"; shift
  gate
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries+1)); [ "$tries" -gt 120 ] && { echo "lock busy, giving up"; exit 1; }
    sleep 2
  done
  TMP=$(mktemp -d)
  nice -n 10 "$CTF" --headless=new --disable-gpu --use-angle=swiftshader --hide-scrollbars \
       --mute-audio --no-first-run --no-default-browser-check --disable-extensions \
       --virtual-time-budget=4000 --window-size=960,600 \
       --user-data-dir="$TMP" --screenshot="$OUT/$n.png" \
       "http://127.0.0.1:$PORT/chunjiang/index.html?shot=$s" >/dev/null 2>&1 || true
  rm -r "$TMP" 2>/dev/null || true
  rmdir "$LOCK" 2>/dev/null || true
  echo "  $OUT/$n.png"
done
echo "round $R: 3 shots in $OUT"
