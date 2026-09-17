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
#
# HEADLESS ONLY. POEM_SHOT_BACKEND: headless-gpu (default) | swiftshader.
# There is no headed fallback: a headed Chrome steals a screen from whoever is
# using this machine. headless-gpu failing is retried once on the same backend;
# if that fails too the round has no shots and the script exits 2 so the caller
# can log the round blocked.
#
# QoS: taskpolicy -c background, nice -n 20. Shared mkdir lock so at most one
# render process exists on this machine. No resident browser, and nothing this
# script started outlives it: every exit, timeout and signal path kills the
# Chrome tree and cdp_shot.py (see cleanup() below).
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

case "$BACKEND" in
  headless-gpu|swiftshader) ;;
  *)
    echo "POEM_SHOT_BACKEND=$BACKEND refused: screenshots are headless-only" >&2
    exit 1
    ;;
esac

[ -x "$CTF" ] || { echo "no Chrome for Testing at: $CTF" >&2; exit 1; }
[ -x "$HERE/cdp_shot.py" ] || { echo "missing $HERE/cdp_shot.py" >&2; exit 1; }

# name:arg passed to window.__poemShot. Index worlds take a camera number;
# xiangfuren takes x,z,yaw,pitch (the same cam= string as before).
. "$HERE/cams.sh"
world_cams "$W" || exit 1
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
CAPPID=""
# Chrome runs in its own session (cdp_shot.py sets start_new_session), so it is
# not in our process group and a group kill does not reach it. cdp_shot.py
# writes its browser pid here and uses this exact profile dir, which gives us
# two independent ways to reap it even after a SIGKILL skipped its own cleanup.
RUNDIR=$(mktemp -d "/tmp/pw-shot-run-$$-XXXXXX")
PIDFILE="$RUNDIR/chrome.pid"
PROFILE="$RUNDIR/profile"

kill_pg() {
  # SIGTERM the process group led by $1, then SIGKILL what is still there.
  kill -TERM "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null || true
  i=0
  while [ "$i" -lt 20 ]; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.25
    i=$((i + 1))
  done
  kill -KILL "-$1" 2>/dev/null || kill -KILL "$1" 2>/dev/null || true
}

cleanup() {
  # Order matters: stop the capture wrapper first so it cannot respawn Chrome,
  # then the browser it left behind, then the sweep, then the lock.
  [ -n "$CAPPID" ] && kill_pg "$CAPPID" || true
  if [ -s "$PIDFILE" ]; then
    cpid=$(cat "$PIDFILE" 2>/dev/null)
    case "$cpid" in
      ''|*[!0-9]*) ;;
      *) kill_pg "$cpid" ;;
    esac
  fi
  # Belt and braces: anything still holding this round's profile is ours.
  pkill -KILL -f "user-data-dir=$PROFILE" 2>/dev/null || true
  [ -n "$SRV" ] && kill "$SRV" 2>/dev/null || true
  rm -rf "$RUNDIR" 2>/dev/null || true
  rmdir "$LOCK" 2>/dev/null || true
}
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

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
  : > "$PIDFILE"
  rm -rf "$PROFILE"
  set --
  for s in $SHOTS; do
    set -- "$@" --shot "$s"
  done
  # perl is the timeout: it forks the python into its own process group and,
  # when the alarm fires, kills that whole group instead of just walking away —
  # a bare `alarm` + `system` left cdp_shot.py (and its Chrome) reparented to
  # init. cdp_shot.py kills its own Chrome on SIGTERM; PIDFILE covers the rest.
  TP=""
  command -v taskpolicy >/dev/null 2>&1 && TP="taskpolicy -c background"
  # shellcheck disable=SC2086
  $TP nice -n 20 perl -e '
      my $t = shift @ARGV;
      my $pid = fork();
      die "fork: $!" unless defined $pid;
      if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127; }
      $SIG{ALRM} = sub {
        kill("TERM", -$pid);
        select(undef, undef, undef, 3);
        kill("KILL", -$pid);
        waitpid($pid, 0);
        exit 124;
      };
      $SIG{$_} = sub { kill("TERM", -$pid); waitpid($pid, 0); exit 143 } for qw(TERM INT HUP);
      alarm $t;
      waitpid($pid, 0);
      my $e = $?;
      alarm 0;
      exit($e == -1 ? 127 : ($e & 127 ? 1 : $e >> 8));
    ' \
    "$SHOT_ALARM" python3 "$HERE/cdp_shot.py" --backend "$backend" --load "$LOAD" \
    --outdir "$OUT" --chrome "$CTF" --timeout "$SHOT_ALARM" \
    --profile "$PROFILE" --pidfile "$PIDFILE" "$@" &
  CAPPID=$!
  # Backgrounded + wait, not foreground, so a signal to this script runs the
  # trap now instead of after the capture finishes.
  rc=0
  wait "$CAPPID" || rc=$?
  CAPPID=""
  return "$rc"
}

# One backend, one retry, no headed anything.
ok=0
if run_capture "$BACKEND"; then
  ok=1
else
  echo "  $BACKEND failed; retrying $BACKEND once" >&2
  run_capture "$BACKEND" && ok=1
fi

missing=""
for s in $SHOTS; do
  name=${s%%:*}
  [ -s "$OUT/$name.png" ] || missing="$missing $name"
done
if [ "$ok" -ne 1 ] || [ -n "$missing" ]; then
  echo "  TIMED OUT or failed on $BACKEND (twice):$missing" >&2
  echo "  no headed fallback — skip shots for round $R and log it blocked" >&2
  exit 2
fi
echo "round $R: 3 shots in $OUT"
echo "  do not Read these PNGs — run: sh shared/critic.sh $W $R"
