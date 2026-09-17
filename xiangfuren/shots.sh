#!/bin/sh
#   sh xiangfuren/shots.sh <round> [port]
# POLISH.md still calls ./shoot.sh; that file is a thin alias of this one.
exec sh "$(cd "$(dirname "$0")" && pwd)/../shared/shoot.sh" xiangfuren "$@"
