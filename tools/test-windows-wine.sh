#!/bin/sh
set -eu

figdrawRoot=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
figdrawDockerContext=${FIGDRAW_DOCKER_CONTEXT:-docker1}
figdrawImage=${FIGDRAW_WINDOWS_WINE_IMAGE:-figdraw/windows-wine-test:debian13}
figdrawContainer=

cleanup() {
  if [ -n "$figdrawContainer" ]; then
    docker --context "$figdrawDockerContext" rm -f "$figdrawContainer" >/dev/null 2>&1 || true
    figdrawContainer=
  fi
}
trap cleanup EXIT HUP INT TERM

docker context inspect "$figdrawDockerContext" >/dev/null
docker --context "$figdrawDockerContext" build \
  --tag "$figdrawImage" \
  "$figdrawRoot/tools/windows-wine"

figdrawContainer=$(docker --context "$figdrawDockerContext" create "$figdrawImage")
docker --context "$figdrawDockerContext" cp \
  "$figdrawRoot/src" "$figdrawContainer:/work/src"
docker --context "$figdrawDockerContext" cp \
  "$figdrawRoot/tests/tsystemfonts_windows.nim" \
  "$figdrawContainer:/work/tests/tsystemfonts_windows.nim"
docker --context "$figdrawDockerContext" start --attach "$figdrawContainer"
