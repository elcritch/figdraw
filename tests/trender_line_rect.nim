import std/os
import std/unittest

import pkg/chroma
import pkg/pixie
import figdraw/windyshim

import figdraw/commons
import figdraw/figextras
import figdraw/fignodes

import ./opengl_test_utils

proc approxEq(a, b: float32, eps = 0.001'f32): bool =
  abs(a - b) <= eps

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
    figLine(90.0'f32, 120.0'f32, 710.0'f32, 470.0'f32, rgba(0, 0, 0, 255), 48.0'f32),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "line helper render":
  test "horizontal line math":
    let line =
      figLine(10.0'f32, 20.0'f32, 110.0'f32, 20.0'f32, rgba(0, 0, 0, 255), 8.0'f32)

    check line.kind == nkRectangle
    check line.screenBox.x.approxEq(10.0'f32)
    check line.screenBox.y.approxEq(16.0'f32)
    check line.screenBox.w.approxEq(100.0'f32)
    check line.screenBox.h.approxEq(8.0'f32)
    check line.rotation.approxEq(0.0'f32)

  test "vertical line math":
    let line =
      figLine(40.0'f32, 25.0'f32, 40.0'f32, 145.0'f32, rgba(0, 0, 0, 255), 12.0'f32)

    check line.kind == nkRectangle
    check line.screenBox.x.approxEq(-20.0'f32)
    check line.screenBox.y.approxEq(79.0'f32)
    check line.screenBox.w.approxEq(120.0'f32)
    check line.screenBox.h.approxEq(12.0'f32)
    check line.rotation.approxEq(90.0'f32)

  test "renders a rotated rect line that matches expectation":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_line_rect.png"
    if fileExists(outPath):
      removeFile(outPath)

    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          title = "figdraw test: line helper",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let expectedPath = "tests" / "expected" / "render_line_rect.png"
      check fileExists(expectedPath)
      let expected = pixie.readImage(expectedPath)
      let (diffScore, diffImg) = expected.diff(img)
      echo "Got image difference of: ", diffScore
      let diffThreshold = 100.0'f32
      if diffScore > diffThreshold:
        diffImg.writeFile(joinPath(outDir, "render_line_rect.diff.png"))
      check diffScore <= diffThreshold
