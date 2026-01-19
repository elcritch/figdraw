--nimcache: ".nimcache/"
--passc: "-Wno-incompatible-function-pointer-types"

import std/[os, strformat, strutils]

task buildWebGL, "build emscripten/WebGL bundle for FigDraw example":
  if findExe("emcc").len == 0:
    echo "Missing `emcc` (Emscripten). Install/activate Emscripten, then re-run."
    quit(2)

  when defined(windows):
    const emccExe = "emcc.bat"
  else:
    const emccExe = "emcc"

  let
    outDir = "examples/emscripten"
    outJs = outDir / "opengl_windy_renderlist_webgl.js"
    nimcache = ".nimcache/emscripten_opengl_windy_renderlist_webgl"

  mkDir(outDir)

  let cmd = (&"""
nim c -d:emscripten -d:useOpenGlEs \
  --os:linux --cpu:wasm32 --cc:clang \
  --clang.exe:{emccExe} --clang.linkerexe:{emccExe} \
  --mm:arc --exceptions:goto -d:release -d:noSignalHandler -d:noAutoGLerrorCheck \
  --nimcache:{nimcache} \
  --passL:"-s USE_WEBGL2=1 -s MAX_WEBGL_VERSION=2 -s MIN_WEBGL_VERSION=1 -s FULL_ES3=1 -s GL_ENABLE_GET_PROC_ADDRESS=1 -s ALLOW_MEMORY_GROWTH" \
  -o:{outJs} \
  examples/opengl_windy_renderlist_webgl.nim
""").strip().replace("\n", " ")
  exec(cmd)

task test, "run unit test":
  exec("nim r tests/timage_loading.nim")
  exec("nim r tests/tfontutils.nim")
  exec("nim r tests/ttransfer.nim")
  exec("nim r tests/trender_image.nim")
  exec("nim r tests/trender_rgb_boxes.nim")
  exec("nim r tests/trender_rgb_boxes_sdf.nim")

  exec("nim c examples/opengl_windy_renderlist.nim")
  exec("nim c examples/opengl_windy_renderlist_webgl.nim")
  exec("nim c examples/opengl_windy_renderlist_100.nim")
  exec("nim c examples/opengl_windy_image_renderlist.nim")
  exec("nim c examples/opengl_windy_text.nim")
  exec("nim c examples/sdl2_renderlist.nim")
  exec("nim c examples/sdl2_renderlist_100.nim")
