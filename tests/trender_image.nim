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

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "root".toFigName(),
    screenBox: rect(0, 0, w, h),
    fill: rgba(160, 160, 160, 255).color,
  ))

  list.addChild(rootIdx, Fig(
    kind: nkImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "img".toFigName(),
    screenBox: rect(60, 60, 160, 160),
    image: ImageStyle(
      color: rgba(255, 255, 255, 255).color,
      id: hash("img1.png").ImageId,
    ),
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc maxChannelDelta(a: ColorRGBX, r, g, b: uint8): int =
  result = max(
    abs(a.r.int - r.int),
    max(abs(a.g.int - g.int), abs(a.b.int - b.int)),
  )

proc findMostOpaquePixel(img: Image): tuple[x, y: int, a: uint8] =
  result = (x: 0, y: 0, a: 0'u8)
  for y in 0 ..< img.height:
    for x in 0 ..< img.width:
      let a = img[x, y].a
      if a > result.a:
        result = (x: x, y: y, a: a)

suite "opengl image render":
  test "renders nkImage with texture":
    setFigDataDir(getCurrentDir() / "data")

    let imgId = loadImage("img1.png")
    let src = pixie.readImage(figDataDir() / "img1.png")
    let sample = findMostOpaquePixel(src)
    require sample.a >= 200'u8

    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_image.png"
    removeFile(outPath)
    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          title = "figdraw test: image render",
        )
      except WindyError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let
        bg = (r: 160'u8, g: 160'u8, b: 160'u8)
        imageRect = rect(60, 60, 160, 160)
        sx = imageRect.x.int + ((sample.x.float32 + 0.5'f32) /
            src.width.float32 * imageRect.w).int
        sy = imageRect.y.int + ((sample.y.float32 + 0.5'f32) /
            src.height.float32 * imageRect.h).int
        tol = 12

      var differsFromBg = false
      for dy in -1 .. 1:
        for dx in -1 .. 1:
          let px = img[sx + dx, sy + dy]
          if px.maxChannelDelta(bg.r, bg.g, bg.b) > tol:
            differsFromBg = true

      check differsFromBg
