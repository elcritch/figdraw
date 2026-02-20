import std/os
import std/unittest

import pkg/chroma
import pkg/pixie
import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes

import ./opengl_test_utils

proc makeRenderTree(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(255, 255, 255, 255),
    )
  )

  discard list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(80, 80, 440, 120),
      corners: [12'u16, 12'u16, 12'u16, 12'u16],
      fill: linear(
        rgba(220, 40, 40, 255),
        rgba(40, 200, 90, 255),
        rgba(50, 90, 225, 255),
        axis = fgaX,
        midPos = 128'u8,
      ),
    ),
  )

  discard list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(80, 240, 220, 220),
      corners: [10'u16, 10'u16, 10'u16, 10'u16],
      fill: linear(rgba(240, 210, 40, 255), rgba(110, 60, 210, 255), axis = fgaY),
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc maxChannelDelta(a: ColorRGBX, r, g, b: uint8): int =
  result = max(abs(a.r.int - r.int), max(abs(a.g.int - g.int), abs(a.b.int - b.int)))

suite "opengl linear gradient render":
  test "renders 2-stop and 3-stop linear fills":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_linear_gradient.png"
    if fileExists(outPath):
      removeFile(outPath)

    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          title = "figdraw test: linear gradients",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let tol = 40
      check img[120, 140].maxChannelDelta(220, 40, 40) <= tol
      check img[300, 140].maxChannelDelta(40, 200, 90) <= tol
      check img[480, 140].maxChannelDelta(50, 90, 225) <= tol
      check img[190, 270].maxChannelDelta(240, 210, 40) <= tol
      check img[190, 430].maxChannelDelta(110, 60, 210) <= tol
