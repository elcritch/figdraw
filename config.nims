--nimcache:
  ".nimcache/"
--passc:
  "-Wno-incompatible-function-pointer-types"

task test, "run unit test":
  exec("nim r tests/timage_loading.nim")
  exec("nim r tests/tfontutils.nim")
  exec("nim r tests/ttransfer.nim")
  exec("nim r tests/trender_image.nim")
  exec("nim r tests/trender_rgb_boxes.nim")
  exec("nim r tests/trender_rgb_boxes_sdf.nim")

  exec("nim c examples/windy_renderlist.nim")
  exec("nim c examples/windy_renderlist_100.nim")
  exec("nim c examples/windy_image_renderlist.nim")
  exec("nim c examples/windy_text.nim")
  exec("nim c -d:figdraw.metal=off examples/sdl2_renderlist.nim")
  exec("nim c -d:figdraw.metal=off examples/sdl2_renderlist_100.nim")

task emscripten, "build emscripten examples":
  exec("nim c -d:emscripten examples/windy_renderlist.nim")
  exec("nim c -d:emscripten examples/windy_renderlist_100.nim")
  exec("nim c -d:emscripten examples/windy_image_renderlist.nim")
  exec("nim c -d:emscripten examples/windy_text.nim")
  exec("nim c -d:emscripten examples/windy_3d_overlay.nim")

