#!/bin/sh
#   sh gitanjali-60/shots.sh <round> [port]
exec sh "$(cd "$(dirname "$0")" && pwd)/../shared/shoot.sh" gitanjali-60 "$@"
