--nimcache: ".nimcache/"
--passc: "-Wno-incompatible-function-pointer-types"

task test, "run unit test":
  exec("nim r tests/timage_loading.nim")
  exec("nim r tests/tfontutils.nim")
  exec("nim r tests/ttransfer.nim")
  exec("nim r tests/trender_image.nim")
  exec("nim r tests/trender_rgb_boxes.nim")
  exec("nim r tests/trender_rgb_boxes_sdf.nim")

  exec("nim c examples/opengl_windy_renderlist.nim")
  exec("nim c examples/opengl_windy_renderlist_100.nim")
  exec("nim c examples/opengl_windy_image_renderlist.nim")
  exec("nim c examples/opengl_windy_text.nim")
  exec("nim c examples/sdl2_renderlist.nim")
  exec("nim c examples/sdl2_renderlist_100.nim")

task emscripten, "build emscripten examples":
  exec("nim c -d:emscripten examples/opengl_windy_renderlist.nim")
  exec("nim c -d:emscripten examples/opengl_windy_renderlist_100.nim")
  exec("nim c -d:emscripten examples/opengl_windy_image_renderlist.nim")
  exec("nim c -d:emscripten examples/opengl_windy_text.nim")
  exec("nim c -d:emscripten examples/opengl_windy_3d_overlay.nim")
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
