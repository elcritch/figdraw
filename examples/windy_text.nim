when defined(emscripten):
  import std/[times, unicode, strutils]
else:
  import std/[os, times, unicode, strutils]
import chroma
import pkg/pixie/fonts

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer
when not UseMetalBackend:
  import figdraw/utils/glutils

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
    uiFont: UiFont, textRect: Rect
): tuple[layout: GlyphArrangement, highlightRange: Slice[int16]] =
  let text =
    """
FigDraw text demo

This example uses `src/figdraw/common/fontutils.nim` typesetting + glyph caching,
then renders glyph atlas sprites via the OpenGL renderer.
"""
  let highlightRange = findPhraseRange(text, "renders glyph atlas sprites")

  result.layout = typeset(
    rect(0, 0, textRect.w, textRect.h),
    [(uiFont, text)],
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
  )
  result.highlightRange = highlightRange

proc buildMonoWordLayouts*(
    monoFont: UiFont, monoText: string, pad: float32
): seq[GlyphArrangement] =
  let (_, monoPx) = monoFont.convertFont()
  let monoLineHeight =
    (if monoPx.lineHeight >= 0: monoPx.lineHeight
    else: monoPx.defaultLineHeight())
  let monoAdvance = (monoPx.typeface.getAdvance(Rune('M')) * monoPx.scale)

  var x = pad
  var y = pad
  var glyphs: seq[(Rune, Vec2)]
  var layouts: seq[GlyphArrangement]
  proc flushWord(
      glyphs: var seq[(Rune, Vec2)],
      layouts: var seq[GlyphArrangement],
      monoFont: UiFont,
  ) =
    if glyphs.len == 0:
      return
    layouts.add(placeGlyphs(monoFont, glyphs, origin = GlyphTopLeft))
    glyphs.setLen(0)

  for rune in monoText.runes:
    if rune == Rune(10):
      flushWord(glyphs, layouts, monoFont)
      x = pad
      y += monoLineHeight
      continue
    if rune == Rune(32):
      flushWord(glyphs, layouts, monoFont)
      x += monoAdvance
      continue
    glyphs.add((rune, vec2(x, y)))
    x += monoAdvance

  flushWord(glyphs, layouts, monoFont)
  result = layouts

proc makeRenderTree*(w, h: float32, uiFont, monoFont: UiFont): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(245, 245, 245, 255).color,
    )
  )

  let pad = 40'f32
  let cardRect = rect(pad, pad, w - pad * 2, h - pad * 2)
  let cardIdx = list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: cardRect,
      fill: rgba(255, 255, 255, 255).color,
      stroke: RenderStroke(weight: 2.0, color: rgba(0, 0, 0, 25).color),
      corners: [16.0'f32, 16.0, 16.0, 16.0],
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 24,
          spread: 0,
          x: 0,
          y: 8,
          color: rgba(0, 0, 0, 30).color,
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

  discard list.addChild(
    cardIdx,
    Fig(
      kind: nkText,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: textRect,
      fill: rgba(20, 20, 20, 255).color,
      stroke: RenderStroke(color: rgba(20, 20, 20, 255).color),
      selectionRange: highlightRange,
      selectionColor: rgba(255, 232, 140, 255).color,
      flags: if highlightRange.a <= highlightRange.b: {NfSelectText} else: {},
      textLayout: layout,
    ),
  )

  let monoLayouts = buildMonoWordLayouts(monoFont, monoText, monoPad)
  discard list.addChild(
    cardIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: monoRect,
      fill: rgba(27, 29, 36, 255).color,
      stroke: RenderStroke(weight: 1.5, color: rgba(0, 0, 0, 50).color),
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )
  let monoColors = [
    rgba(236, 238, 245, 255).color,
    rgba(255, 210, 160, 255).color,
    rgba(166, 223, 255, 255).color,
    rgba(196, 255, 198, 255).color,
    rgba(255, 187, 229, 255).color,
  ]
  for idx, monoLayout in monoLayouts:
    discard list.addChild(
      cardIdx,
      Fig(
        kind: nkText,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: monoRect,
        fill: monoColors[idx mod monoColors.len],
        textLayout: monoLayout,
      ),
    )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  var app_running = true
  if getEnv("HDI") != "":
    setFigUiScale getEnv("HDI").parseFloat()
  else:
    setFigUiScale 1.0

  let typefaceId = loadTypeface("Ubuntu.ttf")
  let uiFont = UiFont(typefaceId: typefaceId, size: 28.0'f32)
  let monoTypefaceId = loadTypeface("HackNerdFont-Regular.ttf")
  let monoFont = UiFont(typefaceId: monoTypefaceId, size: 20.0'f32)

  let size = ivec2(900, 600)

  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  var needsRedraw = true
  let window =
    newWindyWindow(size = size, fullscreen = false, title = "figdraw: Windy + Text")

  let renderer = glrenderer.newFigRenderer(atlasSize = 2048)

  when UseMetalBackend:
    let metalHandle = attachMetalLayer(window, renderer.ctx.metalDevice())
    renderer.ctx.presentLayer = metalHandle.layer

  when UseMetalBackend:
    proc updateMetalLayer() =
      metalHandle.updateMetalLayer(window)

  proc redraw() =
    when UseMetalBackend:
      updateMetalLayer()
    let sz = window.logicalSize()
    let szOrig = window.size()
    let factor = round(szOrig.x.float32 / size.x.float32, 1)
    setFigUiScale factor

    var renders = makeRenderTree(sz.x, sz.y, uiFont, monoFont)
    renderer.renderFrame(renders, sz)
    when not UseMetalBackend:
      window.swapBuffers()

  window.onCloseRequest = proc() =
    app_running = false
  window.onResize = proc() =
    redraw()

  try:
    while app_running:
      pollEvents()
      if needsRedraw:
        redraw()
        needsRedraw = false

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
      window.close()
