--nimcache: ".nimcache/"
--passc: "-Wno-incompatible-function-pointer-types"

import std/[os, strformat]

task buildWebGL, "build emscripten/WebGL bundle for FigDraw example":
  if findExe("emcc").len == 0:
    echo "Missing `emcc` (Emscripten). Install/activate Emscripten, then re-run."
    quit(2)

  mkDir("examples/emscripten")

  let forceFlag = if defined(figdrawForceWebGLBuild): " -f" else: ""
  exec(&"nim c -d:emscripten {forceFlag} examples/opengl_windy_renderlist_webgl.nim")

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
