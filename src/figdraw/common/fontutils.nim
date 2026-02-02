import std/[os, unicode, sequtils, tables, strutils, sets, hashes]
import std/isolation

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
import pkg/chronicles

import ./rchannels
import ./imgutils
import ./shared

import ./fonttypes
import ./typefaces
import ./fontglyphs

export loadTypeface, convertFont

proc calcMinMaxContent(
    textLayout: GlyphArrangement
): tuple[maxSize, minSize: Vec2, bounding: Rect] =
  ## estimate the maximum and minimum size of a given typesetting

  var longestWord: Slice[int]
  var longestWordLen: float

  var words = 0
  var wordsHeight = 0.0
  var curr: Slice[int]
  var currLen: float
  var maxWidth: float
  var rect: Rect = rect(float32.high, float32.high, 0, 0)

  # find longest word and count the number of words
  # herein min content width is longest word
  # herein max content height is a word on each line
  var idx = 0
  for glyph in textLayout.glyphs():
    maxWidth += glyph.rect.w
    rect.x = min(rect.x, glyph.rect.x)
    rect.y = min(rect.y, glyph.rect.y)
    rect.w = max(rect.w, glyph.rect.x + glyph.rect.w)
    rect.h = max(rect.h, glyph.rect.y + glyph.rect.h)

    if glyph.rune.isWhiteSpace:
      curr = idx + 1 .. idx
      currLen = 0.0
    else:
      if curr.len() == 1:
        words.inc
        wordsHeight += glyph.lineHeight
      curr.b = idx
      currLen += glyph.rect.w

    if currLen > longestWordLen:
      longestWord = curr
      longestWordLen = currLen

    idx.inc()

  # find tallest font
  var maxLine = 0.0
  for font in textLayout.fonts:
    maxLine = max(maxLine, font.lineHeight)

  # set results
  result.minSize.x = longestWordLen
  result.minSize.y = maxLine

  result.maxSize.x = maxWidth
  result.maxSize.y = wordsHeight

  result.bounding = rect

proc typeset*(
    box: Rect,
    uiSpans: openArray[(UiFont, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  ## does the typesetting using pixie, then converts the typeseet results
  ## into Figuro's own internal types
  ## Primarily done for thread safety
  threadEffects:
    AppMainThread

  var
    wh = box.wh
    sz = uiSpans.mapIt(it[0].size.float)
    minSz = sz.foldl(max(a, b), 0.0)

  var spans: seq[Span]
  var pfs: seq[Font]
  var gfonts: seq[GlyphFont]
  for (uiFont, txt) in uiSpans:
    let (fontId, pf) = uiFont.convertFont()
    pfs.add(pf)
    spans.add(newSpan(txt, pf))
    assert not pf.typeface.isNil
    let lhAdj = pf.lineHeight
    #let lhAdj = (pf.lineHeight - pf.size * pf.lineHeight / pf.defaultLineHeight()) / 2
    gfonts.add GlyphFont(
      fontId: fontId, lineHeight: pf.lineHeight, descentAdj: lhAdj
    )

  var ha: HorizontalAlignment
  case hAlign
  of Left:
    ha = LeftAlign
  of Center:
    ha = CenterAlign
  of Right:
    ha = RightAlign

  var va: VerticalAlignment
  case vAlign
  of Top:
    va = TopAlign
  of Middle:
    va = MiddleAlign
  of Bottom:
    va = BottomAlign

  let arrangement =
    pixie.typeset(spans, bounds = wh, hAlign = ha, vAlign = va, wrap = wrap)
  result = convertArrangement(arrangement, box, uiSpans, hAlign, vAlign, gfonts)

  let content = result.calcMinMaxContent()
  result.minSize = content.minSize
  result.maxSize = content.maxSize
  result.bounding = content.bounding

  if minContent:
    ## calcaulate min width of content
    var wh = wh
    wh.y = result.maxSize.y
    let arr = pixie.typeset(
      spans, bounds = wh, hAlign = LeftAlign, vAlign = TopAlign, wrap = wrap
    )
    let minResult = convertArrangement(arr, box, uiSpans, hAlign, vAlign, gfonts)

    let minContent = minResult.calcMinMaxContent()
    trace "minContent:",
      boxWh = box.wh,
      wh = wh,
      minSize = minContent.minSize,
      maxSize = minContent.maxSize,
      bounding = minContent.bounding,
      boundH = result.bounding.h

    if minContent.bounding.h > result.bounding.h:
      let wh = vec2(wh.x, minContent.bounding.h)
      let minAdjusted =
        pixie.typeset(spans, bounds = wh, hAlign = ha, vAlign = va, wrap = wrap)
      result = convertArrangement(minAdjusted, box, uiSpans, hAlign, vAlign, gfonts)
      let contentAdjusted = result.calcMinMaxContent()
      result.minSize = contentAdjusted.minSize
      result.maxSize = contentAdjusted.maxSize
      result.bounding = contentAdjusted.bounding
      trace "minContent:adjusted",
        boxWh = box.wh,
        wh = wh,
        wrap = wrap,
        minSize = result.minSize,
        maxSize = result.maxSize,
        bounding = result.bounding

      result.minSize.y = result.bounding.h
    else:
      result.minSize.y = max(result.minSize.y, result.bounding.h)

  let maxLineHeight = max(sz)
  result.minSize += vec2(maxLineHeight / 2, 0)
  result.maxSize += vec2(maxLineHeight / 2, 0)
  result.bounding = result.bounding + rect(0, 0, 0, maxLineHeight / 2)
  result.generateGlyphImages()

proc placeGlyphs*(
    font: UiFont,
    glyphs: openArray[(Rune, Vec2)],
    origin: GlyphOrigin = GlyphTopLeft,
): GlyphArrangement =
  ## Builds a glyph arrangement using explicit positions for each glyph.
  ## `origin` controls whether positions are the glyph's top-left or baseline.
  threadEffects:
    AppMainThread

  result = GlyphArrangement()
  if glyphs.len == 0:
    return

  let fontInfo = glyphFontFor(font)
  let cachedFont = (font: fontInfo.font, glyph: fontInfo.glyph)

  var
    runes = newSeqOfCap[Rune](glyphs.len)
    positions = newSeqOfCap[Vec2](glyphs.len)
    selectionRects = newSeqOfCap[Rect](glyphs.len)
    contentHash = Hash(0)

  for (rune, pos) in glyphs:

    let scaledPos = pos
    let descent = cachedFont.glyph.lineHeight - cachedFont.glyph.descentAdj
    var baselinePos = pos
    if origin == GlyphTopLeft:
      baselinePos.y = pos.y + descent

    runes.add(rune)
    positions.add(baselinePos)

    let drawPos = vec2(baselinePos.x, baselinePos.y - descent)
    let advance = cachedFont.font.typeface.getAdvance(rune) *
        cachedFont.font.scale
    selectionRects.add(
      rect(drawPos.x, drawPos.y, advance, cachedFont.glyph.lineHeight)
    )

    contentHash =
      contentHash !& hash((fontInfo.id, rune, pos.x, pos.y, origin, figUiScale()))

  result.lines = @[0 .. glyphs.len - 1]
  result.spans = @[0 .. glyphs.len - 1]
  result.fonts = @[cachedFont.glyph]
  result.runes = runes
  result.positions = positions
  result.selectionRects = selectionRects
  result.contentHash = !$contentHash

  var
    minX = float32.high
    minY = float32.high
    maxX = -float32.high
    maxY = -float32.high
  for rect in selectionRects:
    minX = min(minX, rect.x)
    minY = min(minY, rect.y)
    maxX = max(maxX, rect.x + rect.w)
    maxY = max(maxY, rect.y + rect.h)
  if selectionRects.len > 0:
    let boundingScaled = rect(minX, minY, maxX - minX, maxY - minY)
    result.bounding = boundingScaled
    result.minSize = result.bounding.wh
    result.maxSize = result.bounding.wh

  result.generateGlyphImages()

