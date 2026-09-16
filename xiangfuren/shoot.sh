#!/usr/bin/env bash
# 固定 6 机位截图。用法： ./shoot.sh <round>
# 机位一旦定下就不再改，这样每轮的图可以直接并排比较。
#
# 一次性 headless：每张图起一个 Chrome for Testing，截完进程就退出，不留常驻实例。
# 三个世界共用一把 mkdir 锁，任何时刻至多一个 CTF 在跑。
set -euo pipefail
ROUND="${1:?usage: shoot.sh <round>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/xiangfuren/shots/$ROUND"
PORT="${PORT:-8793}"
BASE="http://127.0.0.1:$PORT/xiangfuren/index.html"
LOCK="/tmp/poem-world-shot.lock"
CTF="${CTF:-/Users/chener/.cache/puppeteer/chrome/mac_arm-150.0.7871.24/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"

mkdir -p "$OUT"

# 机器忙就别开浏览器：一分钟 load < 8，且空闲内存 > 30%
wait_for_machine() {
  for _ in $(seq 1 40); do
    load=$(uptime | sed 's/.*load averages*: *//' | awk '{print $1}' | tr -d ',')
    free=$(memory_pressure 2>/dev/null | awk -F: '/System-wide memory free percentage/ {gsub(/[ %]/,"",$2); print $2}')
    ok=1
    [ -n "${load:-}" ] && awk "BEGIN{exit !($load >= 8)}" && ok=0
    [ -n "${free:-}" ] && [ "$free" -lt 30 ] && ok=0
    [ "$ok" = 1 ] && return 0
    echo "machine busy (load=${load:-?} free=${free:-?}%), waiting 60s"
    python3 -c "import time; time.sleep(60)"
  done
}
lock() {
  for _ in $(seq 1 240); do
    if mkdir "$LOCK" 2>/dev/null; then trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT; return 0; fi
    python3 -c "import time; time.sleep(5)"
  done
  echo "could not take $LOCK" >&2; return 1
}

# name|cam=x,z,yaw,pitch
# 本机吃紧，从 round 5 起减到三个机位（原来的 1 / 5 / 6），其余不变。
CAMS=(
  "1-beizhu|2,-58,0,-0.05"          # 帝子降兮北渚 — on the shoal, the net still in the tree
  "5-chengwang|0,-62,3.1416,-0.06"  # 登白薠兮骋望 — from the high sedge, across to the house
  "6-dengdai|-70,46,-0.575,-0.02"   # 时不可兮骤得 — far off on the water, still waiting
)

wait_for_machine
lock
for entry in "${CAMS[@]}"; do
  name="${entry%%|*}"; cam="${entry##*|}"
  prof="$(mktemp -d)"
  nice -n 10 "$CTF" --headless=new --disable-gpu --use-angle=swiftshader \
    --hide-scrollbars --no-first-run --no-default-browser-check \
    --user-data-dir="$prof" --window-size=960,600 \
    --virtual-time-budget=4000 \
    --screenshot="$OUT/$name.png" "$BASE?cam=$cam&shot=1" >/dev/null 2>&1 || true
  rm -rf "$prof"
  sips -Z 960 "$OUT/$name.png" --out "$OUT/$name.png" >/dev/null 2>&1 || true
  echo "shot $name"
done
echo "-> $OUT"
