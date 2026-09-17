#!/bin/sh
# Three fixed cameras, one round.
#   sh shared/shoot.sh <world> <round> [port]
#
# One niced Chrome for Testing process paints all three cameras over CDP and
# exits.
#
# The loop worker does NOT look at what comes out of here. Shots go to disk for
# the site and for the byte-for-byte reproducibility check; the aesthetic gate
# runs `shared/critic.sh`, which shrinks them and shows 1-2 to a throwaway
# `claude -p` process. See AGENTS.md "上行流量".
#
# Cameras switch through window.__poemShot so the scene is not rebuilt.
# Backends (POEM_SHOT_BACKEND): headless-gpu (default) | headed-metal | swiftshader.
# QoS: taskpolicy -c background, nice -n 20. Shared mkdir lock so at most one
# render process exists on this machine. No resident browser.
set -e
W="${1:?usage: shoot.sh <world-dir> <round> [port]}"
R="${2:?round number}"
PORT="${3:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
OUT="$ROOT/$W/shots/$R"
LOCK=/tmp/poem-world-shot.lock
BACKEND="${POEM_SHOT_BACKEND:-headless-gpu}"
SHOT_ALARM="${SHOT_ALARM:-60}"
CTF="${POEM_WORLD_CHROME:-/Users/chener/.cache/puppeteer/chrome/mac_arm-150.0.7871.24/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"

[ -x "$CTF" ] || { echo "no Chrome for Testing at: $CTF" >&2; exit 1; }
[ -x "$HERE/cdp_shot.py" ] || { echo "missing $HERE/cdp_shot.py" >&2; exit 1; }

# name:arg passed to window.__poemShot. Index worlds take a camera number;
# xiangfuren takes x,z,yaw,pitch (the same cam= string as before).
case "$W" in
  gitanjali-60)
    SHOTS="1-arrival:1 2-children:2 6-above:6"
    DEFAULT_PORT=8731
    ;;
  chunjiang)
    SHOTS="1-moonrise:1 4-sandbar:4 5-boat:5"
    DEFAULT_PORT=8732
    ;;
  xiangfuren)
    SHOTS="1-beizhu:2,-58,0,-0.05 5-chengwang:0,-62,3.1416,-0.06 6-dengdai:-70,46,-0.575,-0.02"
    DEFAULT_PORT=8793
    ;;
  *)
    echo "unknown world: $W" >&2
    exit 1
    ;;
esac
PORT="${3:-${PORT:-$DEFAULT_PORT}}"
LOAD="http://127.0.0.1:$PORT/$W/index.html?shot=1"
mkdir -p "$OUT"

wait_for_machine() {
  i=0
  while [ "$i" -lt 30 ]; do
    load=$(uptime | sed -n 's/.*load averages*: *\([0-9.]*\).*/\1/p' | cut -d. -f1)
    free=$(memory_pressure 2>/dev/null | sed -n 's/.*memory free percentage: \([0-9]*\)%.*/\1/p')
    [ -z "$load" ] && load=0
    [ -z "$free" ] && free=100
    if [ "$load" -lt 8 ] && [ "$free" -gt 30 ]; then return 0; fi
    echo "  machine busy (load ${load}, free ${free}%), waiting 60s..."
    sleep 60
    i=$((i + 1))
  done
  echo "machine stayed busy for 30 minutes" >&2
  return 1
}
wait_for_machine

waited=0
until mkdir "$LOCK" 2>/dev/null; do
  waited=$((waited + 5))
  [ "$waited" -gt 1800 ] && { echo "shot lock held >30min: $LOCK" >&2; exit 1; }
  sleep 5
done
SRV=""
cleanup() {
  [ -n "$SRV" ] && kill "$SRV" 2>/dev/null || true
  rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/$W/index.html"; then
  ( cd "$ROOT" && nice -n 20 python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
  SRV=$!
  i=0
  while [ "$i" -lt 40 ]; do
    curl -sf -o /dev/null "http://127.0.0.1:$PORT/$W/index.html" && break
    sleep 0.25
    i=$((i + 1))
  done
fi

run_capture() {
  backend=$1
  set --
  for s in $SHOTS; do
    set -- "$@" --shot "$s"
  done
  # perl alarm does not survive exec on macOS, so system() keeps perl around.
  if command -v taskpolicy >/dev/null 2>&1; then
    taskpolicy -c background nice -n 20 perl -e \
      'alarm shift @ARGV; $e = system @ARGV; exit($e == -1 ? 127 : ($e & 127 ? 1 : $e >> 8))' \
      "$SHOT_ALARM" python3 "$HERE/cdp_shot.py" --backend "$backend" --load "$LOAD" \
      --outdir "$OUT" --chrome "$CTF" --timeout "$SHOT_ALARM" "$@"
  else
    nice -n 20 perl -e \
      'alarm shift @ARGV; $e = system @ARGV; exit($e == -1 ? 127 : ($e & 127 ? 1 : $e >> 8))' \
      "$SHOT_ALARM" python3 "$HERE/cdp_shot.py" --backend "$backend" --load "$LOAD" \
      --outdir "$OUT" --chrome "$CTF" --timeout "$SHOT_ALARM" "$@"
  fi
}

ok=0
if run_capture "$BACKEND"; then
  ok=1
elif [ "$BACKEND" = "headless-gpu" ]; then
  echo "  headless-gpu failed; trying headed-metal" >&2
  if run_capture headed-metal; then
    ok=1
  else
    echo "  headed-metal failed; falling back to swiftshader" >&2
    run_capture swiftshader && ok=1
  fi
elif [ "$BACKEND" != "swiftshader" ]; then
  echo "  $BACKEND failed; falling back to swiftshader" >&2
  run_capture swiftshader && ok=1
fi

missing=""
for s in $SHOTS; do
  name=${s%%:*}
  [ -s "$OUT/$name.png" ] || missing="$missing $name"
done
if [ "$ok" -ne 1 ] || [ -n "$missing" ]; then
  echo "  TIMED OUT or failed:$missing" >&2
  exit 2
fi
echo "round $R: 3 shots in $OUT"
echo "  do not Read these PNGs — run: sh shared/critic.sh $W $R"
