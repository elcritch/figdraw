import std/[hashes, sequtils, unicode]

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts

import ./imgutils
import ./shared

import ./fonttypes
when figdrawTextBackend == "harfbuzzy":
  import ./textrasters/glyphid_raster
import ./textrasters/pixie_raster

export applyLcdFilter

proc clearGlyphRasterFontCache*(fontId: FontId) =
  when figdrawTextBackend == "harfbuzzy":
    clearGlyphIdFontCache(fontId)
  else:
    discard

proc clearGlyphRasterTypefaceCache*(typefaceId: TypefaceId) =
  when figdrawTextBackend == "harfbuzzy":
    clearGlyphIdTypefaceCache(typefaceId)
  else:
    discard

type GlyphPosition* = ref object ## Represents a glyph position after typesetting.
  fontId*: FontId
  glyphId*: FontGlyphId
  cluster*: uint32
  source*: GlyphSourceRange
  rune*: Rune
  isWhitespace*: bool
  pos*: Vec2 # Where to draw the image character.
  imageOffset*: Vec2
  rect*: Rect
  descent*: float32
  lineHeight*: float32
  fill*: Fill

const glyphVariantSubpixelSteps* = 10

proc clampGlyphVariantSubpixelStep*(subpixelVariant: int): int {.inline.} =
  if subpixelVariant <= 0:
    return 0
  min(subpixelVariant, glyphVariantSubpixelSteps - 1)

proc toGlyphVariantSubpixelStep*(fractionalX: float32): int {.inline.} =
  let clamped = max(0.0'f32, min(fractionalX, 0.999'f32))
  clampGlyphVariantSubpixelStep((clamped * glyphVariantSubpixelSteps.float32).int)

proc hash*(
    glyph: GlyphPosition, lcdFiltering = false, subpixelVariant = 0
): Hash {.inline.} =
  #result = hash((2344, glyph.fontId, glyph.rune, app.uiScale))
  let variant = clampGlyphVariantSubpixelStep(subpixelVariant)
  result = hash((2344, glyph.fontId, glyph.glyphId, lcdFiltering, variant))

proc generateGlyph*(
    glyph: GlyphPosition,
    lcdFiltering = false,
    subpixelVariant = 0,
    force = false,
    upload = true,
): Image {.discardable.} =
  if glyph.isWhitespace:
    return nil

  let
    variant = clampGlyphVariantSubpixelStep(subpixelVariant)
    hashFill = glyph.hash(lcdFiltering = lcdFiltering, subpixelVariant = variant)

  if (not force) and hasImage(hashFill.ImageId):
    return nil

  when figdrawTextBackend == "harfbuzzy":
    renderGlyphIdGlyph(
      hashFill.ImageId,
      glyph.fontId,
      glyph.glyphId,
      glyph.rect,
      glyph.descent,
      glyph.imageOffset,
      lcdFiltering = lcdFiltering,
      subpixelVariant = variant,
      subpixelSteps = glyphVariantSubpixelSteps,
      upload = upload,
    )
  else:
    renderPixieGlyph(
      hashFill.ImageId,
      glyph.fontId,
      glyph.rune,
      glyph.rect,
      lcdFiltering = lcdFiltering,
      subpixelVariant = variant,
      subpixelSteps = glyphVariantSubpixelSteps,
      upload = upload,
    )

proc buildArrangedGlyphsForUtf8(
    runes: Utf8Runes,
    positions: openArray[Vec2],
    selectionRects: openArray[Rect],
    spans: openArray[Slice[int]],
    fonts: openArray[GlyphFont],
): seq[ArrangedGlyph] =
  ## Builds Pixie-compatible arranged glyph records from parallel glyph arrays.
  result = newSeq[ArrangedGlyph](runes.len)

  for spanIndex, span in spans:
    if spanIndex >= fonts.len:
      continue
    let
      font = fonts[spanIndex]
      start = max(span.a, 0)
      stop = min(span.b, runes.len - 1)
    if start > stop:
      continue

    for idx in start .. stop:
      let
        rune = runes[idx]
        byteRange = runes.byteRangeForRune(idx)
        pos =
          if idx < positions.len:
            positions[idx]
          else:
            vec2(0, 0)
        selection =
          if idx < selectionRects.len:
            selectionRects[idx]
          else:
            rect(pos.x, pos.y, 0, 0)
      result[idx] = ArrangedGlyph(
        fontId: font.fontId,
        glyphId: syntheticFontGlyphId(font.fontId, rune),
        cluster: uint32(idx),
        source: GlyphSourceRange(
          byteStart: byteRange.start,
          byteEnd: byteRange.stop,
          runeStart: idx,
          runeEnd: idx + 1,
        ),
        rune: rune,
        isWhitespace: unicode.isWhiteSpace(rune),
        pos: pos,
        advance: vec2(selection.w, 0),
        offset: vec2(0, 0),
        imageOffset: vec2(0, 0),
        rect: selection,
      )

proc buildArrangedGlyphs*(
    runes: Utf8Runes,
    positions: openArray[Vec2],
    selectionRects: openArray[Rect],
    spans: openArray[Slice[int]],
    fonts: openArray[GlyphFont],
): seq[ArrangedGlyph] =
  ## Builds Pixie-compatible arranged glyph records from UTF-8-backed runes.
  buildArrangedGlyphsForUtf8(runes, positions, selectionRects, spans, fonts)

proc buildArrangedGlyphs*(
    runes: openArray[Rune],
    positions: openArray[Vec2],
    selectionRects: openArray[Rect],
    spans: openArray[Slice[int]],
    fonts: openArray[GlyphFont],
): seq[ArrangedGlyph] =
  ## Builds Pixie-compatible arranged glyph records from decoded runes.
  buildArrangedGlyphsForUtf8(
    initArrangementRunes(runes), positions, selectionRects, spans, fonts
  )

iterator glyphs*(arrangement: GlyphArrangement): GlyphPosition =
  var idx = 0
  let arrangedGlyphCount =
    if arrangement.arrangedGlyphs.len > 0:
      arrangement.arrangedGlyphs.len
    else:
      arrangement.runes.len

  block:
    for i, span in arrangement.spans:
      if span.a > span.b:
        continue
      if idx < span.a:
        idx = span.a
      if idx >= arrangedGlyphCount:
        break

      let gfont = arrangement.fonts[i]
      let spanColor =
        if i < arrangement.spanColors.len:
          arrangement.spanColors[i]
        else:
          fill(rgba(0, 0, 0, 255))
      while idx < arrangedGlyphCount and idx in span:
        let arranged =
          if arrangement.arrangedGlyphs.len > 0:
            arrangement.arrangedGlyphs[idx]
          else:
            let rune = arrangement.runes[idx]
            ArrangedGlyph(
              fontId: gfont.fontId,
              glyphId: syntheticFontGlyphId(gfont.fontId, rune),
              cluster: uint32(idx),
              source: GlyphSourceRange(runeStart: idx, runeEnd: idx + 1),
              rune: rune,
              isWhitespace: unicode.isWhiteSpace(rune),
              pos: arrangement.positions[idx],
              imageOffset: vec2(0, 0),
              rect: arrangement.selectionRects[idx],
            )

        # Pixie arrangement positions are baseline positions; descentAdj stores
        # the baseline offset needed to convert to glyph image top-left.
        let descent = gfont.descentAdj

        yield GlyphPosition(
          fontId: arranged.fontId,
          glyphId: arranged.glyphId,
          cluster: arranged.cluster,
          source: arranged.source,
          rune: arranged.rune,
          isWhitespace: arranged.isWhitespace,
          pos: arranged.pos,
          imageOffset: arranged.imageOffset,
          rect: arranged.rect,
          descent: descent,
          lineHeight: gfont.lineHeight,
          fill: spanColor,
        )

        idx.inc()

proc generateGlyphImages*(arrangement: GlyphArrangement, lcdFiltering = false) =
  ## returns Glyph's hash, will generate glyph if needed
  ##
  ## Font Glyphs are generated with Bottom vAlign and Center hAlign
  ## this puts the glyphs in the right position
  ## so that the renderer doesn't need to figure out adjustments

  for glyph in arrangement.glyphs():
    glyph.generateGlyph(lcdFiltering = lcdFiltering)

proc matchesDisplayRunes(source: Utf8Runes, display: openArray[Rune]): bool =
  if source.isNil or source.len != display.len:
    return false
  var index = 0
  for rune in source:
    if rune != display[index]:
      return false
    inc index
  true

proc mapPixieSourceRanges(
    glyphs: var seq[ArrangedGlyph], source: Utf8Runes, runs: openArray[StyledTextRun]
) =
  ## Pixie keeps one display rune per source rune except filtered controls.
  ## Its font-case conversion can change byte widths, so use source positions.
  let bytes = source.bytes
  var glyphIndex = 0
  for run in runs:
    var
      byteIndex = int(run.byteStart)
      runeIndex = int(run.runeStart)
    while byteIndex < int(run.byteEnd):
      let
        rune = bytes.runeAt(byteIndex)
        nextByte = min(byteIndex + max(1, bytes.runeLenAt(byteIndex)), int(run.byteEnd))
      if rune.uint32 >= 32 or rune == Rune(10):
        if glyphIndex >= glyphs.len:
          raise newException(ValueError, "Pixie display runes differ from source runs")
        glyphs[glyphIndex].source = GlyphSourceRange(
          byteStart: byteIndex,
          byteEnd: nextByte,
          runeStart: runeIndex,
          runeEnd: runeIndex + 1,
        )
        inc glyphIndex
      byteIndex = nextByte
      inc runeIndex
  if glyphIndex != glyphs.len:
    raise newException(ValueError, "Pixie display runes differ from source runs")

proc convertArrangement*(
    arrangement: Arrangement,
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    gfonts: seq[GlyphFont],
    minContent = false,
    wrap = false,
    sourceRunes: Utf8Runes = nil,
    sourceRuns: openArray[StyledTextRun] = [],
): GlyphArrangement =
  var
    lines = newSeqOfCap[Slice[int]](arrangement.lines.len())
    spanSlices = newSeqOfCap[Slice[int]](arrangement.spans.len())
    selectionRects = newSeqOfCap[Rect](arrangement.selectionRects.len())
  for line in arrangement.lines:
    lines.add line[0] .. line[1]
  for span in arrangement.spans:
    spanSlices.add span[0] .. span[1]
  for rect in arrangement.selectionRects:
    selectionRects.add rect

  let displayRunes =
    if sourceRunes.matchesDisplayRunes(arrangement.runes):
      sourceRunes
    else:
      initArrangementRunes(arrangement.runes)
  var arrangedGlyphs = buildArrangedGlyphs(
    displayRunes, arrangement.positions, selectionRects, spanSlices, gfonts
  )
  if not sourceRunes.isNil:
    arrangedGlyphs.mapPixieSourceRanges(sourceRunes, sourceRuns)

  result = GlyphArrangement(
    contentHash: block:
      var h = Hash(0)
      h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign, minContent, wrap)
      h = h !& hash(figUiScale())
      !$h,
    lines: lines,
    spans: spanSlices,
    fonts: gfonts,
    spanColors: uiSpans.mapIt(it[0].color),
    sourceRunes: (if sourceRunes.isNil: displayRunes else: sourceRunes),
    arrangedGlyphs: arrangedGlyphs,
    runes: displayRunes,
    positions: arrangement.positions,
    selectionRects: selectionRects,
  )
