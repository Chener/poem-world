#!/usr/bin/env bash
# 固定 3 机位截图。用法： ./shoot.sh <round>
# 机位一旦定下就不再改，这样每轮的图可以直接并排比较。
#
# 规矩（船长 2026-09-17 的两条裁决）：
#   - 一次性：浏览器只在这个脚本里活着，最后一定 stop，绝不留常驻实例
#   - 每张图有墙钟硬超时；超时记失败、跳过，不空等
#   - 三个世界共用 mkdir 锁 /tmp/poem-world-shot.lock，同一时刻至多一个浏览器
#   - 开工前自查：一分钟 load < 8 且内存空闲 > 30%
#   - 渲染进程 nice -n 10
#
# 为什么不是 Chrome for Testing 一次性 --screenshot：这台机器上那条路走不通。
# 实测同一份 CTF（mac_arm-150.0.7871.24）连 `--headless=new --dump-dom file:///tmp/plain.html`
# 都会挂满墙钟、什么都不输出（--headless=old / --headless 同样），所以 --screenshot 永远拿不到文件。
# 这里改用 chrome-devtools-axi 拍完立刻 stop：一次性、有超时、不留常驻，和裁决的要求一致。
set -euo pipefail
ROUND="${1:?usage: shoot.sh <round>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/xiangfuren/shots/$ROUND"
PORT="${PORT:-8793}"
BASE="http://127.0.0.1:$PORT/xiangfuren/index.html"
LOCK="/tmp/poem-world-shot.lock"
SHOT_TIMEOUT="${SHOT_TIMEOUT:-90}"

export CHROME_DEVTOOLS_AXI_SESSION="${CHROME_DEVTOOLS_AXI_SESSION:-xiangfuren}"
export CHROME_DEVTOOLS_AXI_HEADED=0

mkdir -p "$OUT"

cleanup() {
  chrome-devtools-axi stop >/dev/null 2>&1 || true
  pkill -9 -f "CHROME_DEVTOOLS_AXI_SESSION=xiangfuren" 2>/dev/null || true
  rmdir "$LOCK" 2>/dev/null || true
}

# 机器忙就别开浏览器：一分钟 load < 8，且空闲内存 > 30%
wait_for_machine() {
  for _ in $(seq 1 30); do
    load=$(uptime | sed 's/.*load averages*: *//' | awk '{print $1}' | tr -d ',')
    free=$(memory_pressure 2>/dev/null | awk -F: '/System-wide memory free percentage/ {gsub(/[ %]/,"",$2); print $2}')
    ok=1
    [ -n "${load:-}" ] && awk "BEGIN{exit !($load >= 8)}" && ok=0
    [ -n "${free:-}" ] && [ "$free" -lt 30 ] && ok=0
    [ "$ok" = 1 ] && return 0
    echo "machine busy (load=${load:-?} free=${free:-?}%), waiting 60s"
    python3 -c "import time; time.sleep(60)"
  done
  echo "machine stayed busy; skipping this round's shots" >&2
  return 1
}

cap() { perl -e 'alarm shift; exec @ARGV' "$SHOT_TIMEOUT" nice -n 10 "$@" >/dev/null 2>&1 || true; }

# name|cam=x,z,yaw,pitch
CAMS=(
  "1-beizhu|2,-58,0,-0.05"          # 帝子降兮北渚 — on the shoal, the net still in the tree
  "5-chengwang|0,-62,3.1416,-0.06"  # 登白薠兮骋望 — from the high sedge, across to the house
  "6-dengdai|-70,46,-0.575,-0.02"   # 时不可兮骤得 — far off on the water, still waiting
)

wait_for_machine || exit 3
for _ in $(seq 1 60); do mkdir "$LOCK" 2>/dev/null && break; python3 -c "import time; time.sleep(5)"; done
[ -d "$LOCK" ] || { echo "could not take $LOCK" >&2; exit 4; }
trap cleanup EXIT

fail=0
for entry in "${CAMS[@]}"; do
  name="${entry%%|*}"; cam="${entry##*|}"
  cap chrome-devtools-axi open "$BASE?cam=$cam&shot=1"
  cap chrome-devtools-axi resize 960 600
  cap chrome-devtools-axi open "$BASE?cam=$cam&shot=1"
  cap chrome-devtools-axi screenshot "$OUT/$name.png"
  sips -Z 960 "$OUT/$name.png" --out "$OUT/$name.png" >/dev/null 2>&1 || true
  if [ -s "$OUT/$name.png" ]; then echo "shot $name"; else echo "FAILED $name"; fail=1; fi
done
echo "-> $OUT"
exit "$fail"
