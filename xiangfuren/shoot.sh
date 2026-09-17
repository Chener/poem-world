#!/usr/bin/env bash
# 固定 3 机位截图。用法： ./shoot.sh <round>
# 机位一旦定下就不再改，这样每轮的图可以直接并排比较。
#
# 规矩（船长 2026-09-17 的白天裁决，比前一天更紧）：
#   - 一次性：每帧一个 chrome-headless-shell 进程，写完文件自己退出，绝不留常驻实例
#   - 每帧 90 秒墙钟硬超时（perl alarm）；--virtual-time-budget=5000 让 WebGL 有时间收敛
#   - 三个世界共用 mkdir 锁 /tmp/poem-world-shot.lock，同一时刻至多一个浏览器
#   - 开工前自查：一分钟 load < 6 且内存空闲 > 40%，不满足等 60 秒再看
#   - 渲染进程 nice -n 15，不开可见窗口
#
# 为什么是 chrome-headless-shell 而不是完整的 Chrome for Testing：在这台机器上
# CTF 的 --screenshot 是死的（不写文件也不退出，about:blank 也一样）。
# chrome-headless-shell 是同版本同缓存里的 headless-only 产物，没有窗口可开，
# --screenshot 正常，文件写完立刻退出。
set -euo pipefail
ROUND="${1:?usage: shoot.sh <round>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/xiangfuren/shots/$ROUND"
PORT="${PORT:-8793}"
LOCK="/tmp/poem-world-shot.lock"
SHOT_ALARM="${SHOT_ALARM:-90}"
CTF="${POEM_WORLD_CHROME:-/Users/chener/.cache/puppeteer/chrome-headless-shell/mac_arm-150.0.7871.24/chrome-headless-shell-mac-arm64/chrome-headless-shell}"

[ -x "$CTF" ] || { echo "no chrome-headless-shell at: $CTF" >&2; exit 1; }
mkdir -p "$OUT"

# name|cam=x,z,yaw,pitch
CAMS=(
  "1-beizhu|2,-58,0,-0.05"          # 帝子降兮北渚 — on the shoal, the net still in the tree
  "5-chengwang|0,-62,3.1416,-0.06"  # 登白薠兮骋望 — from the high sedge, across to the house
  "6-dengdai|-70,46,-0.575,-0.02"   # 时不可兮骤得 — far off on the water, still waiting
)

# 机器忙就别开浏览器：船长白天在用这台电脑。
wait_for_machine() {
  for _ in $(seq 1 30); do
    load=$(uptime | sed -n 's/.*load averages*: *\([0-9.]*\).*/\1/p' | cut -d. -f1)
    free=$(memory_pressure 2>/dev/null | sed -n 's/.*memory free percentage: \([0-9]*\)%.*/\1/p')
    [ -z "${load:-}" ] && load=0
    [ -z "${free:-}" ] && free=100
    [ "$load" -lt 6 ] && [ "$free" -gt 40 ] && return 0
    echo "  machine busy (load ${load}, free ${free}%), waiting 60s..."
    sleep 60
  done
  echo "machine stayed busy for 30 minutes" >&2
  return 1
}

SRV=""
cleanup() {
  [ -n "$SRV" ] && kill "$SRV" 2>/dev/null || true
  rmdir "$LOCK" 2>/dev/null || true
}

wait_for_machine || exit 3

waited=0
until mkdir "$LOCK" 2>/dev/null; do
  waited=$((waited + 5))
  [ "$waited" -gt 1800 ] && { echo "shot lock held >30min: $LOCK" >&2; exit 4; }
  sleep 5
done
trap cleanup EXIT INT TERM

# 本地静态服务：file:// 下 log.jsonl 取不到，而且 fetch 被挡。
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/xiangfuren/index.html"; then
  ( cd "$ROOT" && nice -n 15 python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
  SRV=$!
  for _ in $(seq 1 40); do
    curl -sf -o /dev/null "http://127.0.0.1:$PORT/xiangfuren/index.html" && break
    sleep 0.25
  done
fi

fail=0
for entry in "${CAMS[@]}"; do
  name="${entry%%|*}"; cam="${entry##*|}"
  prof=$(mktemp -d /tmp/pw-shot-profile.XXXXXX)
  rm -f "$OUT/$name.png"
  nice -n 15 perl -e 'alarm shift; exec @ARGV' "$SHOT_ALARM" \
    "$CTF" --disable-gpu --use-angle=swiftshader \
    --hide-scrollbars --mute-audio --no-first-run --no-default-browser-check \
    --disable-extensions --disable-background-networking \
    --user-data-dir="$prof" \
    --window-size=960,600 --virtual-time-budget=5000 \
    --screenshot="$OUT/$name.png" \
    "http://127.0.0.1:$PORT/xiangfuren/index.html?cam=$cam&shot=1" >/dev/null 2>&1 || true
  rm -rf "$prof"
  if [ -s "$OUT/$name.png" ]; then echo "  shot $name"; else echo "  FAILED $name" >&2; fail=1; fi
done
echo "-> $OUT"
exit "$fail"
