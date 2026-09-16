#!/bin/bash
# 固定 6 机位截图。用法: ./shots.sh N   （输出 shots/N/1..6.png）
set -e
N="${1:?round number}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/shots/$N"; mkdir -p "$OUT"
BASE="${DUINO_BASE:-http://127.0.0.1:8732/duino-1/index.html}"
export CHROME_DEVTOOLS_AXI_SESSION="${CHROME_DEVTOOLS_AXI_SESSION:-duino1}"

# 机位固定不变，便于逐轮对比
CAMS=(
  "0,24,3.1416,-0.02"      # 1 正对悬崖上的城堡与天使的序列
  "14,-4,3.7,-0.04"        # 2 山坡上的树
  "-16,2,2.35,-0.02"       # 3 敞开的窗
  "-8,-24,3.35,0.06"       # 4 被丢开的名字，远处天使
  "20,20,2.0,-0.02"        # 5 空房间
  "-22,-48,3.95,0.14"      # 6 贴近天使序列的仰视
)
chrome-devtools-axi resize 1440 900 >/dev/null 2>&1 || true
i=1
for c in "${CAMS[@]}"; do
  chrome-devtools-axi open "$BASE?cam=$c&still=1" >/dev/null
  sleep 1.5
  chrome-devtools-axi screenshot "$OUT/$i.png" >/dev/null
  echo "shot $i -> $OUT/$i.png"
  i=$((i+1))
done
