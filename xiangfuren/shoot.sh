#!/bin/sh
# 固定 3 机位截图。用法： ./shoot.sh <round> [port]
# 真正的捕获在 shared/shoot.sh（共用锁、CDP、一次进程三机位）。
exec sh "$(cd "$(dirname "$0")" && pwd)/shots.sh" "$@"
