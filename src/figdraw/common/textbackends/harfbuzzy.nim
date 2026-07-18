import std/[algorithm, hashes, math, sequtils, strutils, tables, unicode]

import pkg/harfbuzzy as hb
import pkg/vmath

import ../fonttypes
import ../shared
import ../typefaces
import ./common

when figdrawTextBackend == "hybrid":
  import ../fontglyphs

const hbGlyphFlagUnsafeToBreak = 0x00000001'u32

type
  DecodedSource = object
    runes: seq[Rune]
    displayByteStarts: seq[int]
    displayByteEnds: seq[int]
    sourceByteStarts: seq[int]
    sourceByteEnds: seq[int]
    sourceRuneStarts: seq[int]
    sourceRuneEnds: seq[int]

  ShapedSpan = object
    style: FontStyle
    text: string
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

proc decodeText(
    text: string
): tuple[runes: seq[Rune], byteStarts: seq[int], byteEnds: seq[int]] =
  var byteOffset = 0
  for rune in text.runes:
    result.runes.add rune
    result.byteStarts.add byteOffset
    byteOffset += ($rune).len
    result.byteEnds.add byteOffset

proc decodeSource(
    sourceSpans, displaySpans: openArray[(FontStyle, string)]
): DecodedSource =
  var
    sourceByteOffset = 0
    sourceRuneOffset = 0
    displayByteOffset = 0

  for spanIndex in 0 ..< sourceSpans.len:
    let
      sourceText = sourceSpans[spanIndex][1]
      displayText = displaySpans[spanIndex][1]
      source = decodeText(sourceText)
      display = decodeText(displayText)

    result.runes.add source.runes
    for displayIndex in 0 ..< display.runes.len:
      let
        mappedStart =
          if source.runes.len == 0:
            0
          else:
            min(
              displayIndex * source.runes.len div max(display.runes.len, 1),
              source.runes.len - 1,
            )
        mappedEnd =
          if source.runes.len == 0:
            0
          else:
            max(
              mappedStart + 1,
              min(
                ((displayIndex + 1) * source.runes.len + display.runes.len - 1) div
                  max(display.runes.len, 1),
                source.runes.len,
              ),
            )

      result.displayByteStarts.add displayByteOffset + display.byteStarts[displayIndex]
      result.displayByteEnds.add displayByteOffset + display.byteEnds[displayIndex]
      result.sourceRuneStarts.add sourceRuneOffset + mappedStart
      result.sourceRuneEnds.add sourceRuneOffset + mappedEnd
      if source.runes.len > 0:
        result.sourceByteStarts.add sourceByteOffset + source.byteStarts[mappedStart]
        result.sourceByteEnds.add sourceByteOffset + source.byteEnds[mappedEnd - 1]
      else:
        result.sourceByteStarts.add sourceByteOffset
        result.sourceByteEnds.add sourceByteOffset

    sourceByteOffset += sourceText.len
    sourceRuneOffset += source.runes.len
    displayByteOffset += displayText.len

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

proc shapingGroups(paragraph: Paragraph): seq[ShapedGroup] =
  for span in paragraph.spans:
    if result.len > 0 and result[^1].style.font == span.style.font:
      result[^1].spans.add span
    else:
      result.add ShapedGroup(style: span.style, spans: @[span])

proc text(group: ShapedGroup): string =
  for span in group.spans:
    result.add span.text

proc byteOffset(group: ShapedGroup): int =
  if group.spans.len > 0:
    result = group.spans[0].byteOffset

proc fillForByte(group: ShapedGroup, byteOffset: int): Fill =
  for span in group.spans:
    if byteOffset >= span.byteOffset and byteOffset < span.byteOffset + span.text.len:
      return span.style.color
  result = group.style.color

proc runeRangeForBytes(
    decoded: DecodedSource, byteStart, byteEnd: int
): GlyphSourceRange =
  result.byteStart = high(int)
  result.byteEnd = 0
  result.runeStart = decoded.runes.len
  result.runeEnd = 0

  for i in 0 ..< decoded.displayByteStarts.len:
    if decoded.displayByteEnds[i] > byteStart and decoded.displayByteStarts[i] < byteEnd:
      result.byteStart = min(result.byteStart, decoded.sourceByteStarts[i])
      result.byteEnd = max(result.byteEnd, decoded.sourceByteEnds[i])
      result.runeStart = min(result.runeStart, decoded.sourceRuneStarts[i])
      result.runeEnd = max(result.runeEnd, decoded.sourceRuneEnds[i])

  if result.byteStart == high(int):
    result.byteStart = 0
    result.runeStart = 0

proc sourceInsertionForDisplayByte(
    decoded: DecodedSource, byteOffset: int
): GlyphSourceRange =
  for i in 0 ..< decoded.displayByteStarts.len:
    if decoded.displayByteStarts[i] >= byteOffset:
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
  if source.runeStart >= 0 and source.runeStart < source.runeEnd and
      source.runeStart < decoded.runes.len:
    return decoded.runes[source.runeStart]
  Rune(0)

proc sourceIsWhitespace(decoded: DecodedSource, source: GlyphSourceRange): bool =
  if source.runeStart >= source.runeEnd:
    return false
  for i in source.runeStart ..< source.runeEnd:
    if i >= decoded.runes.len or not decoded.runes[i].isWhiteSpace:
      return false
  true

func isCjkLineBreakRune(rune: Rune): bool =
  let cp = rune.uint32
  cp in 0x1100'u32 .. 0x11ff'u32 or cp in 0x2e80'u32 .. 0x30ff'u32 or
    cp in 0x3400'u32 .. 0x4dbf'u32 or cp in 0x4e00'u32 .. 0x9fff'u32 or
    cp in 0xac00'u32 .. 0xd7af'u32 or cp in 0xf900'u32 .. 0xfaff'u32 or
    cp in 0xff65'u32 .. 0xff9f'u32

func canBreakAfterRune(rune: Rune): bool =
  if rune.isWhiteSpace:
    return true

  case rune.uint32
  of 0x002d'u32, 0x002f'u32, 0x00ad'u32, 0x058a'u32, 0x05be'u32, 0x1400'u32, 0x1806'u32,
      0x200b'u32, 0x2053'u32, 0x207b'u32, 0x208b'u32, 0x2212'u32, 0x2e17'u32,
      0x2e1a'u32, 0x301c'u32, 0x3030'u32, 0x30a0'u32, 0xfe58'u32, 0xfe63'u32, 0xff0d'u32:
    true
  of 0x2010'u32 .. 0x2015'u32, 0xfe31'u32 .. 0xfe32'u32:
    true
  else:
    false

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
  let fontInfos = initHarfbuzzFontInfos(font)
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
    let scale = selected.typeface.pxScale(font)
    result.advance = selected.typeface.font.horizontalAdvance(glyphId).float32 * scale
    result.imageOffset =
      imageOffsetForGlyph(selected.typeface, glyphId, selected.glyphFont, scale)

proc nextClusterBoundary(run: hb.ShapedRun, cluster: int): int =
  var boundaries = @[run.textRun.byteEnd]
  for glyph in run.glyphRun.glyphs:
    let glyphCluster = int(glyph.cluster)
    if glyphCluster > cluster:
      boundaries.add glyphCluster
  boundaries.sort()
  result = boundaries[0]

proc shiftGlyph(arrangement: var GlyphArrangement, glyphIndex: int, delta: Vec2) =
  arrangement.arrangedGlyphs[glyphIndex].pos += delta
  arrangement.arrangedGlyphs[glyphIndex].rect =
    arrangement.arrangedGlyphs[glyphIndex].rect + rect(delta.x, delta.y, 0, 0)
  arrangement.positions[glyphIndex] += delta
  arrangement.selectionRects[glyphIndex] =
    arrangement.selectionRects[glyphIndex] + rect(delta.x, delta.y, 0, 0)

proc lineBounds(arrangement: GlyphArrangement, line: Slice[int]): Rect =
  result = rect(float32.high, float32.high, 0, 0)
  if line.a > line.b:
    return rect(0, 0, 0, 0)
  for glyphIndex in line:
    let glyphRect = arrangement.arrangedGlyphs[glyphIndex].rect
    result.x = min(result.x, glyphRect.x)
    result.y = min(result.y, glyphRect.y)
    result.w = max(result.w, glyphRect.x + glyphRect.w)
    result.h = max(result.h, glyphRect.y + glyphRect.h)
  result.w -= result.x
  result.h -= result.y

proc applyAlignment(
    arrangement: var GlyphArrangement,
    box: Rect,
    hAlign: FontHorizontal,
    vAlign: FontVertical,
) =
  if arrangement.arrangedGlyphs.len == 0:
    return

  let lines =
    if arrangement.lines.len > 0:
      arrangement.lines
    else:
      @[0 .. arrangement.arrangedGlyphs.len - 1]

  for line in lines:
    let bounds = arrangement.lineBounds(line)
    var dx = -bounds.x
    case hAlign
    of Left:
      discard
    of Center:
      dx += (box.w - bounds.w) / 2
    of Right:
      dx += box.w - bounds.w
    if dx != 0:
      for glyphIndex in line:
        arrangement.shiftGlyph(glyphIndex, vec2(dx, 0))

  let bounds = arrangement.calcMinMaxContent().bounding
  var dy = -bounds.y
  case vAlign
  of Top:
    discard
  of Middle:
    dy += (box.h - bounds.h) / 2
  of Bottom:
    dy += box.h - bounds.h

  if dy != 0:
    for glyphIndex in 0 ..< arrangement.arrangedGlyphs.len:
      arrangement.shiftGlyph(glyphIndex, vec2(0, dy))

proc lineHeight(arrangement: GlyphArrangement, line: Slice[int]): float32 =
  for glyphIndex in line:
    result = max(result, arrangement.arrangedGlyphs[glyphIndex].rect.h)
  if result <= 0:
    for font in arrangement.fonts:
      result = max(result, font.lineHeight)

proc glyphWrapWidth(glyph: ArrangedGlyph): float32 {.inline.} =
  max(glyph.rect.w, abs(glyph.advance.x))

proc preferredLineBreakAfter(arrangement: GlyphArrangement, glyphIndex: int): bool =
  let glyph = arrangement.arrangedGlyphs[glyphIndex]
  if glyph.isWhitespace:
    return true
  if glyph.source.runeEnd <= glyph.source.runeStart or
      glyph.source.runeEnd > arrangement.sourceRunes.len:
    return false

  let lastRune = arrangement.sourceRunes[glyph.source.runeEnd - 1]
  if lastRune.canBreakAfterRune:
    return true

  if glyphIndex + 1 < arrangement.arrangedGlyphs.len:
    let nextGlyph = arrangement.arrangedGlyphs[glyphIndex + 1]
    if glyph.source.runeEnd == nextGlyph.source.runeStart and
        nextGlyph.source.runeStart < arrangement.sourceRunes.len:
      let nextRune = arrangement.sourceRunes[nextGlyph.source.runeStart]
      return lastRune.isCjkLineBreakRune and nextRune.isCjkLineBreakRune

  false

proc buildWrappedLines(
    arrangement: GlyphArrangement,
    boxWidth: float32,
    safeBreakAfter: openArray[bool],
    glyphRange: Slice[int],
): seq[Slice[int]] =
  if arrangement.arrangedGlyphs.len == 0 or glyphRange.a > glyphRange.b:
    return
  if boxWidth <= 0:
    return @[glyphRange]

  var
    lineStart = glyphRange.a
    lineWidth = 0.0'f32
    lastBreak = -1
    lastSafeBreak = -1
    glyphIndex = glyphRange.a

  while glyphIndex <= glyphRange.b:
    let glyph = arrangement.arrangedGlyphs[glyphIndex]
    let width = glyph.glyphWrapWidth()
    var startNextLine = false
    if glyphIndex > lineStart and lineWidth + width > boxWidth:
      let breakIndex =
        if lastBreak >= lineStart and lastBreak < glyphIndex:
          lastBreak
        elif lastSafeBreak >= lineStart and lastSafeBreak < glyphIndex:
          lastSafeBreak
        else:
          -1
      if breakIndex >= lineStart:
        result.add lineStart .. breakIndex
        lineStart = breakIndex + 1
        lineWidth = 0
        lastBreak = -1
        lastSafeBreak = -1
        glyphIndex = lineStart
        startNextLine = true

    if not startNextLine:
      lineWidth += width
      let
        breakAfter = glyphIndex >= safeBreakAfter.len or safeBreakAfter[glyphIndex]
        preferredBreakAfter = arrangement.preferredLineBreakAfter(glyphIndex)
        clusterBoundary =
          glyphIndex == glyphRange.b or
          arrangement.arrangedGlyphs[glyphIndex].source !=
          arrangement.arrangedGlyphs[glyphIndex + 1].source
      if breakAfter and clusterBoundary:
        lastSafeBreak = glyphIndex
      if preferredBreakAfter and breakAfter:
        lastBreak = glyphIndex
      inc glyphIndex

  if lineStart <= glyphRange.b:
    result.add lineStart .. glyphRange.b

func lineSourceStart(arrangement: GlyphArrangement, line: Slice[int]): int =
  result = high(int)
  for glyphIndex in line:
    let source = arrangement.arrangedGlyphs[glyphIndex].source
    if source.runeStart < source.runeEnd:
      result = min(result, source.runeStart)
  if result == high(int):
    result = 0

func linesNeedLogicalReverse(
    arrangement: GlyphArrangement, lines: openArray[Slice[int]]
): bool =
  if lines.len < 2:
    return false

  var previous = arrangement.lineSourceStart(lines[0])
  for i in 1 ..< lines.len:
    let current = arrangement.lineSourceStart(lines[i])
    if current < previous:
      return true
    if current > previous:
      return false
    previous = current

proc addParagraphLines(
    arrangement: var GlyphArrangement,
    glyphRange: Slice[int],
    boxWidth: float32,
    safeBreakAfter: openArray[bool],
    wrap: bool,
) =
  if glyphRange.a > glyphRange.b:
    return

  var lines =
    if wrap:
      arrangement.buildWrappedLines(boxWidth, safeBreakAfter, glyphRange)
    else:
      @[glyphRange]

  if arrangement.linesNeedLogicalReverse(lines):
    lines.reverse()
  for line in lines:
    arrangement.lines.add(line)

proc reflowLines(arrangement: var GlyphArrangement) =
  var lineTop = 0.0'f32
  for line in arrangement.lines:
    var lineX = 0.0'f32
    let lineHeight = arrangement.lineHeight(line)
    for glyphIndex in line:
      let
        oldGlyph = arrangement.arrangedGlyphs[glyphIndex]
        posOffset = oldGlyph.pos - oldGlyph.rect.xy
        newRect = rect(lineX, lineTop, oldGlyph.rect.w, oldGlyph.rect.h)
        newPos = newRect.xy + posOffset

      arrangement.arrangedGlyphs[glyphIndex].rect = newRect
      arrangement.arrangedGlyphs[glyphIndex].pos = newPos
      arrangement.positions[glyphIndex] = newPos
      arrangement.selectionRects[glyphIndex] = newRect
      lineX += oldGlyph.glyphWrapWidth()
    lineTop += lineHeight

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
) =
  let source = decoded.sourceInsertionForDisplayByte(displayByteOffset)
  arrangement.addGlyphSpan(glyphFont, color)
  arrangement.arrangedGlyphs.add ArrangedGlyph(
    fontId: glyphFont.fontId,
    source: source,
    rune: Rune(0),
    isWhitespace: true,
    pos: vec2(0, glyphFont.descentAdj),
    rect: rect(0, 0, 0, glyphFont.lineHeight),
  )
  arrangement.runes.add Rune(0)
  arrangement.positions.add vec2(0, glyphFont.descentAdj)
  arrangement.selectionRects.add rect(0, 0, 0, glyphFont.lineHeight)
  safeBreakAfter.add true

proc appendShapedGroup(
    arrangement: var GlyphArrangement,
    decoded: DecodedSource,
    group: ShapedGroup,
    pen: var Vec2,
    safeBreakAfter: var seq[bool],
) =
  let
    groupText = group.text()
    groupByteOffset = group.byteOffset()
    fontInfos = initHarfbuzzFontInfos(group.style.font)
    paragraph = fontInfos.shapeParagraph(group.style.font, groupText)

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

    for runGlyphIndex, glyph in run.glyphRun.glyphs:
      let
        cluster = int(glyph.cluster)
        nextCluster = run.nextClusterBoundary(cluster)
        source = decoded.runeRangeForBytes(
          groupByteOffset + cluster, groupByteOffset + nextCluster
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
      arrangement.runes.add rune
      arrangement.positions.add pos
      arrangement.selectionRects.add selection
      let nextGlyphUnsafeToBreak =
        runGlyphIndex + 1 < run.glyphRun.glyphs.len and
        (run.glyphRun.glyphs[runGlyphIndex + 1].flags and hbGlyphFlagUnsafeToBreak) != 0
      safeBreakAfter.add not nextGlyphUnsafeToBreak

      pen += advance

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

  let decoded = decodeSource(uiSpans, shapedSpans)
  let fontSizes = shapedSpans.mapIt(it[0].font.size.float)

  result = GlyphArrangement(
    contentHash: block:
      var h = Hash(0)
      h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign, minContent, wrap)
      h = h !& hash(figUiScale())
      !$h,
    sourceRunes: decoded.runes,
  )

  let paragraphs = splitParagraphs(shapedSpans)
  var pen = vec2(0, 0)
  var safeBreakAfter: seq[bool]
  for paragraph in paragraphs:
    let glyphStart = result.arrangedGlyphs.len
    pen.x = 0
    for group in paragraph.shapingGroups():
      if group.spans.len > 0:
        let groupGlyphFont = glyphFontFor(group.style.font).glyph
        let baseline = groupGlyphFont.descentAdj
        if result.arrangedGlyphs.len == 0:
          pen.y = baseline
        result.appendShapedGroup(decoded, group, pen, safeBreakAfter)

    if result.arrangedGlyphs.len == glyphStart and paragraphs.len > 1 and
        paragraph.hasLineStyle:
      let emptyLineFont = glyphFontFor(paragraph.lineStyle.font).glyph
      result.appendEmptyLineGlyph(
        decoded, paragraph.byteStart, emptyLineFont, paragraph.lineStyle.color,
        safeBreakAfter,
      )

    let glyphStop = result.arrangedGlyphs.len - 1
    result.addParagraphLines(glyphStart .. glyphStop, box.w, safeBreakAfter, wrap)

  if wrap or paragraphs.len > 1 or result.arrangedGlyphs.len == 0:
    result.reflowLines()

  var alignmentBox = box
  if minContent:
    let content = result.calcMinMaxContent()
    alignmentBox.h = max(alignmentBox.h, content.bounding.h)

  result.applyAlignment(alignmentBox, hAlign, vAlign)

  let content = result.calcMinMaxContent()
  result.minSize = content.minSize
  result.maxSize = content.maxSize
  result.bounding = content.bounding
  if minContent:
    result.minSize.y = max(result.minSize.y, result.bounding.h)
  result.addFontSizePadding(fontSizes)

  when figdrawTextBackend == "hybrid":
    if rasterize:
      result.generateGlyphImages()
