--nimcache: ".nimcache/"
--passc: "-Wno-incompatible-function-pointer-types"

task test, "run unit test":
  exec("nim r tests/timage_loading.nim")
  exec("nim r tests/ttransfer.nim")
  exec("nim r tests/trender_image.nim")
  exec("nim r tests/trender_rgb_boxes.nim")
  exec("nim r tests/trender_rgb_boxes_sdf.nim")
  exec("nim c examples/opengl_windy_renderlist.nim")
  exec("nim c examples/opengl_windy_image_renderlist.nim")
  exec("nim c examples/sdl2_renderlist.nim")
