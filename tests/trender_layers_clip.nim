import std/os
import std/unittest

import pkg/chroma
import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes

import ./opengl_test_utils

proc maxChannelDelta(a: ColorRGBX, r, g, b: uint8): int =
  result = max(abs(a.r.int - r.int), max(abs(a.g.int - g.int), abs(a.b.int - b.int)))

template assertColor(img: Image, x, y: int, r, g, b: uint8, tol: int = 12) =
  let px = img[x, y]
  check px.maxChannelDelta(r, g, b) <= tol

proc addButton(
    list: var RenderList, parentIdx: FigIdx, rectBox: Rect, color: Color, z: ZLevel
) =
  discard list.addChild(
    parentIdx,
    Fig(kind: nkRectangle, childCount: 0, zlevel: z, screenBox: rectBox, fill: color),
  )

proc makeRenderTree(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "root".toFigName(),
      screenBox: rect(0, 0, w, h),
      fill: rgba(245, 245, 245, 255).color,
    )
  )

  let containerW = w * 0.30'f32
  let containerH = h * 0.80'f32
  let containerY = h * 0.10'f32
  let containerLeftX = w * 0.03'f32
  let containerRightX = w * 0.50'f32

  let buttonX = containerW * 0.10'f32
  let buttonW = containerW * 1.30'f32
  let buttonH = containerH * 0.20'f32
  let buttonY1 = containerH * 0.15'f32
  let buttonY2 = containerH * 0.45'f32
  let buttonY3 = containerH * 0.75'f32

  let leftIdx = list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "left-container".toFigName(),
      screenBox: rect(containerLeftX, containerY, containerW, containerH),
      fill: rgba(208, 208, 208, 255).color,
    ),
  )

  addButton(
    list,
    leftIdx,
    rect(containerLeftX + buttonX, containerY + buttonY1, buttonW, buttonH),
    rgba(60, 120, 220, 255).color,
    20.ZLevel,
  )
  addButton(
    list,
    leftIdx,
    rect(containerLeftX + buttonX, containerY + buttonY2, buttonW, buttonH),
    rgba(40, 180, 90, 255).color,
    0.ZLevel,
  )
  addButton(
    list,
    leftIdx,
    rect(containerLeftX + buttonX, containerY + buttonY3, buttonW, buttonH),
    rgba(220, 60, 60, 255).color,
    (-5).ZLevel,
  )

  let rightIdx = list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: "right-container".toFigName(),
      screenBox: rect(containerRightX, containerY, containerW, containerH),
      fill: rgba(208, 208, 208, 255).color,
      flags: {NfClipContent},
    ),
  )

  addButton(
    list,
    rightIdx,
    rect(containerRightX + buttonX, containerY + buttonY1, buttonW, buttonH),
    rgba(60, 120, 220, 255).color,
    20.ZLevel,
  )
  addButton(
    list,
    rightIdx,
    rect(containerRightX + buttonX, containerY + buttonY2, buttonW, buttonH),
    rgba(40, 180, 90, 255).color,
    0.ZLevel,
  )
  addButton(
    list,
    rightIdx,
    rect(containerRightX + buttonX, containerY + buttonY3, buttonW, buttonH),
    rgba(220, 60, 60, 255).color,
    (-5).ZLevel,
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "opengl layer + clip render":
  test "renders figuro-style layers + clip layout":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_layers_clip.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          windowW = 800,
          windowH = 400,
          title = "figdraw test: layers + clip",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let sampleY = 216
      assertColor(img, 300, sampleY, 40, 180, 90)
      assertColor(img, 700, sampleY, 245, 245, 245)
      assertColor(img, 450, sampleY, 40, 180, 90)
