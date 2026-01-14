--nimcache: ".nimcache/"
--passc:"-Wno-incompatible-function-pointer-types"

task test, "run unit test":
  exec("nim r tests/ttransfer.nim")
  exec("nim r tests/trender_rgb_boxes.nim")
  exec("nim r tests/trender_rgb_boxes_sdf.nim")
  #exec("nim r -d:figdraw.runOnce examples/opengl_windex_renderlist.nim")
