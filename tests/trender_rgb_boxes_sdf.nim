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

  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      corners: [10'u16, 20'u16, 30'u16, 40'u16],
      screenBox: rect(60, 60, 220, 140),
      fill: rgba(220, 40, 40, 255),
      stroke: RenderStroke(weight: 5.0, fill: rgba(0, 0, 0, 255).color),
    ),
  )
  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(320, 120, 220, 140),
      fill: rgba(40, 180, 90, 255),
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 10,
          spread: 10,
          x: 10,
          y: 10,
          fill: rgba(0, 0, 0, 55).color,
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )
  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(180, 300, 220, 140),
      fill: rgba(60, 90, 220, 255),
      shadows: [
        RenderShadow(
          style: InnerShadow,
          blur: 12,
          spread: 0,
          x: -6,
          y: -6,
          fill: rgba(55, 55, 55, 155).color,
        ),
        RenderShadow(
          style: InnerShadow,
          blur: 12,
          spread: 0,
          x: 6,
          y: 6,
          fill: rgba(255, 255, 255, 255).color,
        ),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc maxChannelDelta(a: ColorRGBX, r, g, b: uint8): int =
  result = max(abs(a.r.int - r.int), max(abs(a.g.int - g.int), abs(a.b.int - b.int)))

suite "opengl rgb boxes render (sdf)":
  test "renderAndSwap + screenshot":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_rgb_boxes_sdf.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          title = "figdraw test: rgb boxes (sdf)",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let expectedPath = "tests" / "expected" / "render_rgb_boxes.png"
      check fileExists(expectedPath)
      let expected = pixie.readImage(expectedPath)
      let (diffScore, diffImg) = expected.diff(img)
      echo "Got image difference of: ", diffScore
      let diffThreshold = 100'f32
      if diffScore > diffThreshold:
        diffImg.writeFile(joinPath(outDir, "render_rgb_boxes_sdf.diff.png"))
      check diffScore <= diffThreshold

      #let tol = 12
      #check img[10, 10].maxChannelDelta(255, 255, 255) <= tol
      #check img[120, 120].maxChannelDelta(220, 40, 40) <= tol
      #check img[400, 180].maxChannelDelta(40, 180, 90) <= tol
      #check img[260, 360].maxChannelDelta(60, 90, 220) <= tol
