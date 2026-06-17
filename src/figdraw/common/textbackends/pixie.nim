import std/[math, sequtils]

import pkg/chronicles
import pkg/pixie
import pkg/pixie/fonts

import ../fontglyphs
import ../fonttypes
import ../shared
import ../typefaces
import ./common

proc typeset*(
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  ## Typesets with Pixie, then converts to FigDraw's backend-neutral data.
  threadEffects:
    AppMainThread

  var
    wh = box.wh
    sz = uiSpans.mapIt(it[0].font.size.float)

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
      fontId: fontId, lineHeight: lineHeight, descentAdj: baselineOffset
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

  result.addFontSizePadding(sz)
  result.generateGlyphImages()
