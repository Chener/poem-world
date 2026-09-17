#!/bin/sh
#   sh chunjiang/shots.sh <round> [port]
exec sh "$(cd "$(dirname "$0")" && pwd)/../shared/shoot.sh" chunjiang "$@"
