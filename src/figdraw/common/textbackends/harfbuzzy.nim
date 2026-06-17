import std/[algorithm, hashes, sequtils, strutils, unicode]

import pkg/harfbuzzy as hb
import pkg/vmath

import ../fonttypes
import ../shared
import ../typefaces
import ./common

when figdrawTextBackend == "hybrid":
  import ../fontglyphs

type DecodedSource = object
  runes: seq[Rune]
  byteStarts: seq[int]
  byteEnds: seq[int]

proc decodeSource(text: string): DecodedSource =
  var byteOffset = 0
  for rune in text.runes:
    result.runes.add rune
    result.byteStarts.add byteOffset
    byteOffset += ($rune).len
    result.byteEnds.add byteOffset

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

proc runeRangeForBytes(
    decoded: DecodedSource, byteStart, byteEnd: int
): GlyphSourceRange =
  result.byteStart = byteStart
  result.byteEnd = byteEnd
  result.runeStart = decoded.runes.len
  result.runeEnd = decoded.runes.len

  for i in 0 ..< decoded.runes.len:
    if decoded.byteEnds[i] > byteStart:
      result.runeStart = i
      break

  for i in result.runeStart ..< decoded.runes.len:
    if decoded.byteStarts[i] >= byteEnd:
      result.runeEnd = i
      break
  if result.runeEnd == decoded.runes.len and byteEnd >= byteStart:
    result.runeEnd = decoded.runes.len
  if result.runeStart > result.runeEnd:
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

proc initHarfbuzzTypeface(font: FigFont): hb.Typeface =
  let source = getTypefaceSource(font.typefaceId)
  let blob = hb.initBlob(source.data)
  let face = hb.initFace(blob)
  result = hb.initTypeface(face)

proc pxScale(typeface: hb.Typeface, font: FigFont): float32 =
  let upem = typeface.face.upem
  if upem <= 0:
    return 1.0'f32
  font.size / upem.float32

proc nextClusterBoundary(run: hb.ShapedRun, cluster: int): int =
  var boundaries = @[run.textRun.byteEnd]
  for glyph in run.glyphRun.glyphs:
    let glyphCluster = int(glyph.cluster)
    if glyphCluster > cluster:
      boundaries.add glyphCluster
  boundaries.sort()
  result = boundaries[0]

proc applyAlignment(
    arrangement: var GlyphArrangement,
    box: Rect,
    hAlign: FontHorizontal,
    vAlign: FontVertical,
) =
  if arrangement.arrangedGlyphs.len == 0:
    return

  let content = arrangement.calcMinMaxContent()
  let bounds = content.bounding

  var dx = -bounds.x
  case hAlign
  of Left:
    discard
  of Center:
    dx += (box.w - bounds.w) / 2
  of Right:
    dx += box.w - bounds.w

  var dy = -bounds.y
  case vAlign
  of Top:
    discard
  of Middle:
    dy += (box.h - bounds.h) / 2
  of Bottom:
    dy += box.h - bounds.h

  let delta = vec2(dx, dy)
  for glyph in arrangement.arrangedGlyphs.mitems:
    glyph.pos += delta
    glyph.rect = glyph.rect + rect(delta.x, delta.y, 0, 0)
  for pos in arrangement.positions.mitems:
    pos += delta
  for selection in arrangement.selectionRects.mitems:
    selection = selection + rect(delta.x, delta.y, 0, 0)

proc appendShapedSpan(
    arrangement: var GlyphArrangement,
    decoded: DecodedSource,
    style: FontStyle,
    text: string,
    byteOffset: int,
    pen: var Vec2,
) =
  let fontInfo = glyphFontFor(style.font)
  let hbTypeface = initHarfbuzzTypeface(style.font)
  let scale = hbTypeface.pxScale(style.font)
  let paragraph = hbTypeface.shapeParagraph(text)

  let spanStart = arrangement.arrangedGlyphs.len
  arrangement.fonts.add fontInfo.glyph
  arrangement.spanColors.add style.color

  for run in paragraph.visualRuns:
    for glyph in run.glyphRun.glyphs:
      let
        cluster = int(glyph.cluster)
        nextCluster = run.nextClusterBoundary(cluster)
        source =
          decoded.runeRangeForBytes(byteOffset + cluster, byteOffset + nextCluster)
        rune = decoded.firstRune(source)
        advance = vec2(glyph.xAdvance.float32 * scale, -glyph.yAdvance.float32 * scale)
        offset = vec2(glyph.xOffset.float32 * scale, -glyph.yOffset.float32 * scale)
        pos = pen + offset
        drawPos = vec2(pos.x, pos.y - fontInfo.glyph.descentAdj)
        selectionWidth = max(abs(advance.x), 0.0'f32)
        selection =
          rect(drawPos.x, drawPos.y, selectionWidth, fontInfo.glyph.lineHeight)

      arrangement.arrangedGlyphs.add ArrangedGlyph(
        fontId: fontInfo.id,
        glyphId: FontGlyphId(glyph.codepoint.uint32),
        cluster: glyph.cluster,
        source: source,
        rune: rune,
        isWhitespace: decoded.sourceIsWhitespace(source),
        pos: pos,
        advance: advance,
        offset: offset,
        rect: selection,
      )
      arrangement.runes.add rune
      arrangement.positions.add pos
      arrangement.selectionRects.add selection

      pen += advance

  let spanStop = arrangement.arrangedGlyphs.len - 1
  arrangement.spans.add spanStart .. spanStop

proc typeset*(
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  ## Typesets with Harfbuzzy and converts shaped glyph ids into FigDraw data.
  threadEffects:
    AppMainThread

  discard minContent
  discard wrap

  var shapedSpans = newSeqOfCap[(FontStyle, string)](uiSpans.len)
  for (style, text) in uiSpans:
    shapedSpans.add((style, text.applyFontCase(style.font.fontCase)))

  let sourceText = shapedSpans.mapIt(it[1]).join("")
  let decoded = decodeSource(sourceText)
  let fontSizes = shapedSpans.mapIt(it[0].font.size.float)

  result = GlyphArrangement(
    contentHash: block:
      var h = Hash(0)
      h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign)
      h = h !& hash(figUiScale())
      !$h,
    sourceRunes: decoded.runes,
  )

  var pen = vec2(0, 0)
  var byteOffset = 0
  for (style, text) in shapedSpans:
    let baseline = glyphFontFor(style.font).glyph.descentAdj
    if result.arrangedGlyphs.len == 0:
      pen.y = baseline
    result.appendShapedSpan(decoded, style, text, byteOffset, pen)
    byteOffset += text.len

  if result.arrangedGlyphs.len > 0:
    result.lines = @[0 .. result.arrangedGlyphs.len - 1]

  result.applyAlignment(box, hAlign, vAlign)

  let content = result.calcMinMaxContent()
  result.minSize = content.minSize
  result.maxSize = content.maxSize
  result.bounding = content.bounding
  result.addFontSizePadding(fontSizes)

  when figdrawTextBackend == "hybrid":
    result.generateGlyphImages()
