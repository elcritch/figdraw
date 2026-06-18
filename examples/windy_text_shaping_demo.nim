import std/[os, strutils, times, unicode]

import chroma
import chronicles

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/common/fonttypes
import figdraw/fignodes
import figdraw/figrender as glrenderer

const
  RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
  ExampleDir = currentSourcePath().parentDir
  RepoDir = ExampleDir.parentDir
  UbuntuFontFile = RepoDir / "data" / "Ubuntu.ttf"
  ArabicFontFile = ExampleDir / "fonts" / "NotoNaskhArabic-wght.ttf"
  HebrewFontFile = ExampleDir / "fonts" / "NotoSansHebrew-wdth-wght.ttf"
  DevanagariFontFile = ExampleDir / "fonts" / "NotoSansDevanagari-wdth-wght.ttf"
  ChineseFontFile = ExampleDir / "fonts" / "NotoSerifTC-wght.ttf"

const
  ArabicBody =
    "السلام عليكم ورحمة الله وبركاته\n" &
    "النص العربي يحتاج إلى تشكيل واتجاه صحيح ولف أسطر هادئ."
  HebrewBody =
    "שָׁלוֹם עוֹלָם וּבְרוּכִים הַבָּאִים\n" &
    "טֶקְסְט עִבְרִי צָרִיךְ נִקּוּד, כִּוּוּן נָכוֹן וּשְׁבִירַת שׁוּרוֹת יַצִּיבָה."
  DevanagariBody =
    "नमस्ते दुनिया और आपका स्वागत है\n" &
    "देवनागरी पाठ को मात्रा, संयुक्ताक्षर और स्थिर पंक्ति-विन्यास चाहिए."
  ChineseBody =
    "學而時習之，不亦說乎？有朋自遠方來，不亦樂乎？\n" &
    "古文排版需要可靠的字形、標點與換行。"

type DemoFonts = object
  title: FigFont
  body: FigFont
  metric: FigFont
  arabic: FigFont
  hebrew: FigFont
  devanagari: FigFont
  chinese: FigFont

proc requireFile(path: string) =
  if not fileExists(path):
    raise newException(IOError, "Missing demo asset: " & path)

proc initDemoFonts(): DemoFonts =
  for path in [
    UbuntuFontFile, ArabicFontFile, HebrewFontFile, DevanagariFontFile, ChineseFontFile
  ]:
    requireFile(path)

  let
    ubuntu = loadTypeface(UbuntuFontFile)
    arabic = loadTypeface(ArabicFontFile)
    hebrew = loadTypeface(HebrewFontFile)
    devanagari = loadTypeface(DevanagariFontFile)
    chinese = loadTypeface(ChineseFontFile)
    commonFeatures = @[fontFeature("kern"), fontFeature("liga")]
    fallbackTypefaces = @[arabic, hebrew, devanagari, chinese]

  result = DemoFonts(
    title: FigFont(
      typefaceId: ubuntu,
      size: 22.0'f32,
      fallbackTypefaceIds: fallbackTypefaces,
      features: commonFeatures,
    ),
    body: FigFont(
      typefaceId: ubuntu,
      size: 18.0'f32,
      fallbackTypefaceIds: fallbackTypefaces,
      features: commonFeatures,
    ),
    metric: FigFont(
      typefaceId: ubuntu,
      size: 13.0'f32,
      fallbackTypefaceIds: fallbackTypefaces,
      features: commonFeatures,
    ),
    arabic: FigFont(
      typefaceId: arabic,
      size: 36.0'f32,
      fallbackTypefaceIds: @[hebrew, devanagari, chinese, ubuntu],
      features: commonFeatures,
      variations: @[fontVariation("wght", 520.0'f32)],
    ),
    hebrew: FigFont(
      typefaceId: hebrew,
      size: 34.0'f32,
      fallbackTypefaceIds: @[arabic, devanagari, chinese, ubuntu],
      features: commonFeatures,
      variations: @[fontVariation("wght", 560.0'f32), fontVariation("wdth", 96.0'f32)],
    ),
    devanagari: FigFont(
      typefaceId: devanagari,
      size: 32.0'f32,
      fallbackTypefaceIds: @[arabic, hebrew, chinese, ubuntu],
      features: commonFeatures,
      variations: @[fontVariation("wght", 560.0'f32), fontVariation("wdth", 100.0'f32)],
    ),
    chinese: FigFont(
      typefaceId: chinese,
      size: 28.0'f32,
      fallbackTypefaceIds: @[arabic, hebrew, devanagari, ubuntu],
      features: commonFeatures,
      variations: @[fontVariation("wght", 560.0'f32)],
    ),
  )

proc addRect(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    fill: Fill,
    corners = 0.0'f32,
    zlevel = 0.ZLevel,
    stroke = RenderStroke(),
    shadows: array[ShadowCount, RenderShadow] =
      [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()],
): FigIdx {.discardable.} =
  renders.addChild(
    zlevel,
    parent,
    Fig(
      kind: nkRectangle,
      zlevel: zlevel,
      screenBox: box,
      fill: fill,
      corners: [corners, corners, corners, corners],
      stroke: stroke,
      shadows: shadows,
    ),
  )

proc addTextLayout(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    layout: GlyphArrangement,
    zlevel = 0.ZLevel,
) =
  discard renders.addChild(
    zlevel,
    parent,
    Fig(
      kind: nkText, zlevel: zlevel, screenBox: box, fill: clearColor, textLayout: layout
    ),
  )

proc textLayout(
    box: Rect,
    spans: openArray[(FontStyle, string)],
    hAlign = Left,
    vAlign = Top,
    wrap = true,
): GlyphArrangement =
  typeset(
    rect(0, 0, box.w, box.h),
    spans,
    hAlign = hAlign,
    vAlign = vAlign,
    minContent = false,
    wrap = wrap,
  )

proc runeRange(text, phrase: string): Slice[int] =
  let startByte = text.find(phrase)
  if startByte < 0:
    return 0 .. -1

  let endByte = startByte + phrase.len
  var
    runeIndex = 0
    byteIndex = 0
    startRune = -1
    endRune = -1

  while byteIndex < text.len:
    if byteIndex == startByte:
      startRune = runeIndex
    if byteIndex < endByte:
      endRune = runeIndex
    else:
      break
    byteIndex += runeLenAt(text, byteIndex)
    inc runeIndex

  if startRune < 0 or endRune < startRune:
    return 0 .. -1
  startRune .. endRune

proc addSourceHighlight(
    renders: var Renders,
    parent: FigIdx,
    origin: Vec2,
    layout: GlyphArrangement,
    sourceRange: Slice[int],
    fill: Fill,
) =
  if sourceRange.a > sourceRange.b:
    return

  for selection in layout.selectionRectsForSourceRunes(sourceRange):
    if selection.h <= 0:
      continue
    let box = rect(
      origin.x + selection.x,
      origin.y + selection.y,
      max(selection.w, 2.0'f32),
      selection.h,
    )
    discard renders.addRect(parent, box, fill, corners = 4.0'f32)

proc addCaretMarkers(
    renders: var Renders,
    parent: FigIdx,
    origin: Vec2,
    layout: GlyphArrangement,
    sourceRune: int,
    fill: Fill,
) =
  for caret in layout.caretPositionsForSourceRune(sourceRune):
    let box =
      rect(origin.x + caret.pos.x - 1.0'f32, origin.y + caret.pos.y, 2, caret.rect.h)
    discard renders.addRect(parent, box, fill, corners = 1.0'f32)

proc layoutStats(name: string, layout: GlyphArrangement): string =
  name & "  glyphs " & $layout.arrangedGlyphs.len & "  source " & $layout.sourceRunes.len &
    "  lines " & $layout.lines.len

proc addText(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign = Left,
    vAlign = Top,
    wrap = false,
) =
  let layout = textLayout(
    box, [(fs(font, fill), text)], hAlign = hAlign, vAlign = vAlign, wrap = wrap
  )
  renders.addTextLayout(parent, box, layout)

proc addSampleCard(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    title: string,
    body: string,
    highlightPhrase: string,
    font: FigFont,
    labelFont: FigFont,
    metricFont: FigFont,
    accent: Fill,
    hAlign: FontHorizontal,
) =
  let card = renders.addRect(
    root,
    box,
    rgba(255, 255, 255, 255),
    corners = 8.0'f32,
    stroke = RenderStroke(weight: 1.0'f32, fill: rgba(0, 0, 0, 32).color),
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 20,
        spread: 0,
        x: 0,
        y: 8,
        fill: rgba(0, 0, 0, 24).color,
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ],
  )

  let titleBox = rect(box.x + 22, box.y + 18, box.w - 44, 30)
  renders.addText(card, titleBox, labelFont, title, rgba(40, 45, 50, 255))

  let textBox = rect(box.x + 22, box.y + 62, box.w - 44, box.h - 112)
  let layout = textLayout(
    textBox, [(fs(font, rgba(18, 20, 24, 255)), body)], hAlign = hAlign, wrap = true
  )

  renders.addSourceHighlight(
    card,
    textBox.xy,
    layout,
    body.runeRange(highlightPhrase),
    linear(rgba(80, 190, 255, 70), rgba(30, 100, 210, 48), axis = fgaY),
  )
  renders.addCaretMarkers(
    card, textBox.xy, layout, body.runeRange(highlightPhrase).a, rgba(33, 92, 185, 210)
  )
  renders.addTextLayout(card, textBox, layout)

  let metricBox = rect(box.x + 22, box.y + box.h - 43, box.w - 44, 30)
  renders.addRect(card, metricBox, accent, corners = 5.0'f32)
  renders.addText(
    card,
    metricBox,
    metricFont,
    layoutStats(title, layout),
    rgba(255, 255, 255, 235),
    hAlign = Center,
    vAlign = Middle,
  )

proc makeRenderTree*(w, h: float32, fonts: DemoFonts): Renders =
  result = Renders()
  let root = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: linear(rgba(236, 240, 241, 255), rgba(215, 222, 226, 255), axis = fgaY),
    ),
  )

  let
    pad = 28.0'f32
    titleHeight = 66.0'f32
    gap = 18.0'f32
    usableW = max(360.0'f32, w - pad * 2)
    columnCount =
      if usableW >= 1460.0'f32:
        4
      elif usableW >= 1120.0'f32:
        3
      elif usableW >= 760.0'f32:
        2
      else:
        1
    scriptCount = 4
    scriptRows = (scriptCount + columnCount - 1) div columnCount
    cardW = (usableW - gap * (columnCount.float32 - 1.0'f32)) / columnCount.float32
    mixedMinH = 130.0'f32
    availableH = max(0.0'f32, h - pad * 2 - titleHeight - mixedMinH - gap)
    topCardH =
      max(190.0'f32, (availableH - gap * scriptRows.float32) / scriptRows.float32)
    lowerY = pad + titleHeight + (topCardH + gap) * scriptRows.float32
    lowerH = max(0.0'f32, h - lowerY - pad)

  proc cardRect(index: int): Rect =
    let
      col = index mod columnCount
      row = index div columnCount
    rect(
      pad + (cardW + gap) * col.float32,
      pad + titleHeight + (topCardH + gap) * row.float32,
      cardW,
      topCardH,
    )

  let titleBox = rect(pad, pad, usableW, 34)
  result.addText(
    root,
    titleBox,
    fonts.title,
    "FigDraw Text Shaping",
    linear(rgba(30, 42, 58, 255), rgba(45, 92, 145, 255), axis = fgaX),
  )

  let backendBox = rect(pad, pad + 34, usableW, 24)
  result.addText(
    root,
    backendBox,
    fonts.metric,
    "backend: " & figdrawTextBackend,
    rgba(74, 84, 94, 255),
  )

  let arabicCard = cardRect(0)
  result.addSampleCard(
    root,
    arabicCard,
    "Arabic",
    ArabicBody,
    "العربي",
    fonts.arabic,
    fonts.body,
    fonts.metric,
    linear(rgba(21, 135, 115, 235), rgba(25, 92, 145, 235), axis = fgaX),
    Right,
  )

  let hebrewCard = cardRect(1)
  result.addSampleCard(
    root,
    hebrewCard,
    "Hebrew",
    HebrewBody,
    "עִבְרִי",
    fonts.hebrew,
    fonts.body,
    fonts.metric,
    linear(rgba(114, 68, 160, 235), rgba(58, 112, 188, 235), axis = fgaX),
    Right,
  )

  let devanagariCard = cardRect(2)
  result.addSampleCard(
    root,
    devanagariCard,
    "Devanagari",
    DevanagariBody,
    "देवनागरी",
    fonts.devanagari,
    fonts.body,
    fonts.metric,
    linear(rgba(185, 96, 34, 235), rgba(118, 113, 34, 235), axis = fgaX),
    Left,
  )

  let chineseCard = cardRect(3)
  result.addSampleCard(
    root,
    chineseCard,
    "Classical Chinese",
    ChineseBody,
    "學而時習之",
    fonts.chinese,
    fonts.body,
    fonts.metric,
    linear(rgba(132, 78, 54, 235), rgba(58, 91, 98, 235), axis = fgaX),
    Left,
  )

  let mixedCard = rect(pad, lowerY, usableW, lowerH)
  let mixed = result.addRect(
    root,
    mixedCard,
    rgba(252, 253, 253, 255),
    corners = 8.0'f32,
    stroke = RenderStroke(weight: 1.0'f32, fill: rgba(0, 0, 0, 32).color),
  )
  result.addText(
    mixed,
    rect(mixedCard.x + 22, mixedCard.y + 18, mixedCard.w - 44, 30),
    fonts.body,
    "Mixed Fallback Runs",
    rgba(40, 45, 50, 255),
  )

  let mixedTextBox =
    rect(mixedCard.x + 22, mixedCard.y + 60, mixedCard.w - 44, mixedCard.h - 88)
  let mixedText =
    "FigDraw fallback: العربية + עברית + देवनागरी + 漢文 + English\n" &
    "glyph ids, source ranges, wrapping, and caret positions"
  let mixedLayout = textLayout(
    mixedTextBox,
    [(fs(fonts.body, rgba(20, 22, 24, 255)), mixedText)],
    hAlign = Left,
    wrap = true,
  )
  result.addTextLayout(mixed, mixedTextBox, mixedLayout)

when isMainModule:
  var appRunning = true
  let
    title = windyWindowTitle("FigDraw Text Shaping")
    size = ivec2(1600, 720)
    window = newWindyWindow(size = size, fullscreen = false, title = title)

  if getEnv("HDI") != "":
    setFigUiScale getEnv("HDI").parseFloat()
  else:
    setFigUiScale window.contentScale()
  if size != size.scaled():
    window.size = size.scaled()

  let fonts = initDemoFonts()
  let renderer =
    glrenderer.newFigRenderer(atlasSize = 512, backendState = WindyRenderBackend())
  renderer.setupBackend(window)

  info "Text shaping demo startup",
    backend = figdrawTextBackend,
    windowW = window.size().x,
    windowH = window.size().y,
    scale = window.contentScale()

  var
    renders = makeRenderTree(0.0'f32, 0.0'f32, fonts)
    lastSize = vec2(0.0'f32, 0.0'f32)
    frames = 0
    fpsFrames = 0
    fpsStart = epochTime()

  proc redraw() =
    renderer.beginFrame()
    let sz = window.logicalSize()
    if sz != lastSize:
      lastSize = sz
      renders = makeRenderTree(sz.x, sz.y, fonts)
    renderer.renderFrame(renders, sz)
    renderer.endFrame()

  window.onCloseRequest = proc() =
    appRunning = false
  window.onResize = proc() =
    redraw()

  try:
    while appRunning:
      pollEvents()
      redraw()

      inc frames
      inc fpsFrames
      let now = epochTime()
      if now - fpsStart >= 1.0:
        debug "Text shaping demo heartbeat",
          fps = fpsFrames.float / (now - fpsStart), frames = frames
        fpsFrames = 0
        fpsStart = now

      if RunOnce and frames >= 1:
        appRunning = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
