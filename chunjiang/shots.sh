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
# Chrome for Testing's --screenshot writes nothing on this machine (not even a blank
# page) and never exits; chrome-headless-shell of the same version works, ~4s a frame.
CTF="${POEM_CTF:-/Users/chener/.cache/puppeteer/chrome-headless-shell/mac_arm-150.0.7871.24/chrome-headless-shell-mac-arm64/chrome-headless-shell}"
LOCK=/tmp/poem-world-shot.lock
# cameras 1 / 4 / 5: the moon over the water, the sandbar underfoot, the drifting boat
NAMES="1-moonrise 4-sandbar 5-boat"
SHOTS="1 4 5"

gate() {                      # never open a browser onto a machine that is already full
  g=0                         # not "n": the caller's loop variable is the camera name
  while [ "$g" -lt 30 ]; do
    load=$(uptime | sed 's/.*load averages*: *//' | awk '{print int($1)}')
    free=$(memory_pressure 2>/dev/null | awk -F': ' '/percentage/ {print $2+0; exit}')
    [ -z "$free" ] && free=100
    if [ "${load:-99}" -lt 8 ] && [ "$free" -gt 30 ]; then return 0; fi
    echo "  waiting: load=${load} free=${free}%"
    sleep 60; g=$((g+1))
  done
  echo "machine stayed busy, giving up"; exit 1
}

FAILED=""
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
  # Hard wall clock: CTF has hung past 20 minutes. perl's alarm is the documented
  # form, but on macOS it does not reliably survive exec into Chrome, so a shell
  # watchdog backs it up — whichever fires first, nothing runs past 90 seconds.
  nice -n 10 perl -e 'alarm 90; exec @ARGV' -- \
       "$CTF" --disable-gpu --use-angle=swiftshader --hide-scrollbars \
       --mute-audio --no-first-run --no-default-browser-check --disable-extensions \
       --virtual-time-budget=5000 --window-size=960,600 \
       --user-data-dir="$TMP" --screenshot="$OUT/$n.png" \
       "http://127.0.0.1:$PORT/chunjiang/index.html?shot=$s" >/dev/null 2>&1 &
  shotpid=$!
  ( sleep 90; kill -9 "$shotpid" 2>/dev/null; pkill -9 -f "user-data-dir=$TMP" 2>/dev/null ) &
  dogpid=$!
  wait "$shotpid" 2>/dev/null || true
  kill "$dogpid" 2>/dev/null || true
  pkill -9 -f "user-data-dir=$TMP" 2>/dev/null || true
  rm -r "$TMP" 2>/dev/null || true
  rmdir "$LOCK" 2>/dev/null || true
  if [ -s "$OUT/$n.png" ]; then
    echo "  $OUT/$n.png"
  else
    echo "  FAILED (timeout or no output): $OUT/$n.png"
    FAILED="$FAILED $n"
  fi
done
if [ -n "$FAILED" ]; then
  # a skipped shot is a line in log.jsonl, not a stalled round
  echo "round $R: shots failed:$FAILED"
  exit 2
fi
echo "round $R: 3 shots in $OUT"
