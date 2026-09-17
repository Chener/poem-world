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
# chrome-headless-shell, NOT the full Chrome for Testing binary. In Chrome 150 the
# full binary's --screenshot flag is dead: it writes no file and never exits, even on
# about:blank (verified). chrome-headless-shell is the same version's headless-only
# artifact from the same puppeteer cache, it has no window to show, it still supports
# --screenshot, and it exits the moment the file is written - about four seconds a
# frame instead of hanging until the alarm.
#
# ANGLE backend: Metal, not SwiftShader. Measured on this machine, same scene, same
# frozen clock, one frame of camera 1:
#
#     --disable-gpu --use-angle=swiftshader   real 10.6s   cpu 19.6s
#     --use-angle=metal                       real  6.0s   cpu  2.0s
#
# SwiftShader rasterises on the cores the operator is using, and at 350-400% CPU it
# was pushing the network stack around; Metal hands the work to the GPU and costs a
# tenth of the CPU time. --disable-gpu must NOT be passed with it or the WebGL
# context never comes up and the page is captured still on its loading veil, which
# is what a 30KB screenshot means. SwiftShader stays as the fallback for any machine
# where the Metal context fails.
CTF="${POEM_WORLD_CHROME:-/Users/chener/.cache/puppeteer/chrome-headless-shell/mac_arm-150.0.7871.24/chrome-headless-shell-mac-arm64/chrome-headless-shell}"

[ -x "$CTF" ] || { echo "no chrome-headless-shell at: $CTF" >&2; exit 1; }
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
    if [ "$load" -lt 6 ] && [ "$free" -gt 40 ]; then return 0; fi
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

# Chrome for Testing has wedged for twenty minutes twice on this machine, so every
# capture gets a hard wall-clock ceiling. macOS has no timeout(1); perl's alarm does
# the job. --virtual-time-budget only needs to be long enough for three.js to settle,
# it is NOT a licence to hang until the frame is finished.
SHOT_ALARM=90

# taskpolicy -c background puts the whole process tree in the macOS background QoS
# class: efficiency cores, throttled I/O, and it yields to whatever the operator is
# doing in the foreground. This is a machine somebody is using during the day.
shoot_one() {
  _angle="$1"; _n="$2"; _dst="$3"
  _prof=$(mktemp -d /tmp/pw-shot-profile.XXXXXX)
  taskpolicy -c background nice -n 20 perl -e 'alarm shift; exec @ARGV' "$SHOT_ALARM" \
         "$CTF" $_angle \
         --hide-scrollbars --mute-audio --no-first-run --no-default-browser-check \
         --disable-extensions --disable-background-networking \
         --user-data-dir="$_prof" \
         --window-size=960,600 --virtual-time-budget=5000 \
         --screenshot="$_dst" \
         "http://127.0.0.1:$PORT/$W/index.html?shot=$_n" >/dev/null 2>&1 || true
  rm -rf "$_prof"
}

for c in $CAMS; do
  n="${c%%-*}"
  rm -f "$OUT/$c.png"
  shoot_one "--use-angle=metal" "$n" "$PWD/$OUT/$c.png"
  # a Metal context that never came up captures the loading veil: tens of KB, not
  # hundreds. Fall back rather than log a blank round.
  if [ ! -s "$OUT/$c.png" ] || [ "$(wc -c < "$OUT/$c.png")" -lt 120000 ]; then
    echo "  metal gave nothing usable for $c, falling back to swiftshader" >&2
    rm -f "$OUT/$c.png"
    shoot_one "--disable-gpu --use-angle=swiftshader" "$n" "$PWD/$OUT/$c.png"
  fi
  if [ ! -s "$OUT/$c.png" ]; then
    # Skip the rest of the round rather than wait: a wedged Chrome will not get
    # better on the next camera, and the loop is supposed to keep moving.
    rm -f "$OUT/$c.png"
    echo "  TIMED OUT or failed after ${SHOT_ALARM}s: $c — skipping this round's shots" >&2
    exit 2
  fi
  echo "  $OUT/$c.png"
done
echo "round $R: 3 shots in $OUT"
