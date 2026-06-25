import std/[os, unittest, unicode]

import pkg/chroma
import pkg/pixie

import figdraw/commons
import figdraw/fignodes
import figdraw/common/fontutils
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

proc isHighlight(px: ColorRGBX): bool =
  px.a >= 20'u8 and px.r >= 180'u8 and px.g >= 150'u8 and px.b <= 140'u8

proc isBlueInk(px: ColorRGBX): bool =
  px.a >= 20'u8 and px.r <= 80'u8 and px.g <= 140'u8 and px.b >= 180'u8

proc countBlueInk(img: Image, x0, y0, w, h: int): int =
  let
    minX = max(0, x0)
    minY = max(0, y0)
    maxX = min(img.width - 1, x0 + w - 1)
    maxY = min(img.height - 1, y0 + h - 1)
  if maxX < minX or maxY < minY:
    return 0

  for y in minY .. maxY:
    for x in minX .. maxX:
      if isBlueInk(img[x, y]):
        inc result

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

proc findHighlightBounds(img: Image, x0, y0, w, h: int): InkBounds =
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
      if isHighlight(img[x, y]):
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

proc maxInkColumnGap(img: Image, x0, y0, w, h: int): int =
  let bounds = findInkBounds(img, x0, y0, w, h)
  if not bounds.found:
    return high(int)

  var currentGap = 0
  for x in bounds.x0 .. bounds.x1:
    var hasInk = false
    for y in max(0, y0) .. min(img.height - 1, y0 + h - 1):
      if isInk(img[x, y]):
        hasInk = true
        break
    if hasInk:
      result = max(result, currentGap)
      currentGap = 0
    else:
      inc currentGap
  max(result, currentGap)

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

proc testTextLayout(
    typefaceId: TypefaceId,
    text: string,
    width, height: float32,
    color: ColorRGBA,
    hAlign = Center,
): GlyphArrangement =
  let
    uiFont = FigFont(typefaceId: typefaceId, size: 13.0'f32)
    textStyle = fs(uiFont, fill(color))
  typeset(
    rect(0, 0, width, height),
    [(textStyle, text)],
    hAlign = hAlign,
    vAlign = Middle,
    minContent = false,
    wrap = false,
  )

proc loadHelloTypeface(): TypefaceId =
  var cached {.global.}: TypefaceId
  if Hash(cached) != 0:
    return cached

  let merendaDataDir = getCurrentDir().parentDir().parentDir() / "data"
  if fileExists(merendaDataDir / "IBMPlexSans-Regular.ttf"):
    setFigDataDir(merendaDataDir)
    cached = loadTypeface("IBMPlexSans-Regular.ttf", ["Ubuntu.ttf"])
    return cached

  setFigDataDir(getCurrentDir() / "data")
  let fontData = readFile(figDataDir() / "Ubuntu.ttf")
  cached = loadTypeface("Ubuntu.ttf", fontData, TTF)
  cached

suite "siwin text invert render":
  test "left aligned text renders inside small clipped parents":
    setFigUiScale(1.0'f32)
    setFigDataDir(getCurrentDir() / "data")

    let
      fontData = readFile(figDataDir() / "Ubuntu.ttf")
      typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      uiFont = FigFont(typefaceId: typefaceId, size: 13.0'f32)
      textStyle = fs(uiFont, fill(rgba(18, 28, 44, 255)))
      textValue = "Pure Nim responder/action dispatch with plain widget state"

    proc textArrangement(width, height: float32): GlyphArrangement =
      typeset(
        rect(0, 0, width, height),
        [(textStyle, textValue)],
        hAlign = Left,
        vAlign = Middle,
        minContent = false,
        wrap = false,
      )

    proc addClippedText(
        list: var RenderList, box: Rect, layout: GlyphArrangement, z: ZLevel
    ) =
      let parentIdx = list.addRoot(
        Fig(
          kind: nkRectangle,
          childCount: 0,
          zlevel: z,
          screenBox: box,
          fill: rgba(242, 245, 250, 255),
          flags: {NfClipContent},
        )
      )
      discard list.addChild(
        parentIdx,
        Fig(kind: nkText, childCount: 0, zlevel: z, screenBox: box, textLayout: layout),
      )

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
      list.addClippedText(rect(28, 30, 664, 18), textArrangement(664, 18), 1.ZLevel)
      list.addClippedText(rect(28, 70, 664, 24), textArrangement(664, 24), 1.ZLevel)

      result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
      result.layers[0.ZLevel] = list

    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_small_clipped_text.png"
    if fileExists(outPath):
      removeFile(outPath)

    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          windowW = 720,
          windowH = 130,
          title = "figdraw test: small clipped text",
        )
      except ValueError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let
        bodyInk = findInkBounds(img, 24, 24, 420, 32)
        statusInk = findInkBounds(img, 24, 64, 420, 38)
      check bodyInk.found
      check statusInk.found
      check bodyInk.x1 - bodyInk.x0 > 120
      check statusInk.x1 - statusInk.x0 > 120

  test "hello-like clipped label sequence renders every text node":
    setFigUiScale(1.0'f32)
    setFigDataDir(getCurrentDir() / "data")

    let
      typefaceId = loadHelloTypeface()
      titleLayout = testTextLayout(
        typefaceId, "Hello from KNutella/nimkit", 640, 28, rgba(23, 36, 66, 255), Center
      )
      bodyLayout = testTextLayout(
        typefaceId,
        "Pure Nim responder/action dispatch with plain widget state",
        664,
        18,
        rgba(23, 31, 46, 255),
        Left,
      )
      statusLayout = testTextLayout(
        typefaceId,
        "Button state: Off (click to cycle)",
        644,
        24,
        rgba(23, 69, 46, 255),
        Left,
      )
      buttonLayout = testTextLayout(
        typefaceId, "Cycle State (Off)", 648, 32, rgba(40, 40, 40, 255), Center
      )

    proc addLabel(
        list: var RenderList,
        parentIdx: FigIdx,
        frame, textFrame: Rect,
        background: ColorRGBA,
        layout: GlyphArrangement,
        z: ZLevel,
    ) =
      let labelIdx = list.addChild(
        parentIdx,
        Fig(
          kind: nkRectangle,
          childCount: 0,
          zlevel: z,
          screenBox: frame,
          fill: rgba(0, 0, 0, 0),
          flags: {NfClipContent},
        ),
      )
      discard list.addChild(
        labelIdx,
        Fig(
          kind: nkRectangle,
          childCount: 0,
          zlevel: z,
          screenBox: frame,
          fill: background,
        ),
      )
      discard list.addChild(
        labelIdx,
        Fig(
          kind: nkText,
          childCount: 0,
          zlevel: z,
          screenBox: textFrame,
          textLayout: layout,
        ),
      )

    proc makeRenderTree(w, h: float32): Renders =
      var list = RenderList()
      let rootIdx = list.addRoot(
        Fig(
          kind: nkRectangle,
          childCount: 0,
          zlevel: 0.ZLevel,
          screenBox: rect(0, 0, w, h),
          fill: rgba(242, 245, 250, 255),
        )
      )
      let stackIdx = list.addChild(
        rootIdx,
        Fig(
          kind: nkRectangle,
          childCount: 0,
          zlevel: 0.ZLevel,
          screenBox: rect(28, 28, 664, 138),
          fill: rgba(0, 0, 0, 0),
        ),
      )
      list.addLabel(
        stackIdx,
        rect(28, 28, 664, 28),
        rect(40, 28, 640, 28),
        rgba(228, 242, 255, 255),
        titleLayout,
        0.ZLevel,
      )
      list.addLabel(
        stackIdx,
        rect(28, 68, 664, 18),
        rect(28, 68, 664, 18),
        rgba(0, 0, 0, 0),
        bodyLayout,
        0.ZLevel,
      )
      list.addLabel(
        stackIdx,
        rect(28, 98, 664, 24),
        rect(38, 98, 644, 24),
        rgba(228, 244, 232, 255),
        statusLayout,
        0.ZLevel,
      )
      list.addLabel(
        stackIdx,
        rect(28, 134, 664, 32),
        rect(36, 134, 648, 32),
        rgba(205, 208, 211, 255),
        buttonLayout,
        0.ZLevel,
      )

      result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
      result.layers[0.ZLevel] = list

    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_hello_like_clipped_text.png"
    if fileExists(outPath):
      removeFile(outPath)

    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          windowW = 720,
          windowH = 220,
          title = "figdraw test: hello-like clipped text",
        )
      except ValueError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let
        titleInk = findInkBounds(img, 260, 28, 200, 28)
        bodyInk = findInkBounds(img, 28, 64, 420, 28)
        statusInk = findInkBounds(img, 38, 94, 260, 34)
        buttonInk = findInkBounds(img, 300, 130, 140, 40)
      check titleInk.found
      check bodyInk.found
      check statusInk.found
      check buttonInk.found
      check bodyInk.x1 - bodyInk.x0 > 120
      check statusInk.x1 - statusInk.x0 > 100

  test "Vulkan preserves glyph atlas text after label content changes":
    when UseVulkanBackend:
      setFigUiScale(1.0'f32)
      setFigDataDir(getCurrentDir() / "data")

      let typefaceId = loadHelloTypeface()

      proc layoutFor(
          text: string, width, height: float32, color: ColorRGBA, hAlign: FontHorizontal
      ): GlyphArrangement =
        testTextLayout(typefaceId, text, width, height, color, hAlign)

      proc measureText(text: string) =
        let
          uiFont = FigFont(typefaceId: typefaceId, size: 13.0'f32)
          textStyle = fs(uiFont, fill(rgba(0, 0, 0, 255)))
        discard typeset(
          rect(0, 0, 10000, 100),
          [(textStyle, text)],
          hAlign = Left,
          vAlign = Top,
          minContent = false,
          wrap = false,
        )

      let
        titleText = "Hello from KNutella/nimkit"
        bodyText = "Pure Nim responder/action dispatch with plain widget state"
        initialStatusText = "Button state: Off (click to cycle)"
        initialButtonText = "Cycle State (Off)"
        updatedStatusText = "Button state: Mixed (click to cycle)"
        updatedButtonText = "Cycle State (Mixed)"

      measureText(titleText)
      measureText(bodyText)
      measureText(initialStatusText)
      measureText(initialButtonText)

      let
        titleLayout = layoutFor(titleText, 640, 28, rgba(23, 36, 66, 255), Center)
        bodyLayout = layoutFor(bodyText, 664, 18, rgba(23, 31, 46, 255), Left)
        initialStatusLayout =
          layoutFor(initialStatusText, 644, 24, rgba(23, 69, 46, 255), Left)
        initialButtonLayout =
          layoutFor(initialButtonText, 648, 32, rgba(40, 40, 40, 255), Center)

      proc addLabel(
          list: var RenderList,
          parentIdx: FigIdx,
          frame, textFrame: Rect,
          background: ColorRGBA,
          layout: GlyphArrangement,
          z: ZLevel,
      ) =
        let labelIdx = list.addChild(
          parentIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: z,
            screenBox: frame,
            fill: rgba(0, 0, 0, 0),
            flags: {NfClipContent},
          ),
        )
        discard list.addChild(
          labelIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: z,
            screenBox: frame,
            fill: background,
          ),
        )
        discard list.addChild(
          labelIdx,
          Fig(
            kind: nkText,
            childCount: 0,
            zlevel: z,
            screenBox: textFrame,
            textLayout: layout,
          ),
        )

      proc makeRenderTree(
          w, h: float32, statusLayout, buttonLayout: GlyphArrangement
      ): Renders =
        var list = RenderList()
        let rootIdx = list.addRoot(
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(0, 0, w, h),
            fill: rgba(242, 245, 250, 255),
          )
        )
        let stackIdx = list.addChild(
          rootIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(28, 28, 664, 138),
            fill: rgba(0, 0, 0, 0),
          ),
        )
        list.addLabel(
          stackIdx,
          rect(28, 28, 664, 28),
          rect(40, 28, 640, 28),
          rgba(228, 242, 255, 255),
          titleLayout,
          0.ZLevel,
        )
        list.addLabel(
          stackIdx,
          rect(28, 68, 664, 18),
          rect(28, 68, 664, 18),
          rgba(0, 0, 0, 0),
          bodyLayout,
          0.ZLevel,
        )
        list.addLabel(
          stackIdx,
          rect(28, 98, 664, 24),
          rect(38, 98, 644, 24),
          rgba(228, 244, 232, 255),
          statusLayout,
          0.ZLevel,
        )

        let buttonIdx = list.addChild(
          stackIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(28, 134, 664, 32),
            fill: rgba(0, 0, 0, 0),
          ),
        )
        let buttonClipIdx = list.addChild(
          buttonIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(28, 134, 664, 32),
            fill: rgba(0, 0, 0, 0),
            corners: [14'u16, 14'u16, 14'u16, 14'u16],
            flags: {NfClipContent},
          ),
        )
        let chromeIdx = list.addChild(
          buttonClipIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(30.5, 136.5, 659, 27),
            fill: rgba(190, 194, 196, 255),
            corners: [12'u16, 12'u16, 12'u16, 12'u16],
            flags: {NfRectMaskContent},
          ),
        )
        discard list.addChild(
          chromeIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(31.5, 137.5, 657, 1),
            fill: rgba(250, 250, 250, 255),
          ),
        )
        discard list.addChild(
          chromeIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(30.5, 136.5, 659, 16.74),
            fill: rgba(232, 235, 236, 255),
            corners: [12'u16, 12'u16, 12'u16, 12'u16],
          ),
        )
        discard list.addChild(
          chromeIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(30.5, 146.22, 659, 17.28),
            fill: rgba(190, 194, 196, 255),
            corners: [12'u16, 12'u16, 12'u16, 12'u16],
          ),
        )
        discard list.addChild(
          chromeIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(31.5, 150, 657, 1),
            fill: rgba(160, 165, 168, 255),
          ),
        )
        discard list.addChild(
          stackIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(26, 132, 668, 36),
            fill: rgba(0, 0, 0, 0),
            corners: [16'u16, 16'u16, 16'u16, 16'u16],
            stroke: RenderStroke(weight: 1.0'f32, fill: fill(rgba(190, 198, 205, 255))),
          ),
        )
        discard list.addChild(
          buttonIdx,
          Fig(
            kind: nkText,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(36, 135, 648, 32),
            textLayout: buttonLayout,
          ),
        )
        discard list.addChild(
          buttonIdx,
          Fig(
            kind: nkText,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(36, 133.4, 648, 32),
            textLayout: buttonLayout,
          ),
        )
        discard list.addChild(
          buttonIdx,
          Fig(
            kind: nkText,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(36, 134, 648, 32),
            textLayout: buttonLayout,
          ),
        )

        result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
        result.layers[0.ZLevel] = list

      let outDir = ensureTestOutputDir()
      let initialPath = outDir / "render_hello_text_sequence_initial_vulkan.png"
      let updatedPath = outDir / "render_hello_text_sequence_updated_vulkan.png"
      if fileExists(initialPath):
        removeFile(initialPath)
      if fileExists(updatedPath):
        removeFile(updatedPath)

      block renderSequence:
        var images: tuple[initial, updated: Image]
        try:
          images = renderAndScreenshotSequence(
            proc(w, h: float32): Renders =
              makeRenderTree(w, h, initialStatusLayout, initialButtonLayout),
            proc(w, h: float32): Renders =
              let
                updatedStatusLayout =
                  layoutFor(updatedStatusText, 644, 24, rgba(23, 69, 46, 255), Left)
                updatedButtonLayout =
                  layoutFor(updatedButtonText, 648, 32, rgba(40, 40, 40, 255), Center)
              makeRenderTree(w, h, updatedStatusLayout, updatedButtonLayout),
            initialPath = initialPath,
            updatedPath = updatedPath,
            windowW = 720,
            windowH = 360,
            atlasSize = 1024,
            title = "figdraw test: vulkan text atlas update",
          )
        except ValueError:
          skip()
          break renderSequence

        check fileExists(initialPath)
        check getFileSize(initialPath) > 0
        check fileExists(updatedPath)
        check getFileSize(updatedPath) > 0

        check maxInkColumnGap(images.initial, 220, 24, 280, 36) < 36
        check maxInkColumnGap(images.initial, 24, 64, 440, 28) < 36
        check maxInkColumnGap(images.initial, 34, 94, 300, 36) < 36

        check maxInkColumnGap(images.updated, 220, 24, 280, 36) < 36
        check maxInkColumnGap(images.updated, 24, 64, 440, 28) < 36
        check maxInkColumnGap(images.updated, 34, 94, 300, 36) < 36
    else:
      skip()

  test "Vulkan clears stale rect-mask attributes before unmasked batches":
    when UseVulkanBackend:
      setFigUiScale(1.0'f32)

      proc makeMaskedFrame(w, h: float32): Renders =
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
        let maskIdx = list.addChild(
          rootIdx,
          Fig(
            kind: nkRectangle,
            childCount: 0,
            zlevel: 0.ZLevel,
            screenBox: rect(520, 180, 32, 32),
            fill: rgba(0, 0, 0, 0),
            corners: [8'u16, 8'u16, 8'u16, 8'u16],
            flags: {NfRectMaskContent},
          ),
        )
        for i in 0 ..< 20:
          discard list.addChild(
            maskIdx,
            Fig(
              kind: nkRectangle,
              childCount: 0,
              zlevel: 0.ZLevel,
              screenBox: rect(20 + i.float32 * 18, 28, 12, 84),
              fill: rgba(20, 110, 220, 255),
            ),
          )

        result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
        result.layers[0.ZLevel] = list

      proc makeUnmaskedFrame(w, h: float32): Renders =
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
        for i in 0 ..< 16:
          discard list.addChild(
            rootIdx,
            Fig(
              kind: nkRectangle,
              childCount: 0,
              zlevel: 0.ZLevel,
              screenBox: rect(20 + i.float32 * 18, 28, 12, 84),
              fill: rgba(20, 110, 220, 255),
            ),
          )

        result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
        result.layers[0.ZLevel] = list

      let outDir = ensureTestOutputDir()
      let initialPath = outDir / "render_stale_rect_mask_initial_vulkan.png"
      let updatedPath = outDir / "render_stale_rect_mask_unmasked_vulkan.png"
      if fileExists(initialPath):
        removeFile(initialPath)
      if fileExists(updatedPath):
        removeFile(updatedPath)

      block renderSequence:
        var images: tuple[initial, updated: Image]
        try:
          images = renderAndScreenshotSequence(
            makeMaskedFrame,
            makeUnmaskedFrame,
            initialPath = initialPath,
            updatedPath = updatedPath,
            windowW = 420,
            windowH = 140,
            atlasSize = 1024,
            title = "figdraw test: vulkan stale rect mask",
          )
        except ValueError:
          skip()
          break renderSequence

        check fileExists(updatedPath)
        check getFileSize(updatedPath) > 0
        check countBlueInk(images.updated, 16, 24, 310, 94) > 10000
    else:
      skip()

  test "NfInvertY under mirrored parent stays upright and vertically aligned":
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
      selectionFill = fill(rgba(255, 210, 70, 210))

    proc mirroredInputRect(finalRect: Rect, h: float32): Rect =
      rect(finalRect.x, h - finalRect.y - finalRect.h, finalRect.w, finalRect.h)

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
          flags: {NfSelectText},
          screenBox: rect(leftX, baselineY, 220, 140),
          fill: selectionFill,
          textLayout: arrangement,
          selectionRange: 0'i16 .. 0'i16,
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
          flags: {NfInvertY, NfSelectText},
          screenBox: mirroredInputRect(rect(rightX, baselineY, 220, 140), h),
          fill: selectionFill,
          textLayout: arrangement,
          selectionRange: 0'i16 .. 0'i16,
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
        leftHighlight = findHighlightBounds(img, 32, 40, 260, 260)
        rightHighlight = findHighlightBounds(img, 300, 40, 260, 260)
      check leftBounds.found
      check rightBounds.found
      check leftHighlight.found
      check rightHighlight.found

      check abs(inkHeight(leftBounds) - inkHeight(rightBounds)) <= 4
      check abs(rightBounds.y0 - leftBounds.y0) <= 4

      check abs(inkHeight(leftHighlight) - inkHeight(rightHighlight)) <= 2
      check abs(rightHighlight.y0 - leftHighlight.y0) <= 2

      let
        leftProfile = rowInkProfile(img, leftBounds)
        rightProfile = rowInkProfile(img, rightBounds)
      check leftProfile.len > 0
      check rightProfile.len > 0

      let
        directDiff = profileDiff(leftProfile, rightProfile)
        flippedDiff = profileDiffFlipped(leftProfile, rightProfile)
      check directDiff <= flippedDiff
