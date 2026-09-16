#!/usr/bin/env bash
# 固定 6 机位截图。用法： ./shoot.sh <round>
# 机位一旦定下就不再改，这样每轮的图可以直接并排比较。
set -euo pipefail
ROUND="${1:?usage: shoot.sh <round>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/xiangfuren/shots/$ROUND"
PORT="${PORT:-8793}"
BASE="http://127.0.0.1:$PORT/xiangfuren/index.html"

export CHROME_DEVTOOLS_AXI_SESSION="${CHROME_DEVTOOLS_AXI_SESSION:-xiangfuren}"
export CHROME_DEVTOOLS_AXI_HEADED="${CHROME_DEVTOOLS_AXI_HEADED:-1}"
export CHROME_DEVTOOLS_AXI_CHROME_ARGS="${CHROME_DEVTOOLS_AXI_CHROME_ARGS:---enable-gpu --ignore-gpu-blocklist}"

mkdir -p "$OUT"

# name|cam=x,z,yaw,pitch
CAMS=(
  "1-beizhu|2,-58,0,-0.05"          # 帝子降兮北渚 — standing on the shoal, facing north
  "2-dongtingbo|0,20,2.564,0.085"   # 洞庭波 — out on the water, into the low sun
  "3-muyexia|-4,-18,0.9,0.52"       # 木叶下 — looking up, the leaves coming down
  "4-jiuyi|14,74,3.1416,0.02"       # 九嶷缤兮并迎 — the nine peaks on the southern rim
  "5-chengwang|0,-62,3.1416,-0.06"  # 登白薠兮骋望 — from the high sedge, gazing back
  "6-dengdai|-70,46,-0.575,-0.02"   # 时不可兮骤得 — far off on the water, still waiting
)

for entry in "${CAMS[@]}"; do
  name="${entry%%|*}"; cam="${entry##*|}"
  chrome-devtools-axi open "$BASE?cam=$cam" >/dev/null 2>&1 || chrome-devtools-axi open "$BASE?cam=$cam" >/dev/null 2>&1 || true
  chrome-devtools-axi resize 1440 900 >/dev/null 2>&1 || true
  chrome-devtools-axi eval "(() => { document.getElementById('enter').classList.add('gone'); document.getElementById('tl').classList.add('collapsed'); document.getElementById('hint').style.display = 'none'; return 'ok' })()" >/dev/null 2>&1 || true
  python3 -c "import time; time.sleep(3.0)"
  chrome-devtools-axi screenshot "$OUT/$name.png" >/dev/null 2>&1 || chrome-devtools-axi screenshot "$OUT/$name.png" >/dev/null 2>&1
  sips -Z 1100 "$OUT/$name.png" --out "$OUT/$name.png" >/dev/null 2>&1 || true
  echo "shot $name"
done
echo "-> $OUT"
