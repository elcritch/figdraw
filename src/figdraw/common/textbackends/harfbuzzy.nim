import std/[algorithm, hashes, math, sequtils, strutils, tables, unicode]

import pkg/harfbuzzy as hb
import pkg/vmath

import ../fonttypes
import ../fontfallbacks
import ../shared
import ../typefaces
import ./common
import ./paragraphlayout
import ./state

when figdrawTextBackend == "hybrid" or runtimeTextBackends:
  import ../fontglyphs

const
  hbGlyphFlagUnsafeToBreak = 0x00000001'u32
  MaxFontFallbackPasses = 8

type
  DecodedSource = object
    runes: Utf8Runes
    directSource: bool
    displayByteStarts: seq[int]
    displayByteEnds: seq[int]
    sourceByteStarts: seq[int]
    sourceByteEnds: seq[int]
    sourceRuneStarts: seq[int]
    sourceRuneEnds: seq[int]

  ShapedSpan = object
    style: FontStyle
    text: string
    source: Utf8Runes
    byteStart: int
    byteEnd: int
    byteOffset: int

  Paragraph = object
    spans: seq[ShapedSpan]
    byteStart: int
    lineStyle: FontStyle
    hasLineStyle: bool

  ShapedGroup = object
    style: FontStyle
    spans: seq[ShapedSpan]

  HarfbuzzFontInfo = object
    typeface: hb.Typeface
    fontId: FontId
    glyphFont: GlyphFont

var harfbuzzTypefaceCache {.threadvar.}: Table[FontId, hb.Typeface]

func utf8RuneWidth(text: string, byteOffset: int): int {.inline.} =
  if byteOffset < 0 or byteOffset >= text.len:
    return 0
  min(max(runeLenAt(text, byteOffset), 1), text.len - byteOffset)

proc decodeSource(
    sourceSpans, displaySpans: openArray[(FontStyle, string)]
): DecodedSource =
  var sourceTextCapacity = 0
  for (_, text) in sourceSpans:
    sourceTextCapacity += text.len

  var
    sourceRunesText = newStringOfCap(sourceTextCapacity)
    sourceByteOffset = 0
    sourceRuneOffset = 0
    displayByteOffset = 0

  var direct = true
  for (style, text) in sourceSpans:
    # Each span must contain complete UTF-8 sequences so concatenating them
    # preserves the rune boundaries that the per-span mapping would produce.
    if style.font.fontCase != NormalCase or text.validateUtf8() >= 0:
      direct = false
      break
  if direct:
    for (_, text) in sourceSpans:
      sourceRunesText.add text
    return
      DecodedSource(runes: initArrangementRunes(sourceRunesText), directSource: true)

  for spanIndex in 0 ..< sourceSpans.len:
    let
      sourceText = sourceSpans[spanIndex][1]
      displayText = displaySpans[spanIndex][1]
      sourceRuneCount = sourceText.runeLen
      displayRuneCount = displayText.runeLen

    sourceRunesText.add sourceText

    var
      sourceByteIndex = 0
      sourceRuneIndex = 0
      displayByteIndex = 0
    for displayIndex in 0 ..< displayRuneCount:
      let displayByteLength = displayText.utf8RuneWidth(displayByteIndex)
      let
        mappedStart =
          if sourceRuneCount == 0:
            0
          else:
            min(
              displayIndex * sourceRuneCount div max(displayRuneCount, 1),
              sourceRuneCount - 1,
            )
        mappedEnd =
          if sourceRuneCount == 0:
            0
          else:
            max(
              mappedStart + 1,
              min(
                ((displayIndex + 1) * sourceRuneCount + displayRuneCount - 1) div
                  max(displayRuneCount, 1),
                sourceRuneCount,
              ),
            )

      while sourceRuneIndex < mappedStart:
        sourceByteIndex += sourceText.utf8RuneWidth(sourceByteIndex)
        inc sourceRuneIndex
      let sourceByteStart = sourceByteIndex
      while sourceRuneIndex < mappedEnd:
        sourceByteIndex += sourceText.utf8RuneWidth(sourceByteIndex)
        inc sourceRuneIndex
      let sourceByteEnd = sourceByteIndex

      result.displayByteStarts.add displayByteOffset + displayByteIndex
      result.displayByteEnds.add displayByteOffset + displayByteIndex + displayByteLength
      result.sourceRuneStarts.add sourceRuneOffset + mappedStart
      result.sourceRuneEnds.add sourceRuneOffset + mappedEnd
      if sourceRuneCount > 0:
        result.sourceByteStarts.add sourceByteOffset + sourceByteStart
        result.sourceByteEnds.add sourceByteOffset + sourceByteEnd
      else:
        result.sourceByteStarts.add sourceByteOffset
        result.sourceByteEnds.add sourceByteOffset

      displayByteIndex += displayByteLength

    sourceByteOffset += sourceText.len
    sourceRuneOffset += sourceRuneCount
    displayByteOffset += displayText.len

  result.runes = initArrangementRunes(sourceRunesText)

proc applyFontCase(text: string, fontCase: FontCase): string =
  case fontCase
  of NormalCase:
    text
  of UpperCase:
    text.toUpper()
  of LowerCase:
    text.toLower()
  of TitleCase:
    text.title()

proc splitParagraphs(spans: openArray[(FontStyle, string)]): seq[Paragraph] =
  result.add Paragraph(byteStart: 0)

  var byteOffset = 0
  for (style, text) in spans:
    if not result[^1].hasLineStyle:
      result[^1].lineStyle = style
      result[^1].hasLineStyle = true

    var
      partStart = 0
      byteIndex = 0
    while byteIndex < text.len:
      let ch = text[byteIndex]
      if ch == '\n' or ch == '\r':
        if byteIndex > partStart:
          result[^1].spans.add(
            ShapedSpan(
              style: style,
              text: text[partStart ..< byteIndex],
              byteOffset: byteOffset + partStart,
            )
          )

        var breakLen = 1
        if ch == '\r' and byteIndex + 1 < text.len and text[byteIndex + 1] == '\n':
          breakLen = 2
        byteIndex += breakLen
        partStart = byteIndex
        result.add Paragraph(
          byteStart: byteOffset + byteIndex, lineStyle: style, hasLineStyle: true
        )
      else:
        inc byteIndex

    if partStart < text.len:
      result[^1].spans.add(
        ShapedSpan(
          style: style,
          text: text[partStart ..< text.len],
          byteOffset: byteOffset + partStart,
        )
      )

    byteOffset += text.len

proc splitSourceParagraphs(
    source: Utf8Runes, runs: openArray[StyledTextRun], styles: openArray[FontStyle]
): seq[Paragraph] =
  result.add Paragraph(byteStart: 0)
  for run in runs:
    let
      style = styles[int(uint32(run.styleId))]
      runStart = int(run.byteStart)
      runEnd = int(run.byteEnd)
    if not result[^1].hasLineStyle:
      result[^1].lineStyle = style
      result[^1].hasLineStyle = true
    var
      partStart = runStart
      byteIndex = runStart
    while byteIndex < runEnd:
      let ch = source.bytes[byteIndex]
      if ch == '\n' or ch == '\r':
        if byteIndex > partStart:
          result[^1].spans.add ShapedSpan(
            style: style,
            source: source,
            byteStart: partStart,
            byteEnd: byteIndex,
            byteOffset: partStart,
          )
        var breakLen = 1
        if ch == '\r' and byteIndex + 1 < runEnd and source.bytes[byteIndex + 1] == '\n':
          breakLen = 2
        byteIndex += breakLen
        partStart = byteIndex
        result.add Paragraph(byteStart: byteIndex, lineStyle: style, hasLineStyle: true)
      else:
        inc byteIndex
    if partStart < runEnd:
      result[^1].spans.add ShapedSpan(
        style: style,
        source: source,
        byteStart: partStart,
        byteEnd: runEnd,
        byteOffset: partStart,
      )

func spanByteLength(span: ShapedSpan): int =
  if span.source.isNil:
    span.text.len
  else:
    span.byteEnd - span.byteStart

proc appendSpanText(output: var string, span: ShapedSpan) =
  if span.source.isNil:
    output.add span.text
  else:
    for byteIndex in span.byteStart ..< span.byteEnd:
      output.add span.source.bytes[byteIndex]

proc shapingGroups(paragraph: Paragraph): seq[ShapedGroup] =
  for span in paragraph.spans:
    if result.len > 0 and result[^1].style.font == span.style.font:
      result[^1].spans.add span
    else:
      result.add ShapedGroup(style: span.style, spans: @[span])

proc text(group: ShapedGroup): string =
  if group.spans.len == 1 and not group.spans[0].source.isNil:
    let span = group.spans[0]
    return span.source.bytes[span.byteStart ..< span.byteEnd]
  for span in group.spans:
    result.appendSpanText(span)

proc byteOffset(group: ShapedGroup): int =
  if group.spans.len > 0:
    result = group.spans[0].byteOffset

proc fillForByte(group: ShapedGroup, byteOffset: int): Fill =
  for span in group.spans:
    if byteOffset >= span.byteOffset and
        byteOffset < span.byteOffset + span.spanByteLength:
      return span.style.color
  result = group.style.color

func firstAbove(values: openArray[int], value: int): int {.inline.} =
  ## Index of the first sorted value greater than `value`; avoids the closure
  ## comparisons of `algorithm.upperBound` in per-glyph loops.
  var
    low = 0
    high = values.len
  while low < high:
    let middle = (low + high) shr 1
    if values[middle] <= value:
      low = middle + 1
    else:
      high = middle
  low

func firstAtLeast(values: openArray[int], value: int): int {.inline.} =
  var
    low = 0
    high = values.len
  while low < high:
    let middle = (low + high) shr 1
    if values[middle] < value:
      low = middle + 1
    else:
      high = middle
  low

type RuneCursor = object ## Last resolved rune start within one HarfBuzz-validated run.
  byteOffset: int
  runeIndex: int
  valid: bool

const RuneCursorMaxStep = 512

proc runeAtOrBefore(cursor: var RuneCursor, runes: Utf8Runes, byteOffset: int): int =
  if not cursor.valid or abs(byteOffset - cursor.byteOffset) > RuneCursorMaxStep:
    cursor.runeIndex = runes.runeIndexAtOrBeforeByte(byteOffset)
    cursor.byteOffset = runes.byteOffsetForRune(cursor.runeIndex)
    cursor.valid = true
  else:
    # Read the borrowed bytes in place; binding `lent` to a `let` copies them.
    while cursor.byteOffset > byteOffset:
      # The bytes within this shaped run are valid UTF-8. RTL clusters can
      # walk backward to the preceding leading byte without a fresh lookup.
      dec cursor.byteOffset
      while (ord(runes.bytes[cursor.byteOffset]) and 0xc0) == 0x80:
        dec cursor.byteOffset
      dec cursor.runeIndex
    while cursor.byteOffset < byteOffset:
      let next = cursor.byteOffset + max(runes.bytes.runeLenAt(cursor.byteOffset), 1)
      if next > byteOffset:
        break
      cursor.byteOffset = next
      inc cursor.runeIndex
  cursor.runeIndex

proc runeAtOrAfter(cursor: var RuneCursor, runes: Utf8Runes, byteOffset: int): int =
  result = cursor.runeAtOrBefore(runes, byteOffset)
  if cursor.byteOffset < byteOffset:
    inc result

proc runeRangeForBytes(
    decoded: DecodedSource, cursor: var RuneCursor, byteStart, byteEnd: int
): GlyphSourceRange =
  if decoded.directSource:
    result.byteStart = byteStart
    result.byteEnd = byteEnd
    if decoded.runes.len == decoded.runes.byteLength:
      result.runeStart = byteStart
      result.runeEnd = byteEnd
      return
    result.runeStart = cursor.runeAtOrBefore(decoded.runes, byteStart)
    result.runeEnd = cursor.runeAtOrAfter(decoded.runes, byteEnd)
    return
  result.byteStart = high(int)
  result.byteEnd = 0
  result.runeStart = decoded.runes.len
  result.runeEnd = 0

  # Display runes are ordered, so only the overlapping run needs scanning.
  var i = decoded.displayByteEnds.firstAbove(byteStart)
  while i < decoded.displayByteStarts.len and decoded.displayByteStarts[i] < byteEnd:
    result.byteStart = min(result.byteStart, decoded.sourceByteStarts[i])
    result.byteEnd = max(result.byteEnd, decoded.sourceByteEnds[i])
    result.runeStart = min(result.runeStart, decoded.sourceRuneStarts[i])
    result.runeEnd = max(result.runeEnd, decoded.sourceRuneEnds[i])
    inc i

  if result.byteStart == high(int):
    result.byteStart = 0
    result.runeStart = 0

proc sourceInsertionForDisplayByte(
    decoded: DecodedSource, byteOffset: int
): GlyphSourceRange =
  if decoded.directSource:
    result.byteStart = byteOffset
    result.byteEnd = byteOffset
    result.runeStart = decoded.runes.runeIndexAtOrBeforeByte(byteOffset)
    result.runeEnd = result.runeStart
    return
  let i = decoded.displayByteStarts.firstAtLeast(byteOffset)
  if i < decoded.displayByteStarts.len:
    result.byteStart = decoded.sourceByteStarts[i]
    result.byteEnd = result.byteStart
    result.runeStart = decoded.sourceRuneStarts[i]
    result.runeEnd = result.runeStart
    return

  if decoded.sourceByteEnds.len > 0:
    result.byteStart = decoded.sourceByteEnds[^1]
    result.byteEnd = result.byteStart
    result.runeStart = decoded.sourceRuneEnds[^1]
    result.runeEnd = result.runeStart

proc firstRune(decoded: DecodedSource, source: GlyphSourceRange): Rune =
  ## Decodes from source bytes; rune indexing would rescan from a checkpoint.
  if source.runeStart >= 0 and source.runeStart < source.runeEnd and
      source.byteStart >= 0 and source.byteStart < decoded.runes.byteLength:
    return decoded.runes.bytes.runeAt(source.byteStart)
  Rune(0)

proc sourceIsWhitespace(decoded: DecodedSource, source: GlyphSourceRange): bool =
  if source.runeStart >= source.runeEnd or source.byteStart < 0 or
      source.byteEnd > decoded.runes.byteLength:
    return false
  var offset = source.byteStart
  while offset < source.byteEnd:
    if not decoded.runes.bytes.runeAt(offset).isSpaceRune:
      return false
    offset += max(decoded.runes.bytes.runeLenAt(offset), 1)
  true

proc imageOffsetForGlyph(
    typeface: hb.Typeface, glyphId: hb.Codepoint, font: GlyphFont, scale: float32
): Vec2 =
  try:
    let extents = typeface.font.glyphExtents(glyphId)
    let
      x0 = extents.xBearing.float32 * scale
      x1 = x0 + extents.width.float32 * scale
      y0 = font.descentAdj - extents.yBearing.float32 * scale
      y1 = y0 - extents.height.float32 * scale
    result = vec2(floor(min(0.0'f32, min(x0, x1))), floor(min(0.0'f32, min(y0, y1))))
  except ValueError:
    result = vec2(0, 0)

proc toHarfbuzzFeatures(features: openArray[FontFeature]): seq[hb.Feature] =
  for feature in features:
    result.add hb.initFeature(
      hb.toTag(feature.tag), feature.value, feature.start, feature.ending
    )

proc toHarfbuzzVariations(variations: openArray[FontVariation]): seq[hb.Variation] =
  for variation in variations:
    result.add hb.initVariation(hb.toTag(variation.tag), variation.value)

proc initHarfbuzzTypeface(font: FigFont, fontId: FontId): hb.Typeface =
  if fontId in harfbuzzTypefaceCache:
    return harfbuzzTypefaceCache[fontId]

  let source = getTypefaceSource(font.typefaceId)
  let blob = hb.initBlob(source.data)
  let face = hb.initFace(blob, source.faceIndex)
  result = hb.initTypeface(face)
  result.font.setVariations(font.variations.toHarfbuzzVariations())
  harfbuzzTypefaceCache[fontId] = result

proc fallbackFont(font: FigFont, typefaceId: TypefaceId): FigFont =
  result = font
  result.typefaceId = typefaceId

proc initHarfbuzzFontInfos(font: FigFont): seq[HarfbuzzFontInfo] =
  var typefaceIds = @[font.typefaceId]
  for fallbackId in font.fallbackTypefaceIds:
    if fallbackId notin typefaceIds:
      typefaceIds.add fallbackId

  for typefaceId in typefaceIds:
    let
      figFont = font.fallbackFont(typefaceId)
      fontInfo = glyphFontFor(figFont)
    result.add HarfbuzzFontInfo(
      typeface: initHarfbuzzTypeface(figFont, fontInfo.id),
      fontId: fontInfo.id,
      glyphFont: fontInfo.glyph,
    )

proc codepointNeedsFallback(codepoint: uint32): bool =
  let rune = Rune(codepoint)
  not (
    rune.isWhiteSpace or codepoint in [0x200C'u32, 0x200D'u32] or
    codepoint in 0xFE00'u32 .. 0xFE0F'u32 or codepoint in 0xE0100'u32 .. 0xE01EF'u32 or
    cast[uint32](hb.scriptFor(codepoint)) == cast[uint32](hb.scriptInherited)
  )

proc existingTypefaceIds(font: FigFont): seq[TypefaceId] =
  result.add font.typefaceId
  for typefaceId in font.fallbackTypefaceIds:
    if typefaceId notin result:
      result.add typefaceId

proc missingFallbackRequests(
    fontInfos: openArray[HarfbuzzFontInfo], font: FigFont, text: string
): seq[FontFallbackRequest] =
  let existing = font.existingTypefaceIds()
  for rune in text.runes:
    let codepoint = rune.uint32
    if not codepoint.codepointNeedsFallback:
      continue

    var covered = false
    for info in fontInfos:
      if info.typeface.font.hasGlyph(codepoint):
        covered = true
        break
    if covered:
      continue

    let script = $hb.scriptFor(codepoint)
    var requestIndex = -1
    for index, request in result:
      if request.script == script:
        requestIndex = index
        break
    if requestIndex < 0:
      result.add FontFallbackRequest(
        primaryTypefaceId: font.typefaceId,
        existingTypefaceIds: existing,
        language: font.language,
        script: script,
      )
      requestIndex = result.len - 1
    if codepoint notin result[requestIndex].codepoints:
      result[requestIndex].codepoints.add codepoint

proc resolveFallbacks(font: FigFont, text: string): FigFont =
  result = font
  let resolver = fontFallbackResolver()
  if resolver == nil or text.len == 0:
    return

  for _ in 0 ..< MaxFontFallbackPasses:
    let
      fontInfos = initHarfbuzzFontInfos(result)
      requests = fontInfos.missingFallbackRequests(result, text)
    if requests.len == 0:
      return

    var addedTypeface = false
    for fallbackRequest in requests:
      var request = fallbackRequest
      request.existingTypefaceIds = result.existingTypefaceIds()
      try:
        for typefaceId in resolver(request):
          if typefaceId != result.typefaceId and
              typefaceId notin result.fallbackTypefaceIds:
            result.fallbackTypefaceIds.add typefaceId
            addedTypeface = true
      except CatchableError:
        discard
    if not addedTypeface:
      return

proc shapeParagraph(
    fontInfos: openArray[HarfbuzzFontInfo], font: FigFont, text: string
): hb.ShapedParagraph =
  var typefaces = newSeqOfCap[hb.Typeface](fontInfos.len)
  for info in fontInfos:
    typefaces.add info.typeface

  var features = font.features
  if font.noKerningAdjustments:
    var hasKerningFeature = false
    for feature in features:
      if feature.tag.toLowerAscii() == "kern":
        hasKerningFeature = true
        break
    if not hasKerningFeature:
      features.add fontFeature("kern", 0)

  let context = hb.initShapeContext(
    typefaces,
    hb.ParagraphOptions(
      language:
        if font.language.len > 0:
          hb.toLanguage(font.language)
        else:
          hb.languageInvalid,
      features: features.toHarfbuzzFeatures(),
      flags: {hb.beginningOfText, hb.endOfText},
    ),
  )
  context.shapeParagraph(text)

proc pxScale(typeface: hb.Typeface, font: FigFont): float32 =
  let upem = typeface.face.upem
  if upem <= 0:
    return 1.0'f32
  font.size / upem.float32

func placedRuneSkipsRaster(rune: Rune): bool =
  let codepoint = rune.uint32
  rune.isWhiteSpace or codepoint in [0x200C'u32, 0x200D'u32] or
    codepoint in 0xFE00'u32 .. 0xFE0F'u32 or codepoint in 0xE0100'u32 .. 0xE01EF'u32

proc resolvePlacedGlyph*(
    font: FigFont, rune: Rune
): tuple[
  glyphFont: GlyphFont,
  glyphId: FontGlyphId,
  advance: float32,
  imageOffset: Vec2,
  skipsRaster: bool,
] =
  ## Resolves a source rune for explicit placement without applying text layout.
  let
    resolvedFont = font.resolveFallbacks($rune)
    fontInfos = initHarfbuzzFontInfos(resolvedFont)
  if fontInfos.len == 0:
    raise newException(ValueError, "explicit glyph placement requires a typeface")

  var selectedIndex = 0
  if not rune.placedRuneSkipsRaster:
    for index, info in fontInfos:
      if info.typeface.font.hasGlyph(rune.uint32):
        selectedIndex = index
        break

  let selected = fontInfos[selectedIndex]
  result.glyphFont = selected.glyphFont
  result.skipsRaster = rune.placedRuneSkipsRaster
  if result.skipsRaster and not rune.isWhiteSpace:
    return

  var glyphId: hb.Codepoint
  try:
    glyphId = selected.typeface.font.nominalGlyph(rune.uint32)
  except ValueError:
    discard
  result.glyphId = FontGlyphId(glyphId.uint32)
  if glyphId != 0 or not result.skipsRaster:
    let scale = selected.typeface.pxScale(resolvedFont)
    result.advance = selected.typeface.font.horizontalAdvance(glyphId).float32 * scale
    result.imageOffset =
      imageOffsetForGlyph(selected.typeface, glyphId, selected.glyphFont, scale)

proc harfbuzzHyphenResolver(): HyphenResolver =
  ## Visible hyphens in the font of the glyph that precedes a break.
  result = proc(fontId: FontId): HyphenGlyph =
    var font: FigFont
    if not tryGetFigFont(fontId, font):
      return
    try:
      let placed = resolvePlacedGlyph(font, Rune('-'))
      if placed.glyphId != FontGlyphId(0):
        result = HyphenGlyph(
          found: true,
          glyphFont: placed.glyphFont,
          glyphId: placed.glyphId,
          advance: placed.advance,
          imageOffset: placed.imageOffset,
        )
    except CatchableError:
      discard # No visible hyphen: soft hyphens become plain breaks.

proc clusterStarts(run: hb.ShapedRun): seq[int] =
  ## Sorted distinct cluster starts, computed once per run.
  result = newSeqOfCap[int](run.glyphRun.glyphs.len)
  for glyph in run.glyphRun.glyphs:
    result.add int(glyph.cluster)
  result.sort()
  var unique = 0
  for index in 0 ..< result.len:
    if unique == 0 or result[index] != result[unique - 1]:
      result[unique] = result[index]
      inc unique
  result.setLen(unique)

proc nextClusterBoundary(
    run: hb.ShapedRun, clusters: openArray[int], cluster: int
): int =
  let index = clusters.firstAbove(cluster)
  if index < clusters.len:
    clusters[index]
  else:
    run.textRun.byteEnd

proc addGlyphSpan(
    arrangement: var GlyphArrangement, glyphFont: GlyphFont, color: Fill
) =
  let glyphIndex = arrangement.arrangedGlyphs.len
  if arrangement.spans.len > 0 and arrangement.spans[^1].b == glyphIndex - 1 and
      arrangement.fonts[^1] == glyphFont and arrangement.spanColors[^1] == color:
    arrangement.spans[^1].b = glyphIndex
  else:
    arrangement.spans.add glyphIndex .. glyphIndex
    arrangement.fonts.add glyphFont
    arrangement.spanColors.add color

proc appendEmptyLineGlyph(
    arrangement: var GlyphArrangement,
    decoded: DecodedSource,
    displayByteOffset: int,
    glyphFont: GlyphFont,
    color: Fill,
    safeBreakAfter: var seq[bool],
    glyphText: var string,
) =
  let source = decoded.sourceInsertionForDisplayByte(displayByteOffset)
  arrangement.addGlyphSpan(glyphFont, color)
  arrangement.arrangedGlyphs.add ArrangedGlyph(
    rasterBackend: currentGlyphRaster(),
    fontId: glyphFont.fontId,
    source: source,
    rune: Rune(0),
    isWhitespace: true,
    pos: vec2(0, glyphFont.descentAdj),
    rect: rect(0, 0, 0, glyphFont.lineHeight),
  )
  glyphText.add Rune(0)
  arrangement.positions.add vec2(0, glyphFont.descentAdj)
  arrangement.selectionRects.add rect(0, 0, 0, glyphFont.lineHeight)
  safeBreakAfter.add true

proc appendShapedGroup(
    arrangement: var GlyphArrangement,
    decoded: DecodedSource,
    group: ShapedGroup,
    groupText: string,
    pen: var Vec2,
    safeBreakAfter: var seq[bool],
    glyphText: var string,
    rightToLeft: var bool,
    directionKnown: var bool,
) =
  let
    groupByteOffset = group.byteOffset()
    fontInfos = initHarfbuzzFontInfos(group.style.font)
    paragraph = fontInfos.shapeParagraph(group.style.font, groupText)
  if not directionKnown and paragraph.visualRuns.len > 0:
    rightToLeft = paragraph.baseDirection == hb.Direction.rtl
    directionKnown = true

  for run in paragraph.visualRuns:
    if run.glyphRun.glyphs.len == 0:
      continue

    let
      fontIndex =
        if run.typefaceIndex >= 0 and run.typefaceIndex < fontInfos.len:
          run.typefaceIndex
        else:
          0
      fontInfo = fontInfos[fontIndex]
      scale = fontInfo.typeface.pxScale(group.style.font)
      clusters = run.clusterStarts()
    var cursor: RuneCursor

    for runGlyphIndex, glyph in run.glyphRun.glyphs:
      let
        cluster = int(glyph.cluster)
        nextCluster = run.nextClusterBoundary(clusters, cluster)
        source = decoded.runeRangeForBytes(
          cursor, groupByteOffset + cluster, groupByteOffset + nextCluster
        )
        rune = decoded.firstRune(source)
        color = group.fillForByte(groupByteOffset + cluster)
        advance = vec2(glyph.xAdvance.float32 * scale, -glyph.yAdvance.float32 * scale)
        offset = vec2(glyph.xOffset.float32 * scale, -glyph.yOffset.float32 * scale)
        pos = pen + offset
        drawPos = vec2(pos.x, pos.y - fontInfo.glyphFont.descentAdj)
        selectionWidth = max(abs(advance.x), 0.0'f32)
        selection =
          rect(drawPos.x, drawPos.y, selectionWidth, fontInfo.glyphFont.lineHeight)
        imageOffset = fontInfo.typeface.imageOffsetForGlyph(
          glyph.codepoint, fontInfo.glyphFont, scale
        )

      arrangement.addGlyphSpan(fontInfo.glyphFont, color)
      arrangement.arrangedGlyphs.add ArrangedGlyph(
        rasterBackend: currentGlyphRaster(),
        fontId: fontInfo.fontId,
        glyphId: FontGlyphId(glyph.codepoint.uint32),
        cluster: glyph.cluster,
        source: source,
        rune: rune,
        isWhitespace: decoded.sourceIsWhitespace(source),
        pos: pos,
        advance: advance,
        offset: offset,
        imageOffset: imageOffset,
        rect: selection,
      )
      glyphText.add rune
      arrangement.positions.add pos
      arrangement.selectionRects.add selection
      let nextGlyphUnsafeToBreak =
        runGlyphIndex + 1 < run.glyphRun.glyphs.len and
        (run.glyphRun.glyphs[runGlyphIndex + 1].flags and hbGlyphFlagUnsafeToBreak) != 0
      safeBreakAfter.add not nextGlyphUnsafeToBreak

      pen += advance

proc typesetPrepared(
    box: Rect,
    decoded: DecodedSource,
    paragraphs: seq[Paragraph],
    fontSizes: openArray[float],
    contentHash: Hash,
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent, wrap, rasterize: bool,
): GlyphArrangement =
  threadEffects:
    AppMainThread
  result = GlyphArrangement(contentHash: contentHash, sourceRunes: decoded.runes)
  var
    pen = vec2(0, 0)
    glyphText = newStringOfCap(decoded.runes.len)
  var safeBreakAfter: seq[bool]
  var resolvedFonts: seq[FigFont]
  var layoutParagraphs = newSeqOfCap[LayoutParagraph](paragraphs.len)
  for paragraph in paragraphs:
    let glyphStart = result.arrangedGlyphs.len
    var
      rightToLeft = false
      directionKnown = false
    pen.x = 0
    for sourceGroup in paragraph.shapingGroups():
      var group = sourceGroup
      if group.spans.len > 0:
        let groupText = group.text()
        group.style.font = group.style.font.resolveFallbacks(groupText)
        resolvedFonts.add group.style.font
        let groupGlyphFont = glyphFontFor(group.style.font).glyph
        let baseline = groupGlyphFont.descentAdj
        if result.arrangedGlyphs.len == 0:
          pen.y = baseline
        result.appendShapedGroup(
          decoded, group, groupText, pen, safeBreakAfter, glyphText, rightToLeft,
          directionKnown,
        )

    if result.arrangedGlyphs.len == glyphStart and paragraphs.len > 1 and
        paragraph.hasLineStyle:
      let emptyLineFont = glyphFontFor(paragraph.lineStyle.font).glyph
      result.appendEmptyLineGlyph(
        decoded, paragraph.byteStart, emptyLineFont, paragraph.lineStyle.color,
        safeBreakAfter, glyphText,
      )

    let
      glyphStop = result.arrangedGlyphs.len - 1
      paragraphStyle =
        if paragraph.spans.len > 0:
          paragraph.spans[0].style
        else:
          paragraph.lineStyle
    layoutParagraphs.add LayoutParagraph(
      glyphs: glyphStart .. glyphStop,
      style: paragraphStyle.paragraph,
      language: paragraphStyle.font.language,
      rightToLeft: rightToLeft,
    )

  result.runes = initArrangementRunes(glyphText)
  let styled = layoutParagraphs.hasLayoutStyle()
  let lines = result.breakParagraphLines(
    layoutParagraphs, safeBreakAfter, box.w, wrap, harfbuzzHyphenResolver()
  )
  if wrap or paragraphs.len > 1 or result.arrangedGlyphs.len == 0 or styled:
    result.reflowParagraphLines(lines, layoutParagraphs, box.w, wrap)

  var alignmentBox = box
  if minContent:
    let content = result.calcMinMaxContent()
    alignmentBox.h = max(alignmentBox.h, content.bounding.h)

  result.alignParagraphLines(lines, layoutParagraphs, alignmentBox, hAlign, vAlign)

  let content = result.calcMinMaxContent()
  result.minSize = content.minSize
  result.maxSize = content.maxSize
  result.bounding = content.bounding
  if minContent:
    result.minSize.y = max(result.minSize.y, result.bounding.h)
  result.addFontSizePadding(fontSizes)
  result.contentHash = hash((result.contentHash, resolvedFonts))

  when figdrawTextBackend == "hybrid" or runtimeTextBackends:
    if rasterize and selectedTextBackend() == TextBackendKind.Hybrid:
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
  ## Typesets with Harfbuzzy and converts shaped glyph ids into FigDraw data.
  threadEffects:
    AppMainThread

  var shapedSpans = newSeqOfCap[(FontStyle, string)](uiSpans.len)
  for (style, text) in uiSpans:
    shapedSpans.add((style, text.applyFontCase(style.font.fontCase)))
  let
    decoded = decodeSource(uiSpans, shapedSpans)
    paragraphs = splitParagraphs(shapedSpans)
    fontSizes = shapedSpans.mapIt(it[0].font.size.float)
    contentHash = block:
      var h = Hash(0)
      h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign, minContent, wrap)
      h = h !& hash(figUiScale())
      !$h
  typesetPrepared(
    box, decoded, paragraphs, fontSizes, contentHash, hAlign, vAlign, minContent, wrap,
    rasterize,
  )

proc typesetSourceSpans*(
    box: Rect,
    source: Utf8Runes,
    runs: openArray[StyledTextRun],
    styles: openArray[FontStyle],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent, wrap, rasterize: bool,
): GlyphArrangement =
  ## Shapes normal-case text directly from shared source ranges.
  threadEffects:
    AppMainThread

  for candidate in runs:
    if styles[int(uint32(candidate.styleId))].font.fontCase != NormalCase:
      var owned = newSeqOfCap[(FontStyle, string)](runs.len)
      for run in runs:
        owned.add(
          (
            styles[int(uint32(run.styleId))],
            source.bytes[int(run.byteStart) ..< int(run.byteEnd)],
          )
        )
      result = typeset(box, owned, hAlign, vAlign, minContent, wrap, rasterize)
      result.sourceRunes = source
      return

  let
    decoded = DecodedSource(runes: source, directSource: true)
    paragraphs = splitSourceParagraphs(source, runs, styles)
    fontSizes = runs.mapIt(styles[int(uint32(it.styleId))].font.size.float)
    contentHash = block:
      var h = Hash(0)
      h = h !& hash(box.wh)
      h = h !& hash(source.bytes)
      h = h !& hash(runs)
      h = h !& hash(styles)
      h = h !& hash(selectedTextBackend())
      h = h !& hash(hAlign)
      h = h !& hash(vAlign)
      h = h !& hash(minContent)
      h = h !& hash(wrap)
      h = h !& hash(figUiScale())
      !$h
  typesetPrepared(
    box, decoded, paragraphs, fontSizes, contentHash, hAlign, vAlign, minContent, wrap,
    rasterize,
  )
