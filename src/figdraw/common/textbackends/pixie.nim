import std/[algorithm, math, strutils, unicode]

import pkg/chronicles
import pkg/pixie
import pkg/pixie/fonts

import ../fontglyphs
import ../fonttypes
import ../shared
import ../typefaces
import ./common
import ./paragraphlayout

proc pixieHyphenResolver(): HyphenResolver =
  ## Visible hyphens in the Pixie font of the glyph that precedes a break.
  result = proc(fontId: FontId): HyphenGlyph =
    var font: FigFont
    if not tryGetFigFont(fontId, font):
      return
    let info = glyphFontFor(font)
    result = HyphenGlyph(
      found: true,
      glyphFont: info.glyph,
      glyphId: syntheticFontGlyphId(info.glyph.fontId, Rune('-')),
      advance: info.font.typeface.getAdvance(Rune('-')) * info.font.scale,
    )

proc layoutStyledParagraphs(
    result: var GlyphArrangement,
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    runs: openArray[StyledTextRun],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent, wrap: bool,
) =
  ## Lays out unwrapped Pixie lines, one per paragraph, with FigDraw's
  ## paragraph layout so indents, justification, and hyphenation match the
  ## HarfBuzz backend. `runs[i]` locates `uiSpans[i]` in the source that
  ## glyph source ranges index, unaffected by Pixie's filtered display text.
  var spanStarts = newSeqOfCap[int](runs.len)
  for run in runs:
    spanStarts.add int(run.byteStart)
  var paragraphs = newSeqOfCap[LayoutParagraph](result.lines.len)
  for line in result.lines:
    var style = uiSpans[0][0]
    if line.a <= line.b:
      let spanIndex = max(
        spanStarts.upperBound(result.arrangedGlyphs[line.a].source.byteStart) - 1, 0
      )
      style = uiSpans[min(spanIndex, uiSpans.high)][0]
    paragraphs.add LayoutParagraph(
      glyphs: line, style: style.paragraph, language: style.font.language
    )
  let lines =
    result.breakParagraphLines(paragraphs, [], box.w, wrap, pixieHyphenResolver())
  result.reflowParagraphLines(lines, paragraphs, box.w, wrap)
  var alignmentBox = box
  if minContent:
    alignmentBox.h = max(alignmentBox.h, result.calcMinMaxContent().bounding.h)
  result.alignParagraphLines(lines, paragraphs, alignmentBox, hAlign, vAlign)
  let content = result.calcMinMaxContent()
  result.minSize = content.minSize
  result.maxSize = content.maxSize
  result.bounding = content.bounding
  if minContent:
    result.minSize.y = max(result.minSize.y, result.bounding.h)

proc typesetWithSource(
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent: bool,
    wrap: bool,
    rasterize: bool,
    sourceRunes: Utf8Runes,
    sourceRuns: openArray[StyledTextRun],
): GlyphArrangement =
  ## Typesets with Pixie, then converts to FigDraw's backend-neutral data.
  threadEffects:
    AppMainThread

  let wh = box.wh

  var spans: seq[Span]
  var gfonts: seq[GlyphFont]
  for (style, txt) in uiSpans:
    let (fontId, pf) = style.convertFont()
    spans.add(newSpan(txt, pf))
    assert not pf.typeface.isNil
    let lineHeight =
      if pf.lineHeight >= 0:
        pf.lineHeight
      else:
        pf.defaultLineHeight()
    let lineGap = (lineHeight / pf.scale) - pf.typeface.ascent + pf.typeface.descent
    let baselineOffset = round((pf.typeface.ascent + lineGap / 2) * pf.scale)
    gfonts.add GlyphFont(
      fontId: fontId,
      size: style.font.size,
      lineHeight: lineHeight,
      descentAdj: baselineOffset,
      underline: style.font.underline,
      strikethrough: style.font.strikethrough,
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

  # Pixie wraps unstyled text itself; FigDraw lays out paragraph styles and
  # soft hyphens, which Pixie would draw as visible glyphs.
  if uiSpans.anyIt(not it[0].paragraph.isDefault or "\u00AD" in it[1]):
    let unwrapped = pixie.typeset(
      spans, bounds = vec2(0, wh.y), hAlign = LeftAlign, vAlign = TopAlign, wrap = false
    )
    var
      source = sourceRunes
      runs = @sourceRuns
    if source.isNil:
      # Map glyphs to the caller's text so styles follow original offsets.
      var
        text = newStringOfCap(uiSpans.len * 16)
        runeOffset = 0
      for index, (_, part) in uiSpans:
        let runeCount = part.runeLen
        runs.add StyledTextRun(
          byteStart: uint32(text.len),
          byteEnd: uint32(text.len + part.len),
          runeStart: uint32(runeOffset),
          runeEnd: uint32(runeOffset + runeCount),
          styleId: TextStyleId(uint32(index)),
        )
        text.add part
        runeOffset += runeCount
      source = initUtf8Runes(text)
    result = convertArrangementWithSource(
      unwrapped, box, uiSpans, hAlign, vAlign, gfonts, minContent, wrap, source, runs
    )
    result.layoutStyledParagraphs(box, uiSpans, runs, hAlign, vAlign, minContent, wrap)
    if rasterize:
      result.generateGlyphImages()
    return

  let arrangement =
    pixie.typeset(spans, bounds = wh, hAlign = ha, vAlign = va, wrap = wrap)
  result = convertArrangementWithSource(
    arrangement, box, uiSpans, hAlign, vAlign, gfonts, minContent, wrap, sourceRunes,
    sourceRuns,
  )

  let content = result.calcMinMaxContent()
  result.minSize = content.minSize
  result.maxSize = content.maxSize
  result.bounding = content.bounding

  if minContent:
    var wh = wh
    wh.y = result.maxSize.y
    let arr = pixie.typeset(
      spans, bounds = wh, hAlign = LeftAlign, vAlign = TopAlign, wrap = wrap
    )
    let minResult = convertArrangementWithSource(
      arr, box, uiSpans, hAlign, vAlign, gfonts, minContent, wrap, sourceRunes,
      sourceRuns,
    )

    let minContentSize = minResult.calcMinMaxContent()
    trace "minContent:",
      boxWh = box.wh,
      wh = wh,
      minSize = minContentSize.minSize,
      maxSize = minContentSize.maxSize,
      bounding = minContentSize.bounding,
      boundH = result.bounding.h

    if minContentSize.bounding.h > result.bounding.h:
      let wh = vec2(wh.x, minContentSize.bounding.h)
      let minAdjusted =
        pixie.typeset(spans, bounds = wh, hAlign = ha, vAlign = va, wrap = wrap)
      result = convertArrangementWithSource(
        minAdjusted, box, uiSpans, hAlign, vAlign, gfonts, minContent, wrap,
        sourceRunes, sourceRuns,
      )

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
  ## Typesets with Pixie, then converts to FigDraw's backend-neutral data.
  threadEffects:
    AppMainThread
  typesetWithSource(box, uiSpans, hAlign, vAlign, minContent, wrap, rasterize, nil, [])

proc typesetSourceSpans*(
    box: Rect,
    source: Utf8Runes,
    runs: openArray[StyledTextRun],
    styles: openArray[FontStyle],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent, wrap, rasterize: bool,
): GlyphArrangement =
  ## Pixie requires owned span strings, but layout retains the source directly.
  var spans = newSeqOfCap[(FontStyle, string)](runs.len)
  for run in runs:
    spans.add(
      (
        styles[int(uint32(run.styleId))],
        source.bytes[int(run.byteStart) ..< int(run.byteEnd)],
      )
    )
  typesetWithSource(
    box, spans, hAlign, vAlign, minContent, wrap, rasterize, source, runs
  )
