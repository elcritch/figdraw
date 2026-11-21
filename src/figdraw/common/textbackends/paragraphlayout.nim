## FigDraw adapters for shared paragraph layout.

import std/[tables, unicode]
import pkg/vmath
import threading/smartptrs
import pkg/harfbuzzy/paragraph as sharedParagraph

import ../fonttypes
import ../hyphenation

export sharedParagraph except breakParagraphLines

type
  HyphenGlyph* = object
    found*: bool
    glyphFont*: GlyphFont
    glyphId*: FontGlyphId
    advance*: float32
    imageOffset*: Vec2

  HyphenResolver* = proc(fontId: FontId): HyphenGlyph {.closure.}
    ## Resolves a visible hyphen glyph in the font of the preceding glyph.

  PatternLookup = object
    found: bool
    patterns: ConstPtr[HyphenationPatterns]

  GlyphRecord = object
    ## One glyph with the per-glyph data that spans and runes otherwise hold.
    glyph: ArrangedGlyph
    selection: Rect
    font: GlyphFont
    color: Fill
    covered: bool
    visualKey: float64 ## Original visual position; orders a line for display.

proc decompose*(arrangement: GlyphArrangement): seq[GlyphRecord] =
  result = newSeq[GlyphRecord](arrangement.arrangedGlyphs.len)
  for index, glyph in arrangement.arrangedGlyphs:
    result[index].glyph = glyph
    result[index].selection = arrangement.selectionRects[index]
    result[index].visualKey = index.float64
  for spanIndex, span in arrangement.spans:
    for glyphIndex in span:
      if glyphIndex in 0 ..< result.len:
        result[glyphIndex].font = arrangement.fonts[spanIndex]
        result[glyphIndex].color = arrangement.spanColors[spanIndex]
        result[glyphIndex].covered = true

proc recompose*(arrangement: var GlyphArrangement, records: openArray[GlyphRecord]) =
  ## Rebuilds glyph arrays, merged spans, and display runes from records.
  arrangement.arrangedGlyphs.setLen(records.len)
  arrangement.positions.setLen(records.len)
  arrangement.selectionRects.setLen(records.len)
  arrangement.spans.setLen(0)
  arrangement.fonts.setLen(0)
  arrangement.spanColors.setLen(0)
  var display = newStringOfCap(records.len)
  for index, record in records:
    arrangement.arrangedGlyphs[index] = record.glyph
    arrangement.positions[index] = record.glyph.pos
    arrangement.selectionRects[index] = record.selection
    display.add record.glyph.rune
    if not record.covered:
      continue
    if arrangement.spans.len > 0 and arrangement.spans[^1].b == index - 1 and
        arrangement.fonts[^1] == record.font and
        arrangement.spanColors[^1] == record.color:
      arrangement.spans[^1].b = index
    else:
      arrangement.spans.add index .. index
      arrangement.fonts.add record.font
      arrangement.spanColors.add record.color
  arrangement.runes = initArrangementRunes(display)

proc withHyphen*(
    base: GlyphRecord, hyphen: HyphenGlyph, rect: Rect, visualKey: float64
): GlyphRecord =
  ## A visible hyphen styled like `base`, keeping its decorations.
  result = base
  result.font =
    if hyphen.glyphFont.fontId == base.font.fontId:
      base.font
    else:
      var font = hyphen.glyphFont
      font.underline = base.font.underline
      font.strikethrough = base.font.strikethrough
      font
  result.glyph.fontId = hyphen.glyphFont.fontId
  result.glyph.glyphId = hyphen.glyphId
  result.glyph.rune = Rune('-')
  result.glyph.isWhitespace = false
  result.glyph.advance = vec2(hyphen.advance, 0)
  result.glyph.offset = vec2(0, 0)
  result.glyph.imageOffset = hyphen.imageOffset
  result.glyph.pos = vec2(rect.x, base.glyph.pos.y)
  result.glyph.rect = rect
  result.glyph.rect.w = hyphen.advance
  result.selection = result.glyph.rect
  result.visualKey = visualKey

proc fallbackLineHeight*(arrangement: GlyphArrangement): float32 =
  for font in arrangement.fonts:
    result = max(result, font.lineHeight)

proc breakParagraphLines*(
    arrangement: var GlyphArrangement,
    paragraphs: openArray[LayoutParagraph],
    breakAfter: openArray[bool],
    boxWidth: float32,
    wrap: bool,
    resolver: HyphenResolver,
): seq[ParagraphLine] =
  var patterns: Table[string, PatternLookup]
  proc points(language, word: string): seq[int] =
    if language notin patterns:
      var lookup: PatternLookup
      lookup.found = hyphenationPatternsFor(language, lookup.patterns)
      patterns[language] = lookup
    let lookup = patterns[language]
    if lookup.found:
      result = lookup.patterns[].hyphenationPoints(word)

  sharedParagraph.breakParagraphLines(
    arrangement, paragraphs, breakAfter, boxWidth, wrap, resolver, points
  )
