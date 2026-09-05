#!/bin/sh
set -eu

export WINEARCH=win64
export WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEPREFIX=/tmp/figdraw-wine
export XDG_RUNTIME_DIR=/tmp/figdraw-xdg

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

test -f /work/tests/tsystemfonts_windows.nim
test -d /work/src

nim c \
  --os:windows \
  --cpu:amd64 \
  --cc:gcc \
  --gcc.exe:x86_64-w64-mingw32-gcc \
  --gcc.linkerexe:x86_64-w64-mingw32-gcc \
  --mm:arc \
  --threads:on \
  --path:/work/src \
  --nimcache:/tmp/figdraw-windows-nimcache \
  --out:/tmp/tsystemfonts_windows.exe \
  /work/tests/tsystemfonts_windows.nim

wineboot --init
wineserver --wait
wine /tmp/tsystemfonts_windows.exe
wineserver --wait
