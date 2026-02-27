when defined(emscripten):
  import std/[times, unicode, strutils]
else:
  import std/[os, times, unicode, strutils]
import chroma
import pkg/pixie/fonts

import figdraw/windowing/siwinshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer
when not UseMetalBackend:
  import figdraw/utils/glutils

const FontName {.strdefine: "figdraw.defaultfont".}: string = "Ubuntu.ttf"
const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc findPhraseRange(text, phrase: string): Slice[int16] =
  let startByte = text.find(phrase)
  if startByte < 0:
    return 0'i16 .. -1'i16
  let endByte = startByte + phrase.len
  var startRune = 0
  var endRune = -1
  var runeIdx = 0
  var byteIdx = 0
  while byteIdx < text.len:
    if byteIdx == startByte:
      startRune = runeIdx
    if byteIdx < endByte:
      endRune = runeIdx
    else:
      break
    byteIdx += runeLenAt(text, byteIdx)
    runeIdx.inc
  result = startRune.int16 .. endRune.int16

proc buildBodyTextLayout*(
    uiFont: FigFont, textRect: Rect
): tuple[layout: GlyphArrangement, highlightRange: Slice[int16]] =
  let text =
    """
FigDraw text demo

This example uses `src/figdraw/common/fontutils.nim` typesetting + glyph caching,
then renders glyph atlas sprites via the OpenGL renderer.
"""
  let highlightRange = findPhraseRange(text, "renders glyph atlas sprites")
  let bodyFill = rgba(20, 20, 20, 255)
  let openGlFill = linear(rgba(255, 120, 66, 255), rgba(72, 197, 255, 255), axis = fgaY)
  let openGlToken = "OpenGL"
  let openGlIdx = text.find(openGlToken)
  var spans: seq[(FontStyle, string)]
  if openGlIdx >= 0:
    let prefix = text[0 ..< openGlIdx]
    let suffix = text[openGlIdx + openGlToken.len .. ^1]
    if prefix.len > 0:
      spans.add(span(uiFont, bodyFill, prefix))
    spans.add(span(uiFont, openGlFill, openGlToken))
    if suffix.len > 0:
      spans.add(span(uiFont, bodyFill, suffix))
  else:
    spans = @[span(uiFont, bodyFill, text)]
  result.layout = typeset(
    rect(0, 0, textRect.w, textRect.h),
    spans,
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
  )
  result.highlightRange = highlightRange

proc buildMonoWordLayouts*(
    monoFont: FigFont, monoText: string, pad: float32, colors: openArray[Fill]
): seq[GlyphArrangement] =
  let (_, monoPx) = monoFont.convertFont()
  let monoLineHeight =
    (if monoPx.lineHeight >= 0: monoPx.lineHeight
    else: monoPx.defaultLineHeight())
  let monoAdvance = (monoPx.typeface.getAdvance(Rune('M')) * monoPx.scale)
  let colorsSeq = @colors

  var x = pad
  var y = pad
  var wordIdx = 0
  var glyphs: seq[(Rune, Vec2)]
  var layouts: seq[GlyphArrangement]
  proc flushWord(
      glyphs: var seq[(Rune, Vec2)],
      layouts: var seq[GlyphArrangement],
      monoFont: FigFont,
      colors: seq[Fill],
      wordIdx: var int,
  ) =
    if glyphs.len == 0:
      return
    let wordColor =
      if colors.len > 0:
        colors[wordIdx mod colors.len]
      else:
        fill(rgba(0, 0, 0, 255))
    layouts.add(placeGlyphs(fs(monoFont, wordColor), glyphs, origin = GlyphTopLeft))
    wordIdx.inc
    glyphs.setLen(0)

  for rune in monoText.runes:
    if rune == Rune(10):
      flushWord(glyphs, layouts, monoFont, colorsSeq, wordIdx)
      x = pad
      y += monoLineHeight
      continue
    if rune == Rune(32):
      flushWord(glyphs, layouts, monoFont, colorsSeq, wordIdx)
      x += monoAdvance
      continue
    glyphs.add((rune, vec2(x, y)))
    x += monoAdvance

  flushWord(glyphs, layouts, monoFont, colorsSeq, wordIdx)
  result = layouts

proc makeRenderTree*(w, h: float32, uiFont, monoFont: FigFont): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  let z = 0.ZLevel

  let rootIdx = result.addRoot(
    z,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rect(0, 0, w, h),
      fill: rgba(245, 245, 245, 255),
    ),
  )

  let pad = 40'f32
  let cardRect = rect(pad, pad, w - pad * 2, h - pad * 2)
  let cardIdx = result.addChild(
    z,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: cardRect,
      fill: rgba(255, 255, 255, 255),
      stroke: RenderStroke(weight: 2.0, fill: rgba(0, 0, 0, 25).color),
      corners: [16.0'f32, 16.0, 16.0, 16.0],
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 24,
          spread: 0,
          x: 0,
          y: 8,
          fill: rgba(0, 0, 0, 30).color,
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )

  let textPad = 28'f32
  let innerRect = rect(
    cardRect.x + textPad,
    cardRect.y + textPad,
    cardRect.w - textPad * 2,
    cardRect.h - textPad * 2,
  )

  let monoText = "Manual glyphs: Hack Nerd Font\n$ printf(\"hello\")"
  let (_, monoPx) = monoFont.convertFont()
  let monoLineHeight =
    (if monoPx.lineHeight >= 0: monoPx.lineHeight
    else: monoPx.defaultLineHeight())
  let monoPad = 12'f32
  var monoLines = 1
  for rune in monoText.runes:
    if rune == Rune(10):
      monoLines.inc
  let monoHeight = monoLines.float32 * monoLineHeight + monoPad * 2

  let textRect =
    rect(innerRect.x, innerRect.y, innerRect.w, innerRect.h - monoHeight - 12'f32)
  let monoRect =
    rect(innerRect.x, textRect.y + textRect.h + 12'f32, innerRect.w, monoHeight)

  let (layout, highlightRange) = buildBodyTextLayout(uiFont, textRect)

  discard result.addChild(
    z,
    cardIdx,
    Fig(
      kind: nkText,
      childCount: 0,
      zlevel: z,
      screenBox: textRect,
      selectionRange: highlightRange,
      fill: linear(rgba(255, 242, 170, 255), rgba(255, 192, 128, 255), axis = fgaY),
      flags:
        if highlightRange.a <= highlightRange.b:
          {NfSelectText}
        else:
          {},
      textLayout: layout,
    ),
  )

  discard result.addChild(
    z,
    cardIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: monoRect,
      fill: rgba(27, 29, 36, 255),
      stroke: RenderStroke(weight: 1.5, fill: rgba(0, 0, 0, 50).color),
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )
  let monoColors = [
    linear(rgba(236, 238, 245, 255), rgba(182, 214, 255, 255), axis = fgaX),
    rgba(255, 210, 160, 255),
    linear(rgba(166, 223, 255, 255), rgba(196, 255, 198, 255), axis = fgaDiagTLBR),
    rgba(196, 255, 198, 255),
    linear(rgba(255, 187, 229, 255), rgba(255, 214, 152, 255), axis = fgaX),
  ]
  let monoLayouts = buildMonoWordLayouts(monoFont, monoText, monoPad, monoColors)
  for monoLayout in monoLayouts:
    discard result.addChild(
      z,
      cardIdx,
      Fig(
        kind: nkText,
        childCount: 0,
        zlevel: z,
        screenBox: monoRect,
        fill: clearColor,
        textLayout: monoLayout,
      ),
    )

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  var app_running = true

  let fontName = getEnv("FONT", FontName)
  # looks for fonts, fallback to static fonts if not found
  registerStaticTypeface("Ubuntu.ttf", "../data/Ubuntu.ttf")
  registerStaticTypeface("HackNerdFont-Regular.ttf", "../data/HackNerdFont-Regular.ttf")

  let typefaceId = loadTypeface(fontName, @["Ubuntu.ttf"])
  let uiFont = FigFont(typefaceId: typefaceId, size: 28.0'f32)
  let monoTypefaceId = loadTypeface("HackNerdFont-Regular.ttf")
  let monoFont = FigFont(typefaceId: monoTypefaceId, size: 20.0'f32)

  let size = ivec2(900, 600)

  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  when UseVulkanBackend:
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 4096, backendState = SiwinRenderBackend())
    let appWindow = newSiwinWindow(
      renderer,
      size = size,
      fullscreen = false,
      title = siwinWindowTitle("Siwin + Text"),
    )
  else:
    let appWindow = newSiwinWindow(
      size = size, fullscreen = false, title = siwinWindowTitle("Siwin + Text")
    )
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 4096, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()
  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin + Text")

  proc redraw() =
    renderer.beginFrame()
    let sz = appWindow.logicalSize()

    var renders = makeRenderTree(sz.x, sz.y, uiFont, monoFont)
    renderer.renderFrame(renders, sz)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      app_running = false,
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
    while app_running and appWindow.opened:
      appWindow.redraw()
      appWindow.step()

      inc frames
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        echo "fps: ", fps
        fpsFrames = 0
        fpsStart = now
      if RunOnce and frames >= 1:
        app_running = false
      when not defined(emscripten):
        sleep(16)
  finally:
    when not defined(emscripten):
      appWindow.close()
