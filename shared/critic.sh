#!/bin/sh
# Blind aesthetic gate, in a throwaway subprocess. The loop worker NEVER reads
# the shots itself — it runs this and reads the JSON on stdout.
#
#   sh shared/critic.sh <world> <round> [n-images]
#
# Why a subprocess: every Claude API request re-uploads every image still in the
# session context. One 300KB PNG read by the loop worker is re-sent on every
# later turn of that session, so 200+ shots saturated the uplink. A `claude -p`
# process is born, looks at 1-2 small JPEGs, prints text, and dies — the bytes
# go up once and never enter the loop worker's context at all.
#
# Blindness: this process runs with cwd in /tmp and Read as its only tool, so it
# cannot see index.html, the diff, log.jsonl, or anything the builder wrote. It
# gets the poem, the scoring rubric, and the pictures. That is the whole point of
# the Gauntlet critic and it is preserved here.
#
# Env: POEM_CRITIC_MODEL (default claude-opus-5 — never a *-fast model),
#      POEM_CRITIC_MAX (max images, default 2), POEM_CRITIC_TIMEOUT (default 300s),
#      POEM_CRITIC_ASK (one extra question for this round, answered in "ask").
#      Ralph uses POEM_CRITIC_ASK for its per-round self-check ("is this todo
#      visible?") so the worker never has to open a frame to answer it.
set -e
W="${1:?usage: critic.sh <world-dir> <round> [n-images]}"
R="${2:?round number}"
N="${3:-${POEM_CRITIC_MAX:-2}}"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SHOTS="$ROOT/$W/shots/$R"
POEM="$ROOT/$W/POEM.md"
MODEL="${POEM_CRITIC_MODEL:-claude-opus-5}"
TMO="${POEM_CRITIC_TIMEOUT:-300}"
WORK="/tmp/poem-world-critic/$W/$R"

[ -d "$SHOTS" ] || { echo "no shots for round $R: $SHOTS" >&2; exit 1; }
[ -f "$POEM" ] || { echo "no POEM.md: $POEM" >&2; exit 1; }
case "$MODEL" in *-fast) echo "critic must not run on a *-fast model" >&2; exit 1 ;; esac

rm -rf "$WORK"
mkdir -p "$WORK"
sh "$HERE/shrink.sh" "$SHOTS" "$WORK" >/dev/null

# At most N images per round. Rotate the window by round so every camera is
# looked at over a few rounds without ever sending three frames at once.
ALL=$(ls "$WORK"/*.jpg | sort)
TOTAL=$(echo "$ALL" | wc -l | tr -d ' ')
[ "$N" -lt "$TOTAL" ] || N="$TOTAL"
START=$(( (R - 1) % TOTAL ))
PICK=""
i=0
while [ "$i" -lt "$N" ]; do
  idx=$(( (START + i) % TOTAL + 1 ))
  PICK="$PICK$(echo "$ALL" | sed -n "${idx}p")
"
  i=$((i + 1))
done
# Delete the frames we are not sending, so nothing extra can be picked up.
for f in $ALL; do
  echo "$PICK" | grep -qxF "$f" || rm -f "$f"
done

LIST=$(echo "$PICK" | sed '/^$/d')
ASK_LINE=""
ASK_FIELD=""
if [ -n "${POEM_CRITIC_ASK:-}" ]; then
  ASK_LINE="额外回答一个问题（只看图回答，看不出来就说看不出来）：${POEM_CRITIC_ASK}

"
  ASK_FIELD=', "ask": "<对上面那个额外问题的回答，一句话>"'
fi
PROMPT=$(cat <<EOF
你是一个盲评 critic。你没有看过任何代码、任何 diff、任何作者的解释，也不要去找。
下面是一首诗，和照着它做的一个「可以走进去的世界」这一轮的真实截图。

请先用 Read 工具逐一读这些图片：
$LIST

$(cat "$POEM")

评分口径 —— 不要评价画面好不好看、技术难不难。只评价一件事：
一个读过这首诗的人走进这个世界，会不会认出这是这首诗。
10 = 会，而且这个世界让他看见了读诗时没看见的东西。
7 = 会认出，但有一处明显不对。
5 = 是个场景，但换成任何一首同题材的诗都成立。
3 = 认不出。 0 = 和诗相反。

${ASK_LINE}只输出一行 JSON，不要任何别的字：
{"score": <0-10 数字>, "verdict": "到位" | "还不像", "critic": "<两三句原话，指出最要命的那一处>", "gap": "<下一轮最该补的一个缺口，一句话>"${ASK_FIELD}}
EOF
)

cd "$WORK"
OUT=$(perl -e 'alarm shift @ARGV; $e = system @ARGV; exit($e == -1 ? 127 : ($e & 127 ? 1 : $e >> 8))' \
  "$TMO" claude -p "$PROMPT" --model "$MODEL" --allowed-tools Read --output-format text) || {
  echo "critic subprocess failed or timed out" >&2
  exit 2
}
echo "$OUT" | tr -d '\r' | grep -o '{.*}' | tail -1
