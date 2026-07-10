when not defined(emscripten):
  import std/os

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
  EnglishJohn316 =
    "For God so loved the world, that he gave his only begotten Son, " &
    "that whosoever believeth in him should not perish, but have everlasting life."

type DemoFonts = object
  title: FigFont
  label: FigFont
  hebrew: FigFont
  greek: FigFont
  english: FigFont

proc requireFile(path: string) =
  if not fileExists(path):
    raise newException(IOError, "Missing demo asset: " & path)

func uniformCorners(radius: float32): array[DirectionCorners, uint16] =
  for corner in DirectionCorners:
    result[corner] = radius.uint16

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

proc textLayout(
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign = Left,
    vAlign = Top,
    wrap = true,
): GlyphArrangement =
  typeset(
    rect(0, 0, box.w, box.h),
    [(fs(font, fill), text)],
    hAlign = hAlign,
    vAlign = vAlign,
    minContent = false,
    wrap = wrap,
  )

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

proc addDivider(renders: var Renders, parent: FigIdx, box: Rect) =
  discard renders.addRect(
    parent, box, linear(rgba(218, 225, 234, 0), rgba(174, 188, 206, 180), axis = fgaX)
  )

proc addVerseSection(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    reference: string,
    sourceText: string,
    sourceFont: FigFont,
    sourceAlign: FontHorizontal,
    englishText: string,
    fonts: DemoFonts,
) =
  let
    labelBox = rect(box.x, box.y, box.w, 22.0'f32)
    sourceBox = rect(box.x, labelBox.y + labelBox.h + 8.0'f32, box.w, box.h * 0.46'f32)
    dividerBox = rect(box.x, sourceBox.y + sourceBox.h + 12.0'f32, box.w, 1.0'f32)
    englishBox = rect(
      box.x,
      dividerBox.y + 18.0'f32,
      box.w,
      max(42.0'f32, box.y + box.h - dividerBox.y - 18.0'f32),
    )

  renders.addText(
    parent,
    labelBox,
    fonts.label,
    reference,
    rgba(86, 96, 110, 235),
    hAlign = Center,
    wrap = false,
  )
  let sourceLayout = textLayout(
    sourceBox,
    sourceFont,
    sourceText,
    rgba(22, 28, 38, 255),
    hAlign = sourceAlign,
    vAlign = Middle,
    wrap = true,
  )
  renders.addTextLayout(parent, sourceBox, sourceLayout)
  renders.addDivider(parent, dividerBox)
  renders.addText(
    parent,
    englishBox,
    fonts.english,
    englishText & "  (KJV)",
    rgba(38, 48, 62, 255),
    hAlign = Center,
    vAlign = Top,
    wrap = true,
  )

proc addVersePanel(renders: var Renders, root: FigIdx, panel: Rect, fonts: DemoFonts) =
  let panelIdx = renders.addRect(
    root,
    panel,
    rgba(255, 255, 255, 248),
    corners = 18.0'f32,
    stroke = RenderStroke(weight: 1.0'f32, fill: rgba(194, 202, 214, 255)),
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 22.0'f32,
        spread: 5.0'f32,
        x: 0.0'f32,
        y: 12.0'f32,
        fill: rgba(24, 32, 48, 36),
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ],
  )

  let
    pad = max(22.0'f32, min(panel.w, panel.h) * 0.07'f32)
    contentW = panel.w - pad * 2.0'f32
    titleBox = rect(panel.x + pad, panel.y + pad, contentW, 38.0'f32)
    metaBox = rect(panel.x + pad, titleBox.y + titleBox.h + 4.0'f32, contentW, 24.0'f32)
    sectionTop = metaBox.y + metaBox.h + 22.0'f32
    sectionGap = 26.0'f32
    sectionH =
      max(180.0'f32, (panel.y + panel.h - pad - sectionTop - sectionGap) * 0.5'f32)
    genesisBox = rect(panel.x + pad, sectionTop, contentW, sectionH)
    johnBox =
      rect(panel.x + pad, sectionTop + sectionH + sectionGap, contentW, sectionH)

  renders.addText(
    panelIdx,
    titleBox,
    fonts.title,
    "Genesis 3:19 and John 3:16",
    linear(rgba(36, 45, 58, 255), rgba(72, 95, 130, 255), axis = fgaX),
    hAlign = Center,
    wrap = false,
  )
  renders.addText(
    panelIdx,
    metaBox,
    fonts.label,
    "Hebrew and Greek shaping with KJV English text  |  backend: " & figdrawTextBackend,
    rgba(92, 102, 116, 235),
    hAlign = Center,
    wrap = false,
  )

  renders.addVerseSection(
    panelIdx, genesisBox, "Genesis 3:19", HebrewGenesis319, fonts.hebrew, Right,
    EnglishGenesis319, fonts,
  )
  renders.addVerseSection(
    panelIdx, johnBox, "John 3:16", GreekJohn316, fonts.greek, Center, EnglishJohn316,
    fonts,
  )

proc makeRenderTree*(w, h: float32, fonts: DemoFonts): Renders =
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
    margin = max(26.0'f32, min(w, h) * 0.08'f32)
    panel = rect(
      margin,
      margin,
      max(480.0'f32, w - margin * 2.0'f32),
      max(360.0'f32, h - margin * 2.0'f32),
    )
  result.addVersePanel(root, panel, fonts)

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

  var
    renders = makeRenderTree(0.0'f32, 0.0'f32, fonts)
    lastSize = vec2(0.0'f32, 0.0'f32)

  proc redraw() =
    renderer.beginFrame()
    let sz = appWindow.logicalSize()
    if sz != lastSize:
      lastSize = sz
      renders = makeRenderTree(sz.x, sz.y, fonts)
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
