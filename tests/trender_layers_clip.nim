import std/os
import std/unittest

import pkg/chroma
import pkg/pixie
import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes

import ./opengl_test_utils

proc maxChannelDelta(a: ColorRGBX, r, g, b: uint8): int =
  result = max(abs(a.r.int - r.int), max(abs(a.g.int - g.int), abs(a.b.int - b.int)))

template assertColor(img: Image, x, y: int, r, g, b: uint8, tol: int = 10) =
  let px = img[x, y]
  check px.maxChannelDelta(r, g, b) <= tol

proc makeLayeringRenders(w, h: float32): Renders =
  var lowList = RenderList()
  discard lowList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-5).ZLevel,
      name: "layer-low".toFigName(),
      screenBox: rect(0, 0, w, h),
      fill: rgba(220, 40, 40, 255).color,
    )
  )

  var midList = RenderList()
  discard midList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "layer-mid".toFigName(),
      screenBox: rect(80, 40, 240, 160),
      fill: rgba(40, 180, 90, 255).color,
    )
  )

  var topList = RenderList()
  discard topList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 10.ZLevel,
      name: "layer-top".toFigName(),
      screenBox: rect(160, 80, 120, 80),
      fill: rgba(60, 90, 220, 255).color,
    )
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[(-5).ZLevel] = lowList
  result.layers[0.ZLevel] = midList
  result.layers[10.ZLevel] = topList
  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )

proc makeClippingRenders(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "root".toFigName(),
      screenBox: rect(0, 0, w, h),
      fill: rgba(230, 230, 230, 255).color,
    )
  )

  let leftIdx = list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "left-container".toFigName(),
      screenBox: rect(40, 50, 200, 200),
      fill: rgba(200, 200, 200, 255).color,
    ),
  )

  discard list.addChild(
    leftIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "left-overflow".toFigName(),
      screenBox: rect(20, 120, 260, 60),
      fill: rgba(220, 60, 60, 255).color,
    ),
  )

  let rightIdx = list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "right-container".toFigName(),
      screenBox: rect(360, 50, 200, 200),
      fill: rgba(200, 200, 200, 255).color,
      flags: {NfClipContent},
    ),
  )

  discard list.addChild(
    rightIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "right-overflow".toFigName(),
      screenBox: rect(340, 120, 260, 60),
      fill: rgba(60, 120, 220, 255).color,
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "opengl layer + clip render":
  test "renders layers by zlevel":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_layers.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeLayeringRenders,
          outputPath = outPath,
          windowW = 400,
          windowH = 240,
          title = "figdraw test: layering",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      assertColor(img, 20, 20, 220, 40, 40)
      assertColor(img, 100, 60, 40, 180, 90)
      assertColor(img, 200, 120, 60, 90, 220)

  test "clips child content when requested":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_clip.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeClippingRenders,
          outputPath = outPath,
          windowW = 640,
          windowH = 320,
          title = "figdraw test: clipping",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      assertColor(img, 80, 140, 220, 60, 60)
      assertColor(img, 30, 140, 220, 60, 60)
      assertColor(img, 420, 140, 60, 120, 220)
      assertColor(img, 350, 140, 230, 230, 230)
