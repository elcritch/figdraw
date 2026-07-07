import std/os
import std/strutils
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

proc makeLineRenderTree(w, h: float32): Renders =
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

proc makeCircleRenderTree(w, h: float32): Renders =
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
    rootIdx, figCircle(400.0'f32, 300.0'f32, rgba(0, 0, 0, 255), 110.0'f32)
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

template checkRenderRegression(
    outName: string,
    title: string,
    renderTreeBuilder: proc(w, h: float32): Renders {.closure.},
) =
  let outDir = ensureTestOutputDir()
  let outPath = outDir / outName
  if fileExists(outPath):
    removeFile(outPath)

  block renderOnce:
    var img: Image
    try:
      img = renderAndScreenshotOnce(renderTreeBuilder, outPath, 800, 600, 2048, title)
    except WindyError:
      skip()
      break renderOnce

    check fileExists(outPath)
    check getFileSize(outPath) > 0

    let expectedPath = "tests" / "expected" / outName
    check fileExists(expectedPath)
    let expected = pixie.readImage(expectedPath)
    let (diffScore, diffImg) = expected.diff(img)
    echo "Got image difference of: ", diffScore
    let diffThreshold = 100.0'f32
    if diffScore > diffThreshold:
      diffImg.writeFile(joinPath(outDir, outName.replace(".png", ".diff.png")))
    check diffScore <= diffThreshold

suite "drawable helper render":
  test "circle math":
    let circle = figCircle(80.0'f32, 50.0'f32, rgba(0, 0, 0, 255), 24.0'f32)

    check circle.kind == nkDrawable
    check circle.screenBox.x.approxEq(56.0'f32)
    check circle.screenBox.y.approxEq(26.0'f32)
    check circle.screenBox.w.approxEq(48.0'f32)
    check circle.screenBox.h.approxEq(48.0'f32)
    check circle.fill.color == rgba(0, 0, 0, 255)
    check circle.drawOps.len == 1
    check circle.drawOps[0].kind == dkCircle
    check circle.drawOps[0].center.x.approxEq(24.0'f32)
    check circle.drawOps[0].center.y.approxEq(24.0'f32)
    check circle.drawOps[0].radius.approxEq(24.0'f32)

  test "horizontal line math":
    let line =
      figLine(10.0'f32, 20.0'f32, 110.0'f32, 20.0'f32, rgba(0, 0, 0, 255), 8.0'f32)

    check line.kind == nkDrawable
    check line.screenBox.x.approxEq(6.0'f32)
    check line.screenBox.y.approxEq(16.0'f32)
    check line.screenBox.w.approxEq(108.0'f32)
    check line.screenBox.h.approxEq(8.0'f32)
    check line.drawOps.len == 1
    check line.drawOps[0].kind == dkLine
    check line.drawOps[0].a.x.approxEq(4.0'f32)
    check line.drawOps[0].a.y.approxEq(4.0'f32)
    check line.drawOps[0].b.x.approxEq(104.0'f32)
    check line.drawOps[0].b.y.approxEq(4.0'f32)
    check line.drawStroke.weight.approxEq(8.0'f32)
    check line.drawStroke.fill.color == rgba(0, 0, 0, 255)

  test "vertical line math":
    let line =
      figLine(40.0'f32, 25.0'f32, 40.0'f32, 145.0'f32, rgba(0, 0, 0, 255), 12.0'f32)

    check line.kind == nkDrawable
    check line.screenBox.x.approxEq(34.0'f32)
    check line.screenBox.y.approxEq(19.0'f32)
    check line.screenBox.w.approxEq(12.0'f32)
    check line.screenBox.h.approxEq(132.0'f32)
    check line.drawOps.len == 1
    check line.drawOps[0].kind == dkLine
    check line.drawOps[0].a.x.approxEq(6.0'f32)
    check line.drawOps[0].a.y.approxEq(6.0'f32)
    check line.drawOps[0].b.x.approxEq(6.0'f32)
    check line.drawOps[0].b.y.approxEq(126.0'f32)
    check line.drawStroke.weight.approxEq(12.0'f32)
    check line.drawStroke.fill.color == rgba(0, 0, 0, 255)

  test "bezier math":
    let curve = drawableBezier(
      vec2(0.0'f32, 0.0'f32),
      vec2(12.0'f32, 20.0'f32),
      vec2(24.0'f32, 0.0'f32),
      steps = 8'u16,
    )

    check curve.kind == dkBezier
    check curve.controls.len == 3
    check curve.controls[0].x.approxEq(0.0'f32)
    check curve.controls[1].y.approxEq(20.0'f32)
    check curve.controls[2].x.approxEq(24.0'f32)
    check curve.steps == 8'u16

  test "arc math":
    let arc = drawableArc(
      vec2(12.0'f32, 18.0'f32), 24.0'f32, 0.0'f32, 3.1415927'f32, steps = 12'u16
    )

    check arc.kind == dkArc
    check arc.arcCenter.x.approxEq(12.0'f32)
    check arc.arcCenter.y.approxEq(18.0'f32)
    check arc.arcRadius.approxEq(24.0'f32)
    check arc.startAngle.approxEq(0.0'f32)
    check arc.sweepAngle.approxEq(3.1415927'f32)
    check arc.arcSteps == 12'u16

  test "renders a rotated rect line that matches expectation":
    checkRenderRegression(
      outName = "render_line_rect.png",
      title = "figdraw test: line helper",
      renderTreeBuilder = makeLineRenderTree,
    )

  test "renders a circle that matches expectation":
    checkRenderRegression(
      outName = "render_circle_rect.png",
      title = "figdraw test: circle helper",
      renderTreeBuilder = makeCircleRenderTree,
    )
