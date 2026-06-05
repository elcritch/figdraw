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

template assertColor(img: Image, x, y: int, r, g, b: uint8, tol: int = 12) =
  let px = img[x, y]
  check px.maxChannelDelta(r, g, b) <= tol

proc addRect(
    list: var RenderList,
    parentIdx: FigIdx,
    rectBox: Rect,
    color: ColorRGBA,
    z: ZLevel,
    clip: bool = false,
    rectMask: bool = false,
    corners: uint16 = 10'u16,
) =
  var flags: set[FigFlags] = {}
  if clip:
    flags.incl NfClipContent
  if rectMask:
    flags.incl NfRectMaskContent

  discard list.addChild(
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [corners, corners, corners, corners],
      flags: flags,
    ),
  )

proc addRootRect(
    list: var RenderList,
    rectBox: Rect,
    color: ColorRGBA,
    z: ZLevel,
    clip: bool = false,
    rectMask: bool = false,
    corners: uint16 = 10'u16,
): FigIdx =
  var flags: set[FigFlags] = {}
  if clip:
    flags.incl NfClipContent
  if rectMask:
    flags.incl NfRectMaskContent

  list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [corners, corners, corners, corners],
      flags: flags,
    )
  )

proc makeRenderTree(w, h: float32, rectMask = false): Renders =
  let bgColor = rgba(255, 255, 255, 255)
  let containerColor = rgba(208, 208, 208, 255)
  let buttonColor = rgba(43, 159, 234, 255)

  let containerW = w * 0.30'f32
  let containerH = w * 0.40'f32
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

  var layer0List = RenderList()
  let leftContainer = addRootRect(
    layer0List,
    rect(containerLeftX, containerY, containerW, containerH),
    containerColor,
    0.ZLevel,
  )
  let rightContainer = addRootRect(
    layer0List,
    rect(containerRightX, containerY, containerW, containerH),
    containerColor,
    0.ZLevel,
    clip = not rectMask,
    rectMask = rectMask,
  )

  addRect(
    layer0List,
    leftContainer,
    rect(containerLeftX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )
  addRect(
    layer0List,
    rightContainer,
    rect(containerRightX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )

  var lowList = RenderList()
  var topList = RenderList()

  discard addRootRect(
    lowList,
    rect(containerLeftX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  discard addRootRect(
    topList,
    rect(containerLeftX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  discard addRootRect(
    lowList,
    rect(containerRightX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  discard addRootRect(
    topList,
    rect(containerRightX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[(-20).ZLevel] = bgList
  result.layers[0.ZLevel] = layer0List
  result.layers[(-5).ZLevel] = lowList
  result.layers[20.ZLevel] = topList
  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )

proc makeClipRenderTree(w, h: float32): Renders =
  makeRenderTree(w, h)

proc makeRectMaskRenderTree(w, h: float32): Renders =
  makeRenderTree(w, h, rectMask = true)

proc makeMixedRectMaskBatchRenderTree(w, h: float32): Renders =
  var list = RenderList()
  discard list.addRootRect(
    rect(0.0'f32, 0.0'f32, w, h), rgba(255, 255, 255, 255), 0.ZLevel, corners = 0
  )

  discard list.addRootRect(
    rect(32.0'f32, 48.0'f32, 96.0'f32, 80.0'f32),
    rgba(230, 70, 52, 255),
    0.ZLevel,
    corners = 0,
  )

  let maskIdx = list.addRootRect(
    rect(180.0'f32, 48.0'f32, 80.0'f32, 80.0'f32),
    rgba(218, 218, 218, 255),
    0.ZLevel,
    rectMask = true,
    corners = 0,
  )
  list.addRect(
    maskIdx,
    rect(150.0'f32, 72.0'f32, 150.0'f32, 34.0'f32),
    rgba(56, 168, 88, 255),
    0.ZLevel,
    corners = 0,
  )

  discard list.addRootRect(
    rect(310.0'f32, 48.0'f32, 96.0'f32, 80.0'f32),
    rgba(54, 118, 230, 255),
    0.ZLevel,
    corners = 0,
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "opengl layer + clip render":
  test "renders figuro-style layers + clip layout":
    setFigUiScale(1.0)
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_layers_clip.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeClipRenderTree,
          outputPath = outPath,
          windowW = 800,
          windowH = 375,
          title = "figdraw test: layers + clip",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let expectedPath = "tests" / "expected" / "render_layers_clip.png"
      check fileExists(expectedPath)
      let expected = pixie.readImage(expectedPath)
      var rendered = img
      if rendered.width != expected.width or rendered.height != expected.height:
        rendered = rendered.resize(expected.width, expected.height)
      let (diffScore, diffImg) = expected.diff(rendered)
      echo "Got image difference of: ", diffScore
      let diffThreshold = 1.0'f32
      if diffScore > diffThreshold:
        diffImg.writeFile(joinPath(outDir, "render_layers_clip.diff.png"))
      check diffScore <= diffThreshold

      let w = expected.width.float32
      let h = expected.height.float32
      let containerW = w * 0.30'f32
      let containerH = w * 0.40'f32
      let containerY = h * 0.10'f32
      let containerLeftX = w * 0.03'f32
      let containerRightX = w * 0.50'f32
      let buttonX = containerW * 0.10'f32
      let buttonW = containerW * 1.30'f32
      let buttonH = containerH * 0.20'f32
      let buttonY2 = containerH * 0.45'f32
      let buttonY3 = containerH * 0.75'f32

      let midY = (containerY + buttonY2 + buttonH * 0.5'f32).int
      let lowY = (containerY + buttonY3 + buttonH * 0.5'f32).int

      assertColor(
        rendered, (containerLeftX + buttonX + buttonW * 0.9'f32).int, midY, 43, 159, 234
      )
      assertColor(rendered, (w * 0.90'f32).int, midY, 255, 255, 255)
      assertColor(
        rendered,
        (containerRightX + buttonX + buttonW * 0.2'f32).int,
        midY,
        43,
        159,
        234,
      )
      assertColor(
        rendered, (containerLeftX + containerW * 0.5'f32).int, lowY, 208, 208, 208
      )
      assertColor(
        rendered, (containerRightX + containerW * 0.5'f32).int, lowY, 208, 208, 208
      )

  test "renders figuro-style layers with rect mask layout":
    setFigUiScale(1.0)
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_layers_rect_mask.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRectMaskRenderTree,
          outputPath = outPath,
          windowW = 800,
          windowH = 375,
          title = "figdraw test: layers + rect mask",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let expectedPath = "tests" / "expected" / "render_layers_clip.png"
      check fileExists(expectedPath)
      let expected = pixie.readImage(expectedPath)
      var rendered = img
      if rendered.width != expected.width or rendered.height != expected.height:
        rendered = rendered.resize(expected.width, expected.height)
      let (diffScore, diffImg) = expected.diff(rendered)
      echo "Got rect mask image difference of: ", diffScore
      let diffThreshold = 1.0'f32
      if diffScore > diffThreshold:
        diffImg.writeFile(joinPath(outDir, "render_layers_rect_mask.diff.png"))
      check diffScore <= diffThreshold

  test "keeps unmasked siblings visible around rect mask in one batch":
    setFigUiScale(1.0)
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_rect_mask_mixed_batch.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var rendered: Image
      try:
        rendered = renderAndScreenshotOnce(
          makeRenders = makeMixedRectMaskBatchRenderTree,
          outputPath = outPath,
          windowW = 480,
          windowH = 180,
          title = "figdraw test: mixed rect mask batch",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      assertColor(rendered, 74, 88, 230, 70, 52)
      assertColor(rendered, 160, 88, 255, 255, 255)
      assertColor(rendered, 204, 88, 56, 168, 88)
      assertColor(rendered, 336, 88, 54, 118, 230)
