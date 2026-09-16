#!/bin/sh
# Regenerate <world>/log.js (the file:// fallback) from <world>/log.jsonl.
# Run after every appended round:  sh ../shared/mklog.sh gitanjali-60
set -e
W="${1:?usage: mklog.sh <world-dir>}"
SRC="$W/log.jsonl"; OUT="$W/log.js"
{
  echo "/* Generated from log.jsonl by shared/mklog.sh — do not edit by hand."
  echo " * Exists only so the page still shows its timeline when opened over file://,"
  echo " * where fetch() of a sibling file is blocked. log.jsonl stays the source of truth. */"
  echo "window.__POEM_LOG__ = ["
  awk 'NF && $0 !~ /^#/ { if (n++) print ","; printf "%s", $0 } END { if (n) print "" }' "$SRC"
  echo "];"
} > "$OUT"
echo "wrote $OUT ($(awk 'NF && $0 !~ /^#/' "$SRC" | wc -l | tr -d " ") rounds)"
