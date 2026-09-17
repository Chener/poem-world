#!/bin/sh
# Scene data for one round, from the same three cameras as the screenshots.
#   sh shared/world.sh <world> <round> [port]
#
# One niced Chrome for Testing process loads the page, walks the cameras through
# window.__poemShot and prints window.__world() for each into
#   <world>/scene/<round>.json
# a few kB of numbers: what exists, where it is, whether it is in frame, how big
# it comes out, what the frame cost. The polish loop's hard gates read that file
# — "is it there", "is it in the picture", "is it over budget" are all answered
# from it. Pictures stay for the aesthetic gate (shared/critic.sh).
#
# Same lock, same QoS and the same backend fallbacks as shared/shoot.sh, because
# it is the same browser doing the same work; at most one render process on this
# machine at a time.
set -e
W="${1:?usage: world.sh <world-dir> <round> [port]}"
R="${2:?round number}"
PORT="${3:-}"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
OUT="$ROOT/$W/scene/$R.json"
LOCK=/tmp/poem-world-shot.lock
BACKEND="${POEM_SHOT_BACKEND:-headless-gpu}"
SHOT_ALARM="${SHOT_ALARM:-60}"
CTF="${POEM_WORLD_CHROME:-/Users/chener/.cache/puppeteer/chrome/mac_arm-150.0.7871.24/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"

[ -x "$CTF" ] || { echo "no Chrome for Testing at: $CTF" >&2; exit 1; }
[ -f "$HERE/cdp_world.py" ] || { echo "missing $HERE/cdp_world.py" >&2; exit 1; }

. "$HERE/cams.sh"
world_cams "$W" || exit 1
PORT="${3:-${PORT:-$DEFAULT_PORT}}"
LOAD="http://127.0.0.1:$PORT/$W/index.html?shot=1"
mkdir -p "$(dirname "$OUT")"

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

run_dump() {
  backend=$1
  set --
  for s in $SHOTS; do
    set -- "$@" --shot "$s"
  done
  if command -v taskpolicy >/dev/null 2>&1; then
    taskpolicy -c background nice -n 20 perl -e \
      'alarm shift @ARGV; $e = system @ARGV; exit($e == -1 ? 127 : ($e & 127 ? 1 : $e >> 8))' \
      "$SHOT_ALARM" python3 "$HERE/cdp_world.py" --backend "$backend" --load "$LOAD" \
      --out "$OUT" --chrome "$CTF" --timeout "$SHOT_ALARM" "$@"
  else
    nice -n 20 perl -e \
      'alarm shift @ARGV; $e = system @ARGV; exit($e == -1 ? 127 : ($e & 127 ? 1 : $e >> 8))' \
      "$SHOT_ALARM" python3 "$HERE/cdp_world.py" --backend "$backend" --load "$LOAD" \
      --out "$OUT" --chrome "$CTF" --timeout "$SHOT_ALARM" "$@"
  fi
}

ok=0
if run_dump "$BACKEND"; then
  ok=1
elif [ "$BACKEND" = "headless-gpu" ]; then
  echo "  headless-gpu failed; trying headed-metal" >&2
  if run_dump headed-metal; then
    ok=1
  else
    echo "  headed-metal failed; falling back to swiftshader" >&2
    run_dump swiftshader && ok=1
  fi
elif [ "$BACKEND" != "swiftshader" ]; then
  echo "  $BACKEND failed; falling back to swiftshader" >&2
  run_dump swiftshader && ok=1
fi

if [ "$ok" -ne 1 ] || [ ! -s "$OUT" ]; then
  echo "  TIMED OUT or failed: $OUT" >&2
  exit 2
fi
echo "round $R: scene data in $OUT"
