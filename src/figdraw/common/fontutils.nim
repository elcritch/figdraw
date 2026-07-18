import std/[hashes, unicode]

import pkg/vmath

import ./fonttypes

when figdrawTextBackend != "harfbuzzy" and figdrawTextBackend != "hybrid":
  import pkg/pixie/fonts

import ./shared

import ./imgutils
import ./typefaces
import ./fontglyphs

when defined(figdrawNativeDynlib):
  {.pragma: nativeAbi, exportabi.}
else:
  {.pragma: nativeAbi.}

export FontRef, TypefaceInfo, TypefaceLocalizedName, TypefaceVariationAxis
export font, fontId, fontRef, loadTypeface, getTypefaceInfo, convertFont
export registerStaticTypeface

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
  textBackend.typeset(box, uiSpans, hAlign, vAlign, minContent, wrap, true)

proc typesetForMeasurement*(
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  ## Typesets without generating or publishing glyph images.
  textBackend.typeset(box, uiSpans, hAlign, vAlign, minContent, wrap, false)

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

proc typesetForMeasurement*(
    box: Rect,
    font: FigFont,
    text: string,
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  typesetForMeasurement(box, [(font.fs(), text)], hAlign, vAlign, minContent, wrap)

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

proc typesetForMeasurement*(
    box: Rect,
    font: FontRef,
    text: string,
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  typesetForMeasurement(box, font.font, text, hAlign, vAlign, minContent, wrap)

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

  when figdrawTextBackend != "harfbuzzy" and figdrawTextBackend != "hybrid":
    let fontInfo = glyphFontFor(style.font)
    let cachedFont = (font: fontInfo.font, glyph: fontInfo.glyph)

  var
    contentHash = Hash(0)
    byteOffset = 0

  for glyphIndex, (rune, pos) in glyphs:
    let resolved =
      when figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid":
        textBackend.resolvePlacedGlyph(style.font, rune)
      else:
        (
          glyphFont: cachedFont.glyph,
          glyphId: syntheticFontGlyphId(cachedFont.glyph.fontId, rune),
          advance: cachedFont.font.typeface.getAdvance(rune) * cachedFont.font.scale,
          imageOffset: vec2(0, 0),
          skipsRaster: rune.isWhiteSpace,
        )
    let baselineOffset = resolved.glyphFont.descentAdj
    var baselinePos = pos
    if origin == GlyphTopLeft:
      baselinePos.y = pos.y + baselineOffset

    let drawPos = vec2(baselinePos.x, baselinePos.y - baselineOffset)
    let selection =
      rect(drawPos.x, drawPos.y, resolved.advance, resolved.glyphFont.lineHeight)
    let runeByteLength = ($rune).len

    if result.fonts.len == 0 or result.fonts[^1] != resolved.glyphFont:
      result.fonts.add resolved.glyphFont
      result.spanColors.add style.color
      result.spans.add glyphIndex .. glyphIndex
    else:
      result.spans[^1].b = glyphIndex

    result.sourceRunes.add rune
    result.arrangedGlyphs.add ArrangedGlyph(
      fontId: resolved.glyphFont.fontId,
      glyphId: resolved.glyphId,
      cluster: uint32(glyphIndex),
      source: GlyphSourceRange(
        byteStart: byteOffset,
        byteEnd: byteOffset + runeByteLength,
        runeStart: glyphIndex,
        runeEnd: glyphIndex + 1,
      ),
      rune: rune,
      isWhitespace: resolved.skipsRaster,
      pos: baselinePos,
      advance: vec2(resolved.advance, 0),
      offset: vec2(0, 0),
      imageOffset: resolved.imageOffset,
      rect: selection,
    )
    result.runes.add rune
    result.positions.add baselinePos
    result.selectionRects.add selection
    byteOffset += runeByteLength

    contentHash =
      contentHash !&
      hash(
        (
          resolved.glyphFont.fontId,
          resolved.glyphId,
          rune,
          pos.x,
          pos.y,
          origin,
          style.color,
          figUiScale(),
        )
      )

  result.lines = @[0 .. glyphs.len - 1]
  result.contentHash = !$contentHash

  var
    minX = float32.high
    minY = float32.high
    maxX = -float32.high
    maxY = -float32.high
  for rect in result.selectionRects:
    minX = min(minX, rect.x)
    minY = min(minY, rect.y)
    maxX = max(maxX, rect.x + rect.w)
    maxY = max(maxY, rect.y + rect.h)
  if result.selectionRects.len > 0:
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
