when not defined(emscripten):
  import std/os

import std/[math, times]

import chroma
import chronicles

import figdraw/windowing/siwinshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

logScope:
  scope = "siwin_scripture_shaping"

const
  RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
  DemoWindowTitle = "Siwin Scripture Shaping"
  CarouselHoldSeconds = 15.0'f32
  CarouselSlideSeconds = 1.4'f32
  ExampleDir = currentSourcePath().parentDir
  RepoDir = ExampleDir.parentDir
  UbuntuFontFile = RepoDir / "data" / "Ubuntu.ttf"
  HebrewFontFile = ExampleDir / "fonts" / "NotoSansHebrew-wdth-wght.ttf"

const
  HebrewGenesis319 =
    "בזעת אפיך תאכל לחם עד שובך אל־האדמה כי ממנה לקחת " &
    "כי־עפר אתה ואל־עפר תשוב׃"
  EnglishGenesis319 =
    "In the sweat of thy face shalt thou eat bread, till thou return unto the ground; " &
    "for out of it wast thou taken: for dust thou art, and unto dust shalt thou return."
  GreekJohn316 =
    "Οὕτω γὰρ ἠγάπησεν ὁ Θεὸς τὸν κόσμον, ὥστε τὸν υἱὸν αὐτοῦ " &
    "τὸν μονογενῆ ἔδωκεν, ἵνα πᾶς ὁ πιστεύων εἰς αὐτὸν μὴ ἀπόληται, " &
    "ἀλλ᾽ ἔχῃ ζωὴν αἰώνιον."

type DemoFonts = object
  title: FigFont
  label: FigFont
  metric: FigFont
  hebrew: FigFont
  greek: FigFont
  english: FigFont

type PanelPose = object
  xOffset: float32
  opacity: float32

proc requireFile(path: string) =
  if not fileExists(path):
    raise newException(IOError, "Missing demo asset: " & path)

func uniformCorners(radius: float32): array[DirectionCorners, uint16] =
  for corner in DirectionCorners:
    result[corner] = radius.uint16

func clamp01(v: float32): float32 =
  max(0.0'f32, min(1.0'f32, v))

func faded(color: ColorRGBA, opacity: float32): ColorRGBA =
  rgba(color.r, color.g, color.b, (color.a.float32 * opacity.clamp01()).uint8)

func moved(box: Rect, dx: float32): Rect =
  rect(box.x + dx, box.y, box.w, box.h)

func smoothStep(t: float32): float32 =
  let x = t.clamp01()
  x * x * (3.0'f32 - 2.0'f32 * x)

func carouselTime(t: float32): float32 =
  let
    cycle = (CarouselHoldSeconds + CarouselSlideSeconds) * 2.0'f32
    cycles = floor((t / cycle).float64).float32
  t - cycles * cycle

func carouselPose(t: float32, panelIndex: int, travel: float32): PanelPose =
  let
    segment = CarouselHoldSeconds + CarouselSlideSeconds
    cycleT = carouselTime(t)

  if cycleT < CarouselHoldSeconds:
    if panelIndex == 0:
      result = PanelPose(xOffset: 0.0'f32, opacity: 1.0'f32)
    else:
      result = PanelPose(xOffset: travel, opacity: 0.0'f32)
  elif cycleT < segment:
    let eased = smoothStep((cycleT - CarouselHoldSeconds) / CarouselSlideSeconds)
    if panelIndex == 0:
      result = PanelPose(xOffset: -travel * eased, opacity: 1.0'f32 - eased)
    else:
      result = PanelPose(xOffset: travel * (1.0'f32 - eased), opacity: eased)
  elif cycleT < segment + CarouselHoldSeconds:
    if panelIndex == 1:
      result = PanelPose(xOffset: 0.0'f32, opacity: 1.0'f32)
    else:
      result = PanelPose(xOffset: travel, opacity: 0.0'f32)
  else:
    let eased =
      smoothStep((cycleT - segment - CarouselHoldSeconds) / CarouselSlideSeconds)
    if panelIndex == 1:
      result = PanelPose(xOffset: -travel * eased, opacity: 1.0'f32 - eased)
    else:
      result = PanelPose(xOffset: travel * (1.0'f32 - eased), opacity: eased)

func layoutStats(label: string, layout: GlyphArrangement): string =
  label & "  glyphs " & $layout.arrangedGlyphs.len & "  lines " & $layout.lines.len

func layoutStats(label: string, glyphCount, lineCount: int): string =
  label & "  glyphs " & $glyphCount & "  lines " & $lineCount

proc initDemoFonts(): DemoFonts =
  requireFile(UbuntuFontFile)
  requireFile(HebrewFontFile)

  let
    ubuntu = loadTypeface(UbuntuFontFile)
    hebrew = loadTypeface(HebrewFontFile)
    commonFeatures = @[fontFeature("kern"), fontFeature("liga"), fontFeature("mark")]
    hebrewFeatures =
      @[
        fontFeature("kern"),
        fontFeature("liga"),
        fontFeature("mark"),
        fontFeature("mkmk"),
      ]

  result = DemoFonts(
    title: FigFont(
      typefaceId: ubuntu,
      size: 28.0'f32,
      lineHeight: 34.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
    label: FigFont(
      typefaceId: ubuntu,
      size: 15.0'f32,
      lineHeight: 20.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
    metric: FigFont(
      typefaceId: ubuntu,
      size: 13.0'f32,
      lineHeight: 18.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
    hebrew: FigFont(
      typefaceId: hebrew,
      size: 34.0'f32,
      lineHeight: 54.0'f32,
      fallbackTypefaceIds: @[ubuntu],
      features: hebrewFeatures,
      variations: @[fontVariation("wght", 560.0'f32), fontVariation("wdth", 98.0'f32)],
    ),
    greek: FigFont(
      typefaceId: ubuntu,
      size: 30.0'f32,
      lineHeight: 42.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
    english: FigFont(
      typefaceId: ubuntu,
      size: 22.0'f32,
      lineHeight: 31.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
  )

proc addRect(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    fill: Fill,
    corners = 0.0'f32,
    stroke = RenderStroke(),
    shadows: array[ShadowCount, RenderShadow] =
      [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()],
): FigIdx {.discardable.} =
  renders.addChild(
    0.ZLevel,
    parent,
    Fig(
      kind: nkRectangle,
      screenBox: box,
      fill: fill,
      corners: uniformCorners(corners),
      stroke: stroke,
      shadows: shadows,
    ),
  )

proc addTextLayout(
    renders: var Renders, parent: FigIdx, box: Rect, layout: GlyphArrangement
) =
  discard renders.addChild(
    0.ZLevel,
    parent,
    Fig(kind: nkText, screenBox: box, fill: clearColor, textLayout: layout),
  )

proc spanLayout(
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

proc textLayout(
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign = Left,
    vAlign = Top,
    wrap = true,
): GlyphArrangement =
  spanLayout(box, [(fs(font, fill), text)], hAlign, vAlign, wrap)

proc addText(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign = Left,
    vAlign = Top,
    wrap = true,
) =
  let layout = textLayout(box, font, text, fill, hAlign, vAlign, wrap)
  renders.addTextLayout(parent, box, layout)

proc addColorSwatches(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    colors: array[3, ColorRGBA],
    opacity: float32,
) =
  let
    gap = 7.0'f32
    swatchW = max(12.0'f32, (box.w - gap * 2.0'f32) / 3.0'f32)
  for i, color in colors:
    discard renders.addRect(
      parent,
      rect(box.x + (swatchW + gap) * i.float32, box.y, swatchW, box.h),
      faded(color, opacity),
      corners = 4.0'f32,
    )

proc addCardFrame(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    colors: array[3, ColorRGBA],
    opacity: float32,
): FigIdx =
  result = renders.addRect(
    root,
    box,
    faded(rgba(255, 255, 255, 255), opacity),
    corners = 8.0'f32,
    stroke = RenderStroke(weight: 1.0'f32, fill: faded(rgba(0, 0, 0, 32), opacity)),
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 20.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 8.0'f32,
        fill: faded(rgba(0, 0, 0, 24), opacity),
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ],
  )
  renders.addColorSwatches(
    result,
    rect(box.x + 22.0'f32, box.y + 16.0'f32, box.w - 44.0'f32, 8.0'f32),
    colors,
    opacity,
  )

proc addMetricStrip(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    text: string,
    font: FigFont,
    colors: array[3, ColorRGBA],
    opacity: float32,
) =
  renders.addRect(
    parent,
    box,
    linear(faded(colors[0], opacity), faded(colors[1], opacity), axis = fgaX),
    corners = 5.0'f32,
  )
  renders.addText(
    parent,
    box,
    font,
    text,
    faded(rgba(255, 255, 255, 235), opacity),
    hAlign = Center,
    vAlign = Middle,
    wrap = false,
  )

proc addQuoteCard(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    reference: string,
    language: string,
    text: string,
    font: FigFont,
    hAlign: FontHorizontal,
    fonts: DemoFonts,
    colors: array[3, ColorRGBA],
    opacity: float32,
): GlyphArrangement {.discardable.} =
  if opacity <= 0.01'f32:
    return

  let card = renders.addCardFrame(root, box, colors, opacity)
  let
    pad = 22.0'f32
    contentW = box.w - pad * 2.0'f32
    titleBox = rect(box.x + pad, box.y + 36.0'f32, contentW, 30.0'f32)
    langBox = rect(box.x + pad, titleBox.y + titleBox.h + 4.0'f32, contentW, 20.0'f32)
    metricBox = rect(box.x + pad, box.y + box.h - 43.0'f32, contentW, 30.0'f32)
    textBox = rect(
      box.x + pad,
      langBox.y + langBox.h + 10.0'f32,
      contentW,
      max(40.0'f32, metricBox.y - langBox.y - langBox.h - 22.0'f32),
    )

  renders.addText(
    card,
    titleBox,
    fonts.label,
    reference,
    faded(rgba(40, 45, 50, 255), opacity),
    wrap = false,
  )
  renders.addText(
    card,
    langBox,
    fonts.metric,
    language,
    faded(rgba(74, 84, 94, 235), opacity),
    wrap = false,
  )
  result = textLayout(
    textBox,
    font,
    text,
    faded(rgba(18, 20, 24, 255), opacity),
    hAlign = hAlign,
    vAlign = Middle,
    wrap = true,
  )
  renders.addTextLayout(card, textBox, result)
  renders.addMetricStrip(
    card, metricBox, layoutStats(language, result), fonts.metric, colors, opacity
  )

proc addKnuthLine(
    renders: var Renders,
    parent: FigIdx,
    bodyBox: Rect,
    firstY: float32,
    lineH: float32,
    lineIndex: int,
    spans: openArray[(FontStyle, string)],
    glyphCount: var int,
    renderedLines: var int,
) =
  let
    lineBox = rect(bodyBox.x, firstY + lineH * lineIndex.float32, bodyBox.w, lineH)
    layout = spanLayout(lineBox, spans, hAlign = Center, vAlign = Middle, wrap = false)
  glyphCount += layout.arrangedGlyphs.len
  inc renderedLines
  renders.addTextLayout(parent, lineBox, layout)

proc addKnuthJohnCard(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    fonts: DemoFonts,
    colors: array[3, ColorRGBA],
    opacity: float32,
) =
  if opacity <= 0.01'f32:
    return

  let card = renders.addCardFrame(root, box, colors, opacity)
  let
    pad = 22.0'f32
    contentW = box.w - pad * 2.0'f32
    titleBox = rect(box.x + pad, box.y + 36.0'f32, contentW, 30.0'f32)
    langBox = rect(box.x + pad, titleBox.y + titleBox.h + 4.0'f32, contentW, 20.0'f32)
    metricBox = rect(box.x + pad, box.y + box.h - 43.0'f32, contentW, 30.0'f32)
    bodyBox = rect(
      box.x + pad,
      langBox.y + langBox.h + 8.0'f32,
      contentW,
      max(120.0'f32, metricBox.y - langBox.y - langBox.h - 20.0'f32),
    )
    lineCount = 9
    footerH = 24.0'f32
    heightLineH =
      max(17.0'f32, min(36.0'f32, (bodyBox.h - footerH - 8.0'f32) / 9.4'f32))
    textSize = max(14.0'f32, min(heightLineH * 0.86'f32, bodyBox.w / 15.0'f32))
    lineH = max(17.0'f32, textSize * 1.18'f32)
    quoteFont = FigFont(
      typefaceId: fonts.english.typefaceId,
      size: textSize,
      lineHeight: lineH,
      fallbackTypefaceIds: fonts.english.fallbackTypefaceIds,
      features: fonts.english.features,
      variations: fonts.english.variations,
    )
    footerFont = FigFont(
      typefaceId: fonts.english.typefaceId,
      size: max(15.0'f32, textSize * 0.64'f32),
      lineHeight: footerH,
      fallbackTypefaceIds: fonts.english.fallbackTypefaceIds,
      features: fonts.english.features,
      variations: fonts.english.variations,
    )
    blackStyle = fs(quoteFont, faded(rgba(12, 14, 16, 255), opacity))
    redStyle = fs(quoteFont, faded(rgba(214, 0, 44, 255), opacity))
    blueFill = faded(rgba(0, 118, 188, 255), opacity)
    linesH = lineH * lineCount.float32
    firstY = bodyBox.y + max(0.0'f32, (bodyBox.h - linesH - footerH) * 0.42'f32)

  renders.addText(
    card,
    titleBox,
    fonts.label,
    "John 3:16",
    faded(rgba(40, 45, 50, 255), opacity),
    wrap = false,
  )
  renders.addText(
    card,
    langBox,
    fonts.metric,
    "English, after Knuth john316.pdf",
    faded(rgba(74, 84, 94, 235), opacity),
    wrap = false,
  )

  var
    glyphCount = 0
    renderedLines = 0

  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    0,
    [(blackStyle, "Yes, this is how God")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    1,
    [(blackStyle, "loved the world:")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    2,
    [(blackStyle, "He "), (redStyle, "G"), (blackStyle, "ave his")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    3,
    [(redStyle, "O"), (blackStyle, "nly Child;")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    4,
    [(redStyle, "S"), (blackStyle, "o that all")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    5,
    [(redStyle, "P"), (blackStyle, "eople with faith in him")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    6,
    [(blackStyle, "can "), (redStyle, "E"), (blackStyle, "scape destruction and")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    7,
    [(redStyle, "L"), (blackStyle, "ive a full life,")],
    glyphCount,
    renderedLines,
  )
  renders.addKnuthLine(
    card,
    bodyBox,
    firstY,
    lineH,
    8,
    [(blackStyle, "now and forever")],
    glyphCount,
    renderedLines,
  )

  let footerLayout = textLayout(
    rect(bodyBox.x, bodyBox.y + bodyBox.h - footerH, bodyBox.w - 12.0'f32, footerH),
    footerFont,
    "JOHN 3:16",
    blueFill,
    hAlign = Right,
    vAlign = Middle,
    wrap = false,
  )
  glyphCount += footerLayout.arrangedGlyphs.len
  inc renderedLines
  renders.addTextLayout(
    card,
    rect(bodyBox.x, bodyBox.y + bodyBox.h - footerH, bodyBox.w - 12.0'f32, footerH),
    footerLayout,
  )
  renders.addMetricStrip(
    card,
    metricBox,
    layoutStats("Knuth-style English", glyphCount, renderedLines),
    fonts.metric,
    colors,
    opacity,
  )

func cardPair(page: Rect): tuple[first: Rect, second: Rect] =
  let gap = 20.0'f32
  if page.w >= 760.0'f32:
    let cardW = (page.w - gap) * 0.5'f32
    result = (
      first: rect(page.x, page.y, cardW, page.h),
      second: rect(page.x + cardW + gap, page.y, cardW, page.h),
    )
  else:
    let cardH = (page.h - gap) * 0.5'f32
    result = (
      first: rect(page.x, page.y, page.w, cardH),
      second: rect(page.x, page.y + cardH + gap, page.w, cardH),
    )

proc addGenesisPage(
    renders: var Renders, root: FigIdx, page: Rect, fonts: DemoFonts, pose: PanelPose
) =
  let
    cards = cardPair(page.moved(pose.xOffset))
    hebrewColors: array[3, ColorRGBA] =
      [rgba(21, 135, 115, 245), rgba(45, 92, 145, 245), rgba(214, 143, 42, 245)]
    englishColors: array[3, ColorRGBA] =
      [rgba(214, 143, 42, 245), rgba(156, 86, 52, 245), rgba(45, 92, 145, 245)]
  renders.addQuoteCard(
    root, cards.first, "Genesis 3:19", "Hebrew", HebrewGenesis319, fonts.hebrew, Right,
    fonts, hebrewColors, pose.opacity,
  )
  renders.addQuoteCard(
    root, cards.second, "Genesis 3:19", "English KJV", EnglishGenesis319, fonts.english,
    Center, fonts, englishColors, pose.opacity,
  )

proc addJohnPage(
    renders: var Renders, root: FigIdx, page: Rect, fonts: DemoFonts, pose: PanelPose
) =
  let
    cards = cardPair(page.moved(pose.xOffset))
    greekColors: array[3, ColorRGBA] =
      [rgba(114, 68, 160, 245), rgba(58, 112, 188, 245), rgba(166, 62, 86, 245)]
    englishColors: array[3, ColorRGBA] =
      [rgba(214, 0, 44, 245), rgba(12, 14, 16, 245), rgba(0, 118, 188, 245)]
  renders.addQuoteCard(
    root, cards.first, "John 3:16", "Greek", GreekJohn316, fonts.greek, Center, fonts,
    greekColors, pose.opacity,
  )
  renders.addKnuthJohnCard(root, cards.second, fonts, englishColors, pose.opacity)

proc addGenesisPanel(
    renders: var Renders, root: FigIdx, box: Rect, fonts: DemoFonts, pose: PanelPose
) =
  renders.addGenesisPage(root, box, fonts, pose)

proc addJohnPanel(
    renders: var Renders, root: FigIdx, box: Rect, fonts: DemoFonts, pose: PanelPose
) =
  renders.addJohnPage(root, box, fonts, pose)

proc makeRenderTree*(w, h: float32, fonts: DemoFonts, timeSec = 0.0'f32): Renders =
  result = Renders()

  let root = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, w, h),
      fill: linear(rgba(238, 241, 246, 255), rgba(218, 225, 234, 255), axis = fgaY),
    ),
  )

  let
    pad = 28.0'f32
    titleHeight = 70.0'f32
    usableW = max(360.0'f32, w - pad * 2.0'f32)
    stage = rect(
      pad, pad + titleHeight, usableW, max(340.0'f32, h - pad * 2.0'f32 - titleHeight)
    )
    panelW = min(980.0'f32, max(460.0'f32, usableW * 0.96'f32))
    panelH = min(620.0'f32, max(340.0'f32, stage.h))
    panel = rect(
      stage.x + (stage.w - panelW) * 0.5'f32,
      stage.y + (stage.h - panelH) * 0.5'f32,
      panelW,
      panelH,
    )
    travel = usableW + panelW * 0.5'f32
    genesisPose = carouselPose(timeSec, 0, travel)
    johnPose = carouselPose(timeSec, 1, travel)

  result.addText(
    root,
    rect(pad, pad, usableW, 34.0'f32),
    fonts.title,
    "Scripture Text Shaping",
    linear(rgba(30, 42, 58, 255), rgba(45, 92, 145, 255), axis = fgaX),
    wrap = false,
  )
  result.addText(
    root,
    rect(pad, pad + 34.0'f32, usableW, 24.0'f32),
    fonts.metric,
    "backend: " & figdrawTextBackend,
    rgba(74, 84, 94, 255),
    wrap = false,
  )

  if genesisPose.opacity <= johnPose.opacity:
    result.addGenesisPanel(root, panel, fonts, genesisPose)
    result.addJohnPanel(root, panel, fonts, johnPose)
  else:
    result.addJohnPanel(root, panel, fonts, johnPose)
    result.addGenesisPanel(root, panel, fonts, genesisPose)

when isMainModule:
  var appRunning = true

  let
    title = siwinWindowTitle(DemoWindowTitle)
    size = ivec2(1040, 820)
    fonts = initDemoFonts()

  when UseVulkanBackend:
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = size, fullscreen = false, title = title)
  else:
    let appWindow = newSiwinWindow(size = size, fullscreen = false, title = title)
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()
  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, DemoWindowTitle)

  info "Scripture shaping demo startup",
    textBackend = figdrawTextBackend,
    windowW = appWindow.backingSize().x,
    windowH = appWindow.backingSize().y,
    scale = appWindow.contentScale()

  let animStart = epochTime()
  var renders = makeRenderTree(0.0'f32, 0.0'f32, fonts, 0.0'f32)

  proc redraw() =
    renderer.beginFrame()
    let sz = appWindow.logicalSize()
    renders = makeRenderTree(sz.x, sz.y, fonts, (epochTime() - animStart).float32)
    renderer.renderFrame(renders, sz)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      appRunning = false,
    onResize: proc(e: ResizeEvent) =
      appWindow.refreshUiScale(useAutoScale)
      redraw(),
    onKey: proc(e: KeyEvent) =
      if e.pressed and e.key == Key.escape:
        close(e.window)
    ,
    onRender: proc(e: RenderEvent) =
      redraw(),
  )
  appWindow.firstStep()
  appWindow.refreshUiScale(useAutoScale)

  try:
    var frames = 0
    while appRunning and appWindow.opened:
      appWindow.redraw()
      appWindow.step()
      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      appWindow.close()
