#!/bin/sh
# Three fixed cameras, one round.   sh shared/shoot.sh <world> <round> [port]
#
# The cameras and the frozen clock live in the world's CAMS/FROZEN_T constants and
# never change, so shots/3/2-children.png and shots/7/2-children.png differ only by
# what those rounds actually changed. Rounds 1-5 shot all six cameras; from round 6
# only these three are taken, to keep this machine usable. The camera numbers and
# names are unchanged, so a given file name still means the same eye.
#
# Capture is one-shot: a niced headless Chrome for Testing is launched per frame and
# exits when the file is written. No long-lived browser, nothing that can surface a
# window on the operator's screen. All poem-world workers share one mkdir lock, so at
# most one Chrome exists on this machine at a time.
set -e
W="${1:?usage: shoot.sh <world-dir> <round> [port]}"
R="${2:?round number}"
PORT="${3:-8731}"
CAMS="1-arrival 2-children 6-above"
OUT="$W/shots/$R"
LOCK=/tmp/poem-world-shot.lock
CTF="${POEM_WORLD_CHROME:-/Users/chener/.cache/puppeteer/chrome/mac_arm-150.0.7871.24/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"

[ -x "$CTF" ] || { echo "no Chrome for Testing at: $CTF" >&2; exit 1; }
mkdir -p "$OUT"

# Never open a browser on a machine that is already loaded: three workers running
# at once have put this one into the high teens before.
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
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

for c in $CAMS; do
  n="${c%%-*}"
  prof=$(mktemp -d /tmp/pw-shot-profile.XXXXXX)
  nice -n 10 "$CTF" --headless=new --disable-gpu --use-angle=swiftshader \
         --hide-scrollbars --mute-audio --no-first-run --no-default-browser-check \
         --disable-extensions --disable-background-networking \
         --user-data-dir="$prof" \
         --window-size=960,600 --virtual-time-budget=30000 \
         --screenshot="$PWD/$OUT/$c.png" \
         "http://127.0.0.1:$PORT/$W/index.html?shot=$n" >/dev/null 2>&1 || true
  rm -rf "$prof"
  [ -s "$OUT/$c.png" ] || { echo "  FAILED: $OUT/$c.png" >&2; exit 1; }
  echo "  $OUT/$c.png"
done
echo "round $R: 3 shots in $OUT"
