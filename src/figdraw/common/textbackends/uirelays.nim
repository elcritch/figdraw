## Text laid out with the platform's own measurements, through uirelays.
##
## Each rune is placed where the platform puts it within its word: a word's
## runes are measured as growing prefixes, so kerning and hinted advances are
## the platform's and line widths match what it draws. Words wrap greedily.
## Each rune is one glyph, rendered on its own, so scripts that join letters
## show them unjoined.

import std/[hashes, math, unicode]

import pkg/vmath

import ../fontglyphs
import ../fonttypes
import ../shared
import ../typefaces
import ../textrasters/uirelays_fonts
import ./common

const maxMeasuredRun = 32
  ## Runes measured as one prefix chain. Text without spaces -- CJK, long
  ## identifiers -- restarts the chain here to keep measuring linear.

proc isLayoutControl(rune: Rune): bool {.inline.} =
  rune.uint32 < 32

proc breaksWord(rune: Rune): bool {.inline.} =
  rune.isWhiteSpace or rune.isLayoutControl

type SpanFont = object
  relay: RelayFont
  glyph: GlyphFont
  lineHeight: float32 ## Device pixels.
  baseline: float32 ## Device pixels from the line top.

proc spanFont(style: FontStyle, scale: float32): SpanFont =
  let fontId = cacheFont(style.font)
  result.relay = relayFont(style.font, scale)
  let
    metrics = result.relay.metrics
    cell = float32(metrics.ascent + metrics.descent)
  result.lineHeight =
    if style.font.lineHeight > 0:
      round(style.font.lineHeight * scale)
    else:
      metrics.lineHeight.float32
  result.baseline = round((result.lineHeight - cell) / 2) + metrics.ascent.float32
  result.glyph = GlyphFont(
    fontId: fontId,
    size: style.font.size,
    lineHeight: result.lineHeight / scale,
    descentAdj: metrics.ascent.float32 / scale,
    underline: style.font.underline,
    strikethrough: style.font.strikethrough,
  )

proc measureAdvances(
    runes: openArray[Rune], spanOf: openArray[int], fonts: openArray[SpanFont]
): seq[float32] =
  ## Device pixel advance of each rune.
  result = newSeq[float32](runes.len)
  var i = 0
  while i < runes.len:
    let font = fonts[spanOf[i]].relay
    if runes[i] == Rune(9):
      result[i] = float32(4 * font.relayTextWidth(" "))
      inc i
    elif runes[i].isLayoutControl:
      inc i
    elif runes[i].isWhiteSpace:
      result[i] = font.relayTextWidth($runes[i]).float32
      inc i
    else:
      var
        prefix = ""
        prev = 0
        j = i
      while j < runes.len and spanOf[j] == spanOf[i] and not runes[j].breaksWord and
          j - i < maxMeasuredRun:
        prefix.add runes[j]
        let width = font.relayTextWidth(prefix)
        result[j] = float32(width - prev)
        prev = width
        inc j
      i = j

proc breakLines(
    runes: openArray[Rune], advances: openArray[float32], wrap: bool, maxWidth: float32
): seq[Slice[int]] =
  var
    lineStart = 0
    x = 0'f32
    i = 0
  while i < runes.len:
    if runes[i] == Rune(10):
      result.add lineStart .. i
      lineStart = i + 1
      x = 0
      inc i
    elif wrap and not runes[i].breaksWord:
      var wordEnd = i
      var wordWidth = 0'f32
      while wordEnd < runes.len and not runes[wordEnd].breaksWord:
        wordWidth += advances[wordEnd]
        inc wordEnd
      if x > 0 and x + wordWidth > maxWidth:
        result.add lineStart .. i - 1
        lineStart = i
        x = 0
      for k in i ..< wordEnd:
        # A word wider than the whole line breaks between its runes.
        if x > 0 and x + advances[k] > maxWidth:
          result.add lineStart .. k - 1
          lineStart = k
          x = 0
        x += advances[k]
      i = wordEnd
    else:
      x += advances[i]
      inc i
  if lineStart < runes.len:
    result.add lineStart .. runes.len - 1

proc typesetWithSource(
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent: bool,
    wrap: bool,
    rasterize: bool,
    sourceRunes: Utf8Runes,
): GlyphArrangement =
  threadEffects:
    AppMainThread

  let scale = figUiScale()
  var
    text = ""
    runes: seq[Rune]
    spanOf: seq[int]
    spanFonts: seq[SpanFont]
    spans: seq[Slice[int]]
    glyphFonts: seq[GlyphFont]
    spanColors: seq[Fill]
    sizes: seq[float]
  for (style, spanText) in uiSpans:
    sizes.add style.font.size.float
    if spanText.len == 0:
      continue
    let first = runes.len
    for rune in spanText.runes:
      runes.add rune
      spanOf.add spanFonts.len
    text.add spanText
    let font = spanFont(style, scale)
    spanFonts.add font
    glyphFonts.add font.glyph
    spanColors.add style.color
    spans.add first .. runes.len - 1

  let
    advances = measureAdvances(runes, spanOf, spanFonts)
    boxWidth = box.w * scale
    lines = breakLines(runes, advances, wrap and box.w > 0, boxWidth)
  var
    positions = newSeq[Vec2](runes.len)
    selectionRects = newSeq[Rect](runes.len)
    lineTops = newSeq[float32](lines.len)
    lineHeights = newSeq[float32](lines.len)
    lineBaselines = newSeq[float32](lines.len)
    height = 0'f32
  for li, line in lines:
    for i in line:
      let font = spanFonts[spanOf[i]]
      lineHeights[li] = max(lineHeights[li], font.lineHeight)
      lineBaselines[li] = max(lineBaselines[li], font.baseline)
    lineTops[li] = height
    height += lineHeights[li]

  let yOffset =
    case vAlign
    of Top:
      0'f32
    of Middle:
      round((box.h * scale - height) / 2)
    of Bottom:
      box.h * scale - height
  for li, line in lines:
    var width = 0'f32
    var visibleWidth = 0'f32
    for i in line:
      width += advances[i]
      if not runes[i].breaksWord:
        visibleWidth = width
    var x =
      case hAlign
      of Left:
        0'f32
      of Center:
        round((boxWidth - visibleWidth) / 2)
      of Right:
        boxWidth - visibleWidth
    let top = yOffset + lineTops[li]
    for i in line:
      positions[i] = vec2(x / scale, (top + lineBaselines[li]) / scale)
      selectionRects[i] =
        rect(x / scale, top / scale, advances[i] / scale, lineHeights[li] / scale)
      x += advances[i]

  let displayRunes =
    if sourceRunes.isNil:
      initArrangementRunes(text)
    else:
      sourceRunes
  var arranged =
    buildArrangedGlyphs(displayRunes, positions, selectionRects, spans, glyphFonts)
  for glyph in arranged.mitems:
    glyph.rasterBackend = GlyphRasterBackend.Uirelays
    if glyph.rune.isLayoutControl:
      glyph.isWhitespace = true

  result = GlyphArrangement(
    contentHash: block:
      var h = Hash(0)
      h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign, minContent, wrap)
      h = h !& hash(scale)
      !$h,
    lines: lines,
    spans: spans,
    fonts: glyphFonts,
    spanColors: spanColors,
    sourceRunes: displayRunes,
    arrangedGlyphs: arranged,
    runes: displayRunes,
    positions: positions,
    selectionRects: selectionRects,
  )

  let content = result.calcMinMaxContent()
  result.minSize = content.minSize
  result.maxSize = content.maxSize
  result.bounding = content.bounding
  if minContent:
    result.minSize.y = max(result.minSize.y, result.bounding.h)

  result.addFontSizePadding(sizes)
  if rasterize:
    result.generateGlyphImages()

proc typeset*(
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
    rasterize: bool,
): GlyphArrangement =
  typesetWithSource(box, uiSpans, hAlign, vAlign, minContent, wrap, rasterize, nil)

proc typesetSourceSpans*(
    box: Rect,
    source: Utf8Runes,
    runs: openArray[StyledTextRun],
    styles: openArray[FontStyle],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent, wrap, rasterize: bool,
): GlyphArrangement =
  ## Runes map one to one onto glyphs, so the source is the display text.
  var spans = newSeqOfCap[(FontStyle, string)](runs.len)
  for run in runs:
    spans.add(
      (
        styles[int(uint32(run.styleId))],
        source.bytes[int(run.byteStart) ..< int(run.byteEnd)],
      )
    )
  typesetWithSource(box, spans, hAlign, vAlign, minContent, wrap, rasterize, source)

proc resolvePlacedGlyph*(
    font: FigFont, rune: Rune
): tuple[
  glyphFont: GlyphFont,
  glyphId: FontGlyphId,
  advance: float32,
  imageOffset: Vec2,
  skipsRaster: bool,
] =
  ## Resolves a rune for explicit placement without laying out text.
  let
    scale = figUiScale()
    span = spanFont(FontStyle(font: font), scale)
  result.glyphFont = span.glyph
  result.glyphId = syntheticFontGlyphId(span.glyph.fontId, rune)
  result.skipsRaster = rune.breaksWord
  if not rune.isLayoutControl:
    result.advance = span.relay.relayTextWidth($rune).float32 / scale
