import std/[os, unittest, unicode]

import pkg/chroma
import pkg/pixie

import figdraw/commons
import figdraw/fignodes
import figdraw/common/typefaces

import ./siwin_test_utils

type InkBounds = object
  found: bool
  x0: int
  y0: int
  x1: int
  y1: int

proc isInk(px: ColorRGBX): bool =
  px.a >= 20'u8 and (px.r < 220'u8 or px.g < 220'u8 or px.b < 220'u8)

proc findInkBounds(img: Image, x0, y0, w, h: int): InkBounds =
  let
    minX = max(0, x0)
    minY = max(0, y0)
    maxX = min(img.width - 1, x0 + w - 1)
    maxY = min(img.height - 1, y0 + h - 1)
  if maxX < minX or maxY < minY:
    return InkBounds(found: false)

  result = InkBounds(found: false, x0: maxX, y0: maxY, x1: minX, y1: minY)
  for y in minY .. maxY:
    for x in minX .. maxX:
      if isInk(img[x, y]):
        if not result.found:
          result = InkBounds(found: true, x0: x, y0: y, x1: x, y1: y)
        else:
          result.x0 = min(result.x0, x)
          result.y0 = min(result.y0, y)
          result.x1 = max(result.x1, x)
          result.y1 = max(result.y1, y)

proc inkHeight(b: InkBounds): int =
  if not b.found:
    return 0
  b.y1 - b.y0 + 1

proc rowInkProfile(img: Image, b: InkBounds): seq[int] =
  if not b.found:
    return @[]
  result = newSeq[int](b.y1 - b.y0 + 1)
  for y in b.y0 .. b.y1:
    var sum = 0
    for x in b.x0 .. b.x1:
      let px = img[x, y]
      if px.a > 0'u8:
        sum += (255 - px.r.int) + (255 - px.g.int) + (255 - px.b.int)
    result[y - b.y0] = sum

proc profileDiff(a, b: seq[int]): int =
  let n = min(a.len, b.len)
  var total = 0
  for i in 0 ..< n:
    total += abs(a[i] - b[i])
  total

proc profileDiffFlipped(a, b: seq[int]): int =
  let n = min(a.len, b.len)
  var total = 0
  for i in 0 ..< n:
    total += abs(a[i] - b[n - 1 - i])
  total

suite "siwin text invert render":
  test "NfInvertY keeps mirrored text upright without Y shift":
    setFigUiScale(1.0'f32)
    setFigDataDir(getCurrentDir() / "data")

    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 72.0'f32)
    let arrangement = placeGlyphs(
      uiFont, [("g".runeAt(0), vec2(0.0'f32, 0.0'f32))], origin = GlyphTopLeft
    )

    let
      windowW = 640
      windowH = 360
      baselineY = 120.0'f32
      leftX = 96.0'f32
      rightX = 352.0'f32

    proc makeRenderTree(w, h: float32): Renders =
      var list = RenderList()
      discard list.addRoot(
        Fig(
          kind: nkRectangle,
          childCount: 0,
          zlevel: 0.ZLevel,
          screenBox: rect(0, 0, w, h),
          fill: rgba(255, 255, 255, 255),
        )
      )

      discard list.addRoot(
        Fig(
          kind: nkText,
          childCount: 0,
          zlevel: 1.ZLevel,
          screenBox: rect(leftX, baselineY, 220, 140),
          fill: fill(rgba(10, 10, 10, 255)),
          textLayout: arrangement,
          selectionRange: 0'i16 .. -1'i16,
        )
      )

      let mirroredRoot = list.addRoot(
        Fig(
          kind: nkTransform,
          childCount: 0,
          zlevel: 1.ZLevel,
          transform: TransformStyle(
            translation: vec2(0.0'f32, h),
            matrix: scale(vec3(1.0'f32, -1.0'f32, 1.0'f32)),
            useMatrix: true,
          ),
        )
      )

      discard list.addChild(
        mirroredRoot,
        Fig(
          kind: nkText,
          childCount: 0,
          zlevel: 1.ZLevel,
          flags: {NfInvertY},
          screenBox: rect(rightX, h - baselineY, 220, 140),
          fill: fill(rgba(10, 10, 10, 255)),
          textLayout: arrangement,
          selectionRange: 0'i16 .. -1'i16,
        ),
      )

      result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
      result.layers[0.ZLevel] = list

    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_text_invert.png"
    if fileExists(outPath):
      removeFile(outPath)

    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          windowW = windowW,
          windowH = windowH,
          title = "figdraw test: text invert render (siwin)",
        )
      except ValueError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let
        leftBounds = findInkBounds(img, 32, 40, 260, 260)
        rightBounds = findInkBounds(img, 300, 40, 260, 260)
      check leftBounds.found
      check rightBounds.found

      check abs(leftBounds.y0 - rightBounds.y0) <= 2
      check abs(inkHeight(leftBounds) - inkHeight(rightBounds)) <= 2

      let
        leftProfile = rowInkProfile(img, leftBounds)
        rightProfile = rowInkProfile(img, rightBounds)
      check leftProfile.len > 0
      check rightProfile.len > 0

      let
        directDiff = profileDiff(leftProfile, rightProfile)
        flippedDiff = profileDiffFlipped(leftProfile, rightProfile)
      check directDiff <= flippedDiff
