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

proc addRect(
    list: var RenderList,
    parentIdx: FigIdx,
    rectBox: Rect,
    color: Color,
    z: ZLevel,
    clip: bool = false,
) =
  discard list.addChild(
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
      flags:
        if clip:
          {NfClipContent}
        else:
          {},
    ),
  )

proc addRootRect(
    list: var RenderList, rectBox: Rect, color: Color, z: ZLevel, clip: bool = false
): FigIdx =
  list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
      flags:
        if clip:
          {NfClipContent}
        else:
          {},
    )
  )

proc makeRenderTree(w, h: float32): Renders =
  let bgColor = rgba(245, 245, 245, 255).color
  let containerColor = rgba(208, 208, 208, 255).color
  let buttonColor = rgba(0, 160, 255, 255).color
  let transparent = rgba(0, 0, 0, 0).color

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

  var bgList = RenderList()
  discard bgList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-20).ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: bgColor,
    )
  )

  var containerList = RenderList()
  discard containerList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-10).ZLevel,
      screenBox: rect(containerLeftX, containerY, containerW, containerH),
      fill: containerColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    )
  )
  discard containerList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-10).ZLevel,
      screenBox: rect(containerRightX, containerY, containerW, containerH),
      fill: containerColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    )
  )

  var lowList = RenderList()
  var midList = RenderList()
  var topList = RenderList()

  discard addRootRect(
    lowList,
    rect(containerLeftX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  discard addRootRect(
    midList,
    rect(containerLeftX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )
  discard addRootRect(
    topList,
    rect(containerLeftX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  let rightLowClip = addRootRect(
    lowList,
    rect(containerRightX, containerY, containerW, containerH),
    transparent,
    (-5).ZLevel,
    clip = true,
  )
  let rightMidClip = addRootRect(
    midList,
    rect(containerRightX, containerY, containerW, containerH),
    transparent,
    0.ZLevel,
    clip = true,
  )
  let rightTopClip = addRootRect(
    topList,
    rect(containerRightX, containerY, containerW, containerH),
    transparent,
    20.ZLevel,
    clip = true,
  )

  addRect(
    lowList,
    rightLowClip,
    rect(containerRightX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  addRect(
    midList,
    rightMidClip,
    rect(containerRightX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )
  addRect(
    topList,
    rightTopClip,
    rect(containerRightX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[(-20).ZLevel] = bgList
  result.layers[(-10).ZLevel] = containerList
  result.layers[(-5).ZLevel] = lowList
  result.layers[0.ZLevel] = midList
  result.layers[20.ZLevel] = topList
  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )

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
      assertColor(img, 300, sampleY, 0, 160, 255)
      assertColor(img, 700, sampleY, 245, 245, 245)
      assertColor(img, 450, sampleY, 0, 160, 255)
