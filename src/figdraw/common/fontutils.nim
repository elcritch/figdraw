import std/[hashes, unicode]

import pkg/vmath
import pkg/pixie/fonts

import ./shared

import ./fonttypes
import ./imgutils
import ./typefaces
import ./fontglyphs

when defined(figdrawNativeDynlib):
  {.pragma: nativeAbi, exportabi.}
else:
  {.pragma: nativeAbi.}

export FontRef, fontRef, loadTypeface, convertFont, registerStaticTypeface

when figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid":
  import ./textbackends/harfbuzzy as textBackend
else:
  import ./textbackends/pixie as textBackend

proc fs*(font: FontRef, color: Fill = fill(rgba(0, 0, 0, 255))): FontStyle =
  fs(font.font, color)

proc fsp*(font: FontRef, color: Fill, text: string): (FontStyle, string) =
  fsp(font.font, color, text)

proc span*(font: FontRef, color: Fill, text: string): (FontStyle, string) =
  span(font.font, color, text)

proc clearFontGlyphs*(font: FontRef) =
  clearFontGlyphs(font.fontId)

proc typeset*(
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  textBackend.typeset(box, uiSpans, hAlign, vAlign, minContent, wrap)

proc typeset*(
    box: Rect,
    uiSpans: openArray[(FigFont, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  var styled = newSeqOfCap[(FontStyle, string)](uiSpans.len)
  for (font, text) in uiSpans:
    styled.add((fs(font), text))
  result = typeset(box, styled, hAlign, vAlign, minContent, wrap)

proc typeset*(
    box: Rect,
    font: FigFont,
    text: string,
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement {.nativeAbi.} =
  typeset(box, [(font, text)], hAlign, vAlign, minContent, wrap)

proc typeset*(
    box: Rect,
    uiSpans: openArray[(FontRef, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  var styled = newSeqOfCap[(FontStyle, string)](uiSpans.len)
  for (font, text) in uiSpans:
    styled.add((fs(font), text))
  result = typeset(box, styled, hAlign, vAlign, minContent, wrap)

proc placeGlyphs*(
    style: FontStyle,
    glyphs: openArray[(Rune, Vec2)],
    origin: GlyphOrigin = GlyphTopLeft,
): GlyphArrangement {.nativeAbi.} =
  ## Builds a glyph arrangement using explicit positions for each glyph.
  ## `origin` controls whether positions are the glyph's top-left or baseline.
  threadEffects:
    AppMainThread

  result = GlyphArrangement()
  if glyphs.len == 0:
    return

  let fontInfo = glyphFontFor(style.font)
  let cachedFont = (font: fontInfo.font, glyph: fontInfo.glyph)

  var
    runes = newSeqOfCap[Rune](glyphs.len)
    positions = newSeqOfCap[Vec2](glyphs.len)
    selectionRects = newSeqOfCap[Rect](glyphs.len)
    contentHash = Hash(0)

  for (rune, pos) in glyphs:
    let baselineOffset = cachedFont.glyph.descentAdj
    var baselinePos = pos
    if origin == GlyphTopLeft:
      baselinePos.y = pos.y + baselineOffset

    runes.add(rune)
    positions.add(baselinePos)

    let drawPos = vec2(baselinePos.x, baselinePos.y - baselineOffset)
    let advance = cachedFont.font.typeface.getAdvance(rune) * cachedFont.font.scale
    selectionRects.add(rect(drawPos.x, drawPos.y, advance, cachedFont.glyph.lineHeight))

    contentHash =
      contentHash !&
      hash((fontInfo.id, rune, pos.x, pos.y, origin, style.color, figUiScale()))

  result.lines = @[0 .. glyphs.len - 1]
  result.spans = @[0 .. glyphs.len - 1]
  result.fonts = @[cachedFont.glyph]
  result.spanColors = @[style.color]
  result.sourceRunes = runes
  result.arrangedGlyphs =
    buildArrangedGlyphs(runes, positions, selectionRects, result.spans, result.fonts)
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

proc placeGlyphs*(
    font: FigFont, glyphs: openArray[(Rune, Vec2)], origin: GlyphOrigin = GlyphTopLeft
): GlyphArrangement =
  result = placeGlyphs(fs(font), glyphs, origin)

proc placeGlyphs*(
    font: FontRef, glyphs: openArray[(Rune, Vec2)], origin: GlyphOrigin = GlyphTopLeft
): GlyphArrangement =
  result = placeGlyphs(fs(font), glyphs, origin)
