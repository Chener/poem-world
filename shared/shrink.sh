#!/bin/sh
# Shrink a round's shots for model eyes: longest edge <= 1024, JPEG quality ~70.
#   sh shared/shrink.sh <in-dir> [out-dir] [max-edge] [quality]
# Default out-dir is <in-dir>/small. Source PNGs are never touched — the site
# and the byte-for-byte reproducibility check still use them.
#
# Why this exists: a 960x600 PNG is 250-530KB (base64 ~1.3x that on the wire);
# the same frame as a q70 JPEG is 55-100KB. Only these JPEGs are ever handed to
# a model. See AGENTS.md "上行流量".
set -e
IN="${1:?usage: shrink.sh <in-dir> [out-dir] [max-edge] [quality]}"
OUT="${2:-$IN/small}"
MAX="${3:-1024}"
Q="${4:-70}"
[ -d "$IN" ] || { echo "no such dir: $IN" >&2; exit 1; }
mkdir -p "$OUT"
n=0
for f in "$IN"/*.png; do
  [ -f "$f" ] || continue
  b=$(basename "$f" .png)
  sips -s format jpeg -s formatOptions "$Q" -Z "$MAX" "$f" --out "$OUT/$b.jpg" >/dev/null
  n=$((n + 1))
done
[ "$n" -gt 0 ] || { echo "no PNGs in $IN" >&2; exit 1; }
echo "$OUT"
