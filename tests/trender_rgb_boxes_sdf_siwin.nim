import std/os
import std/unittest

import pkg/chroma
import pkg/pixie

import figdraw/commons
import figdraw/fignodes

import ./siwin_test_utils

proc makeRenderTree(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(255, 255, 255, 255).color,
    )
  )

  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      corners: [10.0'f32, 20.0, 30.0, 40.0],
      screenBox: rect(60, 60, 220, 140),
      fill: rgba(220, 40, 40, 255).color,
      stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 255).color),
    ),
  )
  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(320, 120, 220, 140),
      fill: rgba(40, 180, 90, 255).color,
      shadows: [
        RenderShadow(
          style: DropShadow, blur: 10, spread: 10, x: 10, y: 10, color: blackColor
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
      fill: rgba(60, 90, 220, 255).color,
      shadows: [
        RenderShadow(
          style: InnerShadow,
          blur: 14,
          spread: 6,
          x: 0,
          y: 6,
          color: rgba(0, 0, 0, 95).color,
        ),
        RenderShadow(
          style: InnerShadow,
          blur: 3,
          spread: 0,
          x: -2,
          y: -2,
          color: rgba(255, 255, 255, 75).color,
        ),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "siwin rgb boxes render (sdf)":
  test "renderAndSwap + screenshot":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_rgb_boxes_sdf_siwin.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          title = "figdraw test: rgb boxes (sdf, siwin)",
        )
      except ValueError:
        skip()
        break renderOnce

      img.writeFile(outPath)
      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let expectedPath = "tests" / "expected" / "render_rgb_boxes.png"
      check fileExists(expectedPath)
      let expected = pixie.readImage(expectedPath)
      let (diffScore, diffImg) = expected.diff(img)
      echo "Got image difference of: ", diffScore
      let diffThreshold = 100'f32
      if diffScore > diffThreshold:
        diffImg.writeFile(joinPath(outDir, "render_rgb_boxes_sdf_siwin.diff.png"))
      check diffScore <= diffThreshold
