import std/[hashes, unicode]
import uimaths
import filltypes

export uimaths
export filltypes

import pkg/chroma
export chroma

when defined(figdrawNativeDynlib):
  {.pragma: nativeAbi, exportabi.}
else:
  {.pragma: nativeAbi.}

type
  TypefaceId* = distinct Hash
  FontId* = distinct Hash
  GlyphId* = distinct Hash
  FontGlyphId* = distinct uint32
  FontName* = distinct string

  FontCase* = enum
    NormalCase
    UpperCase
    LowerCase
    TitleCase

  FontHorizontal* = enum
    Left
    Center
    Right

  FontVertical* = enum
    Top
    Middle
    Bottom

  GlyphOrigin* = enum
    GlyphTopLeft
    GlyphBaseline

  GlyphFont* = object
    fontId*: FontId
    size*: float32 ## Font size in pixels.
    lineHeight*: float32
    descentAdj*: float32
    underline*: bool
    strikethrough*: bool
      ## The line height in pixels or autoLineHeight for the font's default line height.

  FontFeature* = object
    tag*: string ## OpenType feature tag, for example "liga" or "kern".
    value*: uint32 ## Feature value. Most boolean features use 0 or 1.
    start*: uint32 ## Inclusive glyph-range start for the feature.
    ending*: uint32 ## Exclusive glyph-range end for the feature.

  FontVariation* = object
    tag*: string ## OpenType variation axis tag, for example "wght" or "wdth".
    value*: float32 ## Axis coordinate in the font's design-space units.

  FigFont* = object
    typefaceId*: TypefaceId
    size*: float32 = 12.0'f32 ## Font size in pixels.
    lineHeight*: float32 ## The line height in pixels
    lineHeightDefault*: float32
    fontCase*: FontCase
    underline*: bool ## Apply an underline.
    strikethrough*: bool ## Apply a strikethrough.
    noKerningAdjustments*: bool ## Optionally disable kerning pair adjustments
    fallbackTypefaceIds*: seq[TypefaceId] ## Ordered font fallback chain.
    features*: seq[FontFeature] ## OpenType features applied while shaping.
    variations*: seq[FontVariation] ## OpenType variable-axis coordinates.

  FontStyle* = object
    font*: FigFont
    color*: Fill

  GlyphSourceRange* = object
    byteStart*: int ## Inclusive source byte index.
    byteEnd*: int ## Exclusive source byte index.
    runeStart*: int ## Inclusive index into GlyphArrangement.sourceRunes.
    runeEnd*: int ## Exclusive index into GlyphArrangement.sourceRunes.

  ArrangedGlyph* = object
    fontId*: FontId
    glyphId*: FontGlyphId
    cluster*: uint32
    source*: GlyphSourceRange
    rune*: Rune ## Cheap first/source rune for compatibility and diagnostics.
    isWhitespace*: bool
    pos*: Vec2
    advance*: Vec2
    offset*: Vec2
    imageOffset*: Vec2 ## Offset from baseline top-left to the raster image origin.
    rect*: Rect

  GlyphArrangement* = object
    contentHash*: Hash
    lines*: seq[Slice[int]] ## The (start, stop) of the lines of text.
    spans*: seq[Slice[int]] ## The (start, stop) of the spans in the text.
    fonts*: seq[GlyphFont] ## The font for each span.
    spanColors*: seq[Fill] ## The fill for each span.
    sourceRunes*: seq[Rune] ## The decoded source runes for glyph source ranges.
    arrangedGlyphs*: seq[ArrangedGlyph] ## Glyph-id-first placement data.
    runes*: seq[Rune] ## The runes of the text.
    positions*: seq[Vec2] ## The positions of the glyphs for each rune.
    selectionRects*: seq[Rect] ## The selection rects for each glyph.
    maxSize*: Vec2
    minSize*: Vec2
    bounding*: Rect

  TextCaretAffinity* = enum
    CaretLeading
    CaretInside
    CaretTrailing

  TextCaretPosition* = object
    sourceRune*: int ## Source insertion index in `GlyphArrangement.sourceRunes`.
    glyphIndex*: int ## Visual glyph index that produced this caret position.
    lineIndex*: int
    affinity*: TextCaretAffinity
    pos*: Vec2 ## Local caret top position.
    rect*: Rect ## Local caret rectangle.

  SelectionSourceKind = enum
    sskRunes
    sskBytes

const figdrawTextBackend* {.strdefine.} = "pixie"

static:
  doAssert figdrawTextBackend in ["pixie", "harfbuzzy", "hybrid"]

proc hash*(id: TypefaceId): Hash {.borrow.}
proc `==`*(a, b: TypefaceId): bool {.borrow.}

proc hash*(id: FontId): Hash {.borrow.}
proc `==`*(a, b: FontId): bool {.borrow.}

proc hash*(id: GlyphId): Hash {.borrow.}
proc `==`*(a, b: GlyphId): bool {.borrow.}

proc hash*(id: FontGlyphId): Hash {.borrow.}
proc `==`*(a, b: FontGlyphId): bool {.borrow.}
proc `$`*(id: FontGlyphId): string {.borrow.}

proc hash*(name: FontName): Hash {.borrow.}
proc `==`*(a, b: FontName): bool {.borrow.}
proc `$`*(name: FontName): string {.borrow.}

func fontFeature*(
    tag: string, value = 1'u32, start = 0'u32, ending = uint32.high
): FontFeature =
  ## Creates an OpenType feature setting for Harfbuzz-backed shaping.
  FontFeature(tag: tag, value: value, start: start, ending: ending)

func fontVariation*(tag: string, value: float32): FontVariation =
  ## Creates an OpenType variable-axis coordinate for Harfbuzz-backed fonts.
  FontVariation(tag: tag, value: value)

proc hash*(feature: FontFeature): Hash =
  hash((feature.tag, feature.value, feature.start, feature.ending))

proc hash*(variation: FontVariation): Hash =
  hash((variation.tag, variation.value))

func syntheticFontGlyphId*(fontId: FontId, rune: Rune): FontGlyphId {.inline.} =
  ## Returns the Pixie-compatible synthetic glyph id for a source rune.
  ## The id is interpreted together with fontId by render/cache code.
  discard fontId
  FontGlyphId(rune.uint32)

func sourceRune*(arrangement: GlyphArrangement, glyphIndex: int): Rune {.inline.} =
  ## Returns the cheap representative source rune for a glyph.
  if arrangement.arrangedGlyphs.len > 0:
    arrangement.arrangedGlyphs[glyphIndex].rune
  else:
    arrangement.runes[glyphIndex]

func sourceRuneRange*(
    arrangement: GlyphArrangement, glyphIndex: int
): Slice[int] {.inline.} =
  ## Returns the inclusive source-rune range for a glyph.
  let source =
    if arrangement.arrangedGlyphs.len > 0:
      arrangement.arrangedGlyphs[glyphIndex].source
    else:
      GlyphSourceRange(runeStart: glyphIndex, runeEnd: glyphIndex + 1)
  result = source.runeStart .. source.runeEnd - 1

iterator sourceRunes*(arrangement: GlyphArrangement, glyphIndex: int): Rune =
  ## Iterates the source runes mapped to a glyph.
  let sourceRange = arrangement.sourceRuneRange(glyphIndex)
  if sourceRange.a <= sourceRange.b:
    if arrangement.sourceRunes.len > 0:
      for i in sourceRange:
        yield arrangement.sourceRunes[i]
    else:
      for i in sourceRange:
        yield arrangement.runes[i]

func sourceIntersects(
    source: GlyphSourceRange, runeStart, runeEnd: int
): bool {.inline.} =
  source.runeStart < runeEnd and runeStart < source.runeEnd

func byteSourceIntersects(
    source: GlyphSourceRange, byteStart, byteEnd: int
): bool {.inline.} =
  source.byteStart < byteEnd and byteStart < source.byteEnd

func glyphSource(
    arrangement: GlyphArrangement, glyphIndex: int
): GlyphSourceRange {.inline.} =
  if arrangement.arrangedGlyphs.len > 0:
    arrangement.arrangedGlyphs[glyphIndex].source
  else:
    GlyphSourceRange(
      runeStart: glyphIndex,
      runeEnd: glyphIndex + 1,
      byteStart: glyphIndex,
      byteEnd: glyphIndex + 1,
    )

func glyphRangeFor*(
    arrangement: GlyphArrangement, sourceRange: Slice[int]
): Slice[int] {.nativeAbi.} =
  ## Returns the inclusive glyph range touching an inclusive source-rune range.
  ## Returns `0 .. -1` when no glyph intersects the source range.
  if sourceRange.a > sourceRange.b:
    return 0 .. -1

  let
    runeStart = max(sourceRange.a, 0)
    runeEnd = sourceRange.b + 1
    glyphCount =
      if arrangement.arrangedGlyphs.len > 0:
        arrangement.arrangedGlyphs.len
      else:
        arrangement.runes.len

  result = 0 .. -1
  for glyphIndex in 0 ..< glyphCount:
    if arrangement.glyphSource(glyphIndex).sourceIntersects(runeStart, runeEnd):
      if result.a > result.b:
        result = glyphIndex .. glyphIndex
      else:
        result.b = glyphIndex

func glyphRangeForRawBytes*(
    arrangement: GlyphArrangement, byteRange: Slice[int]
): Slice[int] =
  ## Returns the inclusive glyph range touching an inclusive raw source-byte range.
  ## Returns `0 .. -1` when no glyph intersects the source range.
  if byteRange.a > byteRange.b:
    return 0 .. -1

  let
    byteStart = max(byteRange.a, 0)
    byteEnd = byteRange.b + 1
    glyphCount =
      if arrangement.arrangedGlyphs.len > 0:
        arrangement.arrangedGlyphs.len
      else:
        arrangement.runes.len

  result = 0 .. -1
  for glyphIndex in 0 ..< glyphCount:
    if arrangement.glyphSource(glyphIndex).byteSourceIntersects(byteStart, byteEnd):
      if result.a > result.b:
        result = glyphIndex .. glyphIndex
      else:
        result.b = glyphIndex

func glyphCount*(arrangement: GlyphArrangement): int {.nativeAbi.} =
  ## Returns the number of visual glyphs in the arrangement.
  if arrangement.arrangedGlyphs.len > 0:
    arrangement.arrangedGlyphs.len
  else:
    arrangement.runes.len

func rectForGlyph(arrangement: GlyphArrangement, glyphIndex: int): Rect {.inline.} =
  if arrangement.arrangedGlyphs.len > 0:
    arrangement.arrangedGlyphs[glyphIndex].rect
  else:
    arrangement.selectionRects[glyphIndex]

func glyphSourceRange*(
    arrangement: GlyphArrangement, glyphIndex: int
): GlyphSourceRange {.nativeAbi.} =
  ## Returns the source byte/rune range that produced a visual glyph.
  if glyphIndex < 0 or glyphIndex >= arrangement.glyphCount():
    return
  arrangement.glyphSource(glyphIndex)

func glyphRect*(arrangement: GlyphArrangement, glyphIndex: int): Rect {.nativeAbi.} =
  ## Returns the local visual glyph rectangle, or an empty rectangle when out of range.
  if glyphIndex < 0 or glyphIndex >= arrangement.glyphCount():
    return rect(0, 0, 0, 0)
  arrangement.rectForGlyph(glyphIndex)

func glyphFont*(
    arrangement: GlyphArrangement, glyphIndex: int
): GlyphFont {.nativeAbi.} =
  ## Returns the font metrics associated with a visual glyph.
  for fontIndex, span in arrangement.spans:
    if glyphIndex in span and fontIndex < arrangement.fonts.len:
      return arrangement.fonts[fontIndex]
  if arrangement.fonts.len > 0:
    arrangement.fonts[0]
  else:
    GlyphFont()

func sourceIntersectsSelection(
    source: GlyphSourceRange,
    selectionStart, selectionEnd: int,
    sourceKind: SelectionSourceKind,
): bool {.inline.} =
  case sourceKind
  of sskRunes:
    source.sourceIntersects(selectionStart, selectionEnd)
  of sskBytes:
    source.byteSourceIntersects(selectionStart, selectionEnd)

func normalizedGlyphLine(arrangement: GlyphArrangement, line: Slice[int]): Slice[int] =
  let glyphCount = arrangement.glyphCount()
  if glyphCount == 0:
    return 0 .. -1

  result = max(line.a, 0) .. min(line.b, glyphCount - 1)
  if result.a > result.b:
    result = 0 .. -1

func selectionLineBox(arrangement: GlyphArrangement, line: Slice[int]): Rect =
  var
    foundGlyph = false
    minY = float32.high
    maxY = -float32.high

  for glyphIndex in line:
    let glyphRect = arrangement.rectForGlyph(glyphIndex)
    minY = min(minY, glyphRect.y)
    maxY = max(maxY, glyphRect.y + glyphRect.h)
    foundGlyph = true

  if foundGlyph:
    result = rect(0, minY, 0, max(maxY - minY, 0.0'f32))
  else:
    result = rect(0, 0, 0, 0)

func lineForGlyph(arrangement: GlyphArrangement, glyphIndex: int): Slice[int] =
  if arrangement.lines.len > 0:
    for line in arrangement.lines:
      if glyphIndex >= line.a and glyphIndex <= line.b:
        return line
  0 .. arrangement.glyphCount() - 1

func lineIndexForGlyph(arrangement: GlyphArrangement, glyphIndex: int): int =
  for lineIndex, line in arrangement.lines:
    if glyphIndex >= line.a and glyphIndex <= line.b:
      return lineIndex
  0

func glyphLineIndex*(arrangement: GlyphArrangement, glyphIndex: int): int =
  ## Returns the visual line index for a glyph, or `-1` when out of range.
  if glyphIndex < 0 or glyphIndex >= arrangement.glyphCount():
    return -1
  arrangement.lineIndexForGlyph(glyphIndex)

func glyphLineRange*(arrangement: GlyphArrangement, glyphIndex: int): Slice[int] =
  ## Returns the normalized visual glyph range for the line containing a glyph.
  if glyphIndex < 0 or glyphIndex >= arrangement.glyphCount():
    return 0 .. -1
  arrangement.normalizedGlyphLine(arrangement.lineForGlyph(glyphIndex))

func lineGlyphRanges*(arrangement: GlyphArrangement): seq[Slice[int]] {.nativeAbi.} =
  ## Returns normalized visual-line glyph ranges for this arrangement.
  let count = arrangement.glyphCount()
  if count == 0:
    return
  if arrangement.lines.len == 0:
    result.add 0 .. count - 1
    return

  for rawLine in arrangement.lines:
    let line = arrangement.normalizedGlyphLine(rawLine)
    if line.a <= line.b:
      result.add line

func layoutContentSize*(arrangement: GlyphArrangement): Vec2 {.nativeAbi.} =
  ## Returns the content size implied by arranged glyph bounds and max size.
  vec2(
    max(arrangement.maxSize.x, arrangement.bounding.w),
    max(arrangement.maxSize.y, arrangement.bounding.h),
  )

func glyphAppearsRtl(arrangement: GlyphArrangement, glyphIndex: int): bool =
  let
    line = arrangement.lineForGlyph(glyphIndex)
    source = arrangement.glyphSource(glyphIndex)
  if glyphIndex > line.a:
    let prevSource = arrangement.glyphSource(glyphIndex - 1)
    if prevSource.runeStart > source.runeStart:
      return true
  if glyphIndex < line.b:
    let nextSource = arrangement.glyphSource(glyphIndex + 1)
    if nextSource.runeStart < source.runeStart:
      return true
  false

func sameSourceRange(a, b: GlyphSourceRange): bool {.inline.} =
  a.byteStart == b.byteStart and a.byteEnd == b.byteEnd and a.runeStart == b.runeStart and
    a.runeEnd == b.runeEnd

func clusterGlyphRangeForGlyph(
    arrangement: GlyphArrangement, glyphIndex: int
): Slice[int] =
  let
    line = arrangement.lineForGlyph(glyphIndex)
    source = arrangement.glyphSource(glyphIndex)

  result = glyphIndex .. glyphIndex
  while result.a > line.a and
      arrangement.glyphSource(result.a - 1).sameSourceRange(source):
    dec result.a
  while result.b < line.b and
      arrangement.glyphSource(result.b + 1).sameSourceRange(source):
    inc result.b

func clusterRectForGlyph(arrangement: GlyphArrangement, glyphIndex: int): Rect =
  let cluster = arrangement.clusterGlyphRangeForGlyph(glyphIndex)
  var
    minX = float32.high
    minY = float32.high
    maxX = -float32.high
    maxY = -float32.high
    foundGlyph = false

  for clusterGlyphIndex in cluster:
    let glyphRect = arrangement.rectForGlyph(clusterGlyphIndex)
    minX = min(minX, min(glyphRect.x, glyphRect.x + glyphRect.w))
    minY = min(minY, glyphRect.y)
    maxX = max(maxX, max(glyphRect.x, glyphRect.x + glyphRect.w))
    maxY = max(maxY, glyphRect.y + glyphRect.h)
    foundGlyph = true

  if foundGlyph:
    rect(minX, minY, maxX - minX, maxY - minY)
  else:
    arrangement.rectForGlyph(glyphIndex)

func glyphSelectionRectsForRange(
    arrangement: GlyphArrangement,
    sourceRange: Slice[int],
    sourceKind: SelectionSourceKind,
): seq[Rect] =
  if sourceRange.a > sourceRange.b:
    return

  let
    selectionStart = max(sourceRange.a, 0)
    selectionEnd = sourceRange.b + 1
  if selectionEnd <= selectionStart:
    return

  for glyphIndex in 0 ..< arrangement.glyphCount():
    let source = arrangement.glyphSource(glyphIndex)
    if source.sourceIntersectsSelection(selectionStart, selectionEnd, sourceKind):
      result.add arrangement.rectForGlyph(glyphIndex)

func glyphSelectionRectsFor*(
    arrangement: GlyphArrangement, sourceRange: Slice[int]
): seq[Rect] =
  ## Returns raw glyph rectangles for glyphs touching a source-rune range.
  glyphSelectionRectsForRange(arrangement, sourceRange, sskRunes)

func glyphSelectionRectsForRawBytes*(
    arrangement: GlyphArrangement, byteRange: Slice[int]
): seq[Rect] =
  ## Returns raw glyph rectangles for glyphs touching a raw source-byte range.
  glyphSelectionRectsForRange(arrangement, byteRange, sskBytes)

func sourceBounds(
    source: GlyphSourceRange, sourceKind: SelectionSourceKind
): tuple[start, ending: int] {.inline.} =
  case sourceKind
  of sskRunes:
    (source.runeStart, source.runeEnd)
  of sskBytes:
    (source.byteStart, source.byteEnd)

func selectedGlyphRectForRange(
    arrangement: GlyphArrangement,
    glyphIndex: int,
    selectionStart, selectionEnd: int,
    sourceKind: SelectionSourceKind,
): Rect =
  let
    source = arrangement.glyphSource(glyphIndex)
    bounds = source.sourceBounds(sourceKind)
    clippedStart = max(selectionStart, bounds.start)
    clippedEnd = min(selectionEnd, bounds.ending)
  if clippedEnd <= clippedStart or bounds.ending <= bounds.start:
    return rect(0, 0, 0, 0)

  let
    glyphRect = arrangement.clusterRectForGlyph(glyphIndex)
    minX = min(glyphRect.x, glyphRect.x + glyphRect.w)
    maxX = max(glyphRect.x, glyphRect.x + glyphRect.w)
    width = maxX - minX
    sourceLen = max(bounds.ending - bounds.start, 1).float32
    startT =
      max(0.0'f32, min((clippedStart - bounds.start).float32 / sourceLen, 1.0'f32))
    endT = max(0.0'f32, min((clippedEnd - bounds.start).float32 / sourceLen, 1.0'f32))
    rtl = arrangement.glyphAppearsRtl(glyphIndex)
    startX =
      if rtl:
        maxX - width * startT
      else:
        minX + width * startT
    endX =
      if rtl:
        maxX - width * endT
      else:
        minX + width * endT

  rect(min(startX, endX), glyphRect.y, abs(endX - startX), glyphRect.h)

func flushSelectionBand(bands: var seq[Rect], band: var Rect, bandActive: var bool) =
  if bandActive:
    bands.add band
    bandActive = false

func addGlyphToSelectionBand(
    band: var Rect, bandActive: var bool, lineBox, glyphRect: Rect
) =
  let
    glyphMinX = min(glyphRect.x, glyphRect.x + glyphRect.w)
    glyphMaxX = max(glyphRect.x, glyphRect.x + glyphRect.w)

  if bandActive:
    let
      bandMinX = min(band.x, glyphMinX)
      bandMaxX = max(band.x + band.w, glyphMaxX)
    band = rect(bandMinX, lineBox.y, bandMaxX - bandMinX, lineBox.h)
  else:
    band = rect(glyphMinX, lineBox.y, glyphMaxX - glyphMinX, lineBox.h)
    bandActive = true

func addSelectionBandsForLine(
    arrangement: GlyphArrangement,
    line: Slice[int],
    selectionStart, selectionEnd: int,
    sourceKind: SelectionSourceKind,
    bands: var seq[Rect],
) =
  let glyphLine = arrangement.normalizedGlyphLine(line)
  if glyphLine.a <= glyphLine.b:
    let lineBox = arrangement.selectionLineBox(glyphLine)
    var
      band = rect(0, lineBox.y, 0, lineBox.h)
      bandActive = false

    for glyphIndex in glyphLine:
      let source = arrangement.glyphSource(glyphIndex)
      if source.sourceIntersectsSelection(selectionStart, selectionEnd, sourceKind):
        let selectionRect = arrangement.selectedGlyphRectForRange(
          glyphIndex, selectionStart, selectionEnd, sourceKind
        )
        band.addGlyphToSelectionBand(bandActive, lineBox, selectionRect)
      else:
        bands.flushSelectionBand(band, bandActive)

    bands.flushSelectionBand(band, bandActive)

func selectionBandsForRange(
    arrangement: GlyphArrangement,
    sourceRange: Slice[int],
    sourceKind: SelectionSourceKind,
): seq[Rect] =
  if sourceRange.a > sourceRange.b:
    return

  let
    selectionStart = max(sourceRange.a, 0)
    selectionEnd = sourceRange.b + 1
  if selectionEnd <= selectionStart:
    return

  if arrangement.lines.len > 0:
    for line in arrangement.lines:
      arrangement.addSelectionBandsForLine(
        line, selectionStart, selectionEnd, sourceKind, result
      )
  else:
    arrangement.addSelectionBandsForLine(
      0 .. arrangement.glyphCount() - 1,
      selectionStart,
      selectionEnd,
      sourceKind,
      result,
    )

func selectionBandsFor*(
    arrangement: GlyphArrangement, sourceRange: Slice[int]
): seq[Rect] =
  ## Returns merged visual selection bands for a source-rune range.
  selectionBandsForRange(arrangement, sourceRange, sskRunes)

func selectionBandsForRawBytes*(
    arrangement: GlyphArrangement, byteRange: Slice[int]
): seq[Rect] =
  ## Returns merged visual selection bands for a raw source-byte range.
  selectionBandsForRange(arrangement, byteRange, sskBytes)

func selectionRectsFor*(
    arrangement: GlyphArrangement, sourceRange: Slice[int]
): seq[Rect] {.nativeAbi.} =
  ## Returns merged visual selection bands for a source-rune range.
  ## Use `glyphSelectionRectsFor` for raw per-glyph rectangles.
  arrangement.selectionBandsFor(sourceRange)

func selectionRectsForRawBytes*(
    arrangement: GlyphArrangement, byteRange: Slice[int]
): seq[Rect] =
  ## Returns merged visual selection bands for a raw source-byte range.
  ## Use `glyphSelectionRectsForRawBytes` for raw per-glyph rectangles.
  arrangement.selectionBandsForRawBytes(byteRange)

func containsPoint(rect: Rect, point: Vec2): bool {.inline.} =
  point.x >= rect.x and point.y >= rect.y and point.x < rect.x + rect.w and
    point.y < rect.y + rect.h

func glyphIndexAt*(arrangement: GlyphArrangement, point: Vec2): int {.nativeAbi.} =
  ## Returns the glyph index at a local text-layout point, or `-1`.
  let glyphCount =
    if arrangement.arrangedGlyphs.len > 0:
      arrangement.arrangedGlyphs.len
    else:
      arrangement.selectionRects.len

  for glyphIndex in 0 ..< glyphCount:
    if arrangement.rectForGlyph(glyphIndex).containsPoint(point):
      return glyphIndex
  -1

func sourceRuneRangeAt*(
    arrangement: GlyphArrangement, point: Vec2
): Slice[int] {.nativeAbi.} =
  ## Returns the source-rune range at a local text-layout point, or `0 .. -1`.
  let glyphIndex = arrangement.glyphIndexAt(point)
  if glyphIndex < 0:
    return 0 .. -1
  arrangement.sourceRuneRange(glyphIndex)

func sourceRuneCount*(arrangement: GlyphArrangement): int {.nativeAbi.} =
  ## Returns the number of source runes represented by the arrangement.
  if arrangement.sourceRunes.len > 0:
    arrangement.sourceRunes.len
  else:
    arrangement.runes.len

func caretX(glyphRect: Rect, rtl, sourceStart: bool): float32 {.inline.} =
  if sourceStart:
    if rtl:
      glyphRect.x + glyphRect.w
    else:
      glyphRect.x
  else:
    if rtl:
      glyphRect.x
    else:
      glyphRect.x + glyphRect.w

func sameCaret(a, b: TextCaretPosition): bool {.inline.} =
  a.sourceRune == b.sourceRune and a.lineIndex == b.lineIndex and
    abs(a.pos.x - b.pos.x) < 0.01'f32 and abs(a.pos.y - b.pos.y) < 0.01'f32

func addCaret(carets: var seq[TextCaretPosition], caret: TextCaretPosition) =
  for existing in carets:
    if existing.sameCaret(caret):
      return
  carets.add caret

func caretPositionsFor*(
    arrangement: GlyphArrangement, sourceRune: int
): seq[TextCaretPosition] {.nativeAbi.} =
  ## Returns visual caret positions for a source insertion index.
  ## Bidi boundaries can produce more than one visual position.
  let sourceCount = arrangement.sourceRuneCount()
  if sourceRune < 0 or sourceRune > sourceCount:
    return

  let glyphCount = arrangement.glyphCount()
  if glyphCount == 0:
    if sourceRune == 0:
      result.add TextCaretPosition(
        sourceRune: 0,
        glyphIndex: -1,
        lineIndex: 0,
        affinity: CaretInside,
        pos: vec2(0, 0),
        rect: rect(0, 0, 0, 0),
      )
    return

  for glyphIndex in 0 ..< glyphCount:
    let
      source = arrangement.glyphSource(glyphIndex)
      glyphRect = arrangement.clusterRectForGlyph(glyphIndex)
      rtl = arrangement.glyphAppearsRtl(glyphIndex)
      lineIndex = arrangement.lineIndexForGlyph(glyphIndex)

    if source.runeStart == sourceRune:
      let x = glyphRect.caretX(rtl, sourceStart = true)
      result.addCaret TextCaretPosition(
        sourceRune: sourceRune,
        glyphIndex: glyphIndex,
        lineIndex: lineIndex,
        affinity: CaretLeading,
        pos: vec2(x, glyphRect.y),
        rect: rect(x, glyphRect.y, 0, glyphRect.h),
      )

    if source.runeEnd == sourceRune:
      let x = glyphRect.caretX(rtl, sourceStart = false)
      result.addCaret TextCaretPosition(
        sourceRune: sourceRune,
        glyphIndex: glyphIndex,
        lineIndex: lineIndex,
        affinity: CaretTrailing,
        pos: vec2(x, glyphRect.y),
        rect: rect(x, glyphRect.y, 0, glyphRect.h),
      )

    if sourceRune > source.runeStart and sourceRune < source.runeEnd:
      let
        rangeLen = max(source.runeEnd - source.runeStart, 1)
        t = (sourceRune - source.runeStart).float32 / rangeLen.float32
        x =
          if rtl:
            glyphRect.x + glyphRect.w * (1.0'f32 - t)
          else:
            glyphRect.x + glyphRect.w * t
      result.addCaret TextCaretPosition(
        sourceRune: sourceRune,
        glyphIndex: glyphIndex,
        lineIndex: lineIndex,
        affinity: CaretInside,
        pos: vec2(x, glyphRect.y),
        rect: rect(x, glyphRect.y, 0, glyphRect.h),
      )

func nearestSourceRuneForCaretPoint*(
    arrangement: GlyphArrangement, point: Vec2
): int {.nativeAbi.} =
  ## Returns the source insertion index nearest to a local text-layout point.
  let sourceCount = arrangement.sourceRuneCount()
  result = 0
  var bestDistance = float32.high
  for sourceRune in 0 .. sourceCount:
    for caret in arrangement.caretPositionsFor(sourceRune):
      let
        dx = point.x - caret.pos.x
        dy =
          if point.y < caret.rect.y:
            caret.rect.y - point.y
          elif point.y > caret.rect.y + caret.rect.h:
            point.y - (caret.rect.y + caret.rect.h)
          else:
            0.0'f32
        distance = dx * dx + dy * dy
      if distance < bestDistance:
        bestDistance = distance
        result = sourceRune

proc hash*(fnt: FigFont): Hash =
  var h = Hash(0)
  for n, f in fnt.fieldPairs():
    when n != "paints":
      h = h !& hash(f)
  result = !$h

proc hash*(style: FontStyle): Hash =
  var h = Hash(0)
  h = h !& hash(style.font)
  h = h !& hash(style.color)
  result = !$h

proc fs*(font: FigFont, color: Fill = fill(rgba(0, 0, 0, 255))): FontStyle =
  ## helper for making font style objects
  FontStyle(font: font, color: color)

proc fsp*(font: FigFont, color: Fill, text: string): (FontStyle, string) =
  ## helper for making font span objects
  (FontStyle(font: font, color: color), text)

proc span*(font: FigFont, color: Fill, text: string): (FontStyle, string) =
  ## helper for making font span objects
  (FontStyle(font: font, color: color), text)

proc getId*(font: FigFont): FontId =
  FontId font.hash()

proc fontWithSize*(fontId: TypeFaceId, size: float32): FigFont =
  FigFont(typefaceId: fontId, size: size)

proc getContentHash*(
    size: Vec2,
    uiSpans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = false,
): Hash =
  var h = Hash(0)
  h = h !& hash(size)
  h = h !& hash(uiSpans)
  h = h !& hash(hAlign)
  h = h !& hash(vAlign)
  h = h !& hash(minContent)
  h = h !& hash(wrap)
  result = !$h

proc getContentHash*(
    size: Vec2,
    uiSpans: openArray[(FigFont, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = false,
): Hash =
  var styled = newSeqOfCap[(FontStyle, string)](uiSpans.len)
  for (font, text) in uiSpans:
    styled.add((fs(font), text))
  result = getContentHash(size, styled, hAlign, vAlign, minContent, wrap)
