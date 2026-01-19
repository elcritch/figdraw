import os, strformat, strutils

const outDir = "examples/emscripten"
mkDir(outDir)

--os:linux
--cpu:wasm32
--cc:clang

when defined(windows):
  --clang.exe:emcc.bat
  --clang.linkerexe:emcc.bat
  --clang.cpp.exe:emcc.bat
  --clang.cpp.linkerexe:emcc.bat
else:
  --clang.exe:emcc
  --clang.linkerexe:emcc
  --clang.cpp.exe:emcc
  --clang.cpp.linkerexe:emcc

--mm:arc
--exceptions:goto
--define:noSignalHandler
--define:noAutoGLerrorCheck
--define:release
--define:useOpenGlEs
--nimcache:.nimcache/emscripten_opengl_windy_renderlist_webgl
--out:examples/emscripten/opengl_windy_renderlist_webgl.js

switch("passL", "-s USE_WEBGL2=1")
switch("passL", "-s MAX_WEBGL_VERSION=2")
switch("passL", "-s MIN_WEBGL_VERSION=1")
switch("passL", "-s FULL_ES3=1")
switch("passL", "-s GL_ENABLE_GET_PROC_ADDRESS=1")
switch("passL", "-s ALLOW_MEMORY_GROWTH")

