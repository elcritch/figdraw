import std/unicode

import pkg/vmath

import ../fonttypes

proc calcMinMaxContent*(
    textLayout: GlyphArrangement
): tuple[maxSize, minSize: Vec2, bounding: Rect] =
  ## Estimate maximum and minimum content size for a glyph arrangement.
  var longestWordLen: float

  var wordsHeight = 0.0
  var curr: Slice[int]
  var currLen: float
  var maxWidth: float
  var
    minX = float32.high
    minY = float32.high
    maxX = -float32.high
    maxY = -float32.high

  let glyphCount =
    if textLayout.arrangedGlyphs.len > 0:
      textLayout.arrangedGlyphs.len
    else:
      textLayout.runes.len

  let spanCount = min(textLayout.spans.len, textLayout.fonts.len)
  var orderedSpans = true
  for index in 1 ..< spanCount:
    if textLayout.spans[index].a < textLayout.spans[index - 1].a:
      orderedSpans = false
      break
  var spanIndex = 0

  for idx in 0 ..< glyphCount:
    let glyphRect =
      if textLayout.arrangedGlyphs.len > 0:
        textLayout.arrangedGlyphs[idx].rect
      elif idx < textLayout.selectionRects.len:
        textLayout.selectionRects[idx]
      else:
        rect(0, 0, 0, 0)
    let glyphRune =
      if textLayout.arrangedGlyphs.len > 0:
        textLayout.arrangedGlyphs[idx].rune
      else:
        textLayout.runes[idx]

    maxWidth += glyphRect.w
    minX = min(minX, glyphRect.x)
    minY = min(minY, glyphRect.y)
    maxX = max(maxX, glyphRect.x + glyphRect.w)
    maxY = max(maxY, glyphRect.y + glyphRect.h)

    if glyphRune.isWhiteSpace:
      curr = idx + 1 .. idx
      currLen = 0.0
    else:
      if curr.len() == 1:
        if orderedSpans:
          while spanIndex < spanCount and textLayout.spans[spanIndex].b < idx:
            inc spanIndex
          if spanIndex < spanCount and idx in textLayout.spans[spanIndex]:
            wordsHeight += textLayout.fonts[spanIndex].lineHeight
        else:
          for fontIndex in 0 ..< spanCount:
            if idx in textLayout.spans[fontIndex]:
              wordsHeight += textLayout.fonts[fontIndex].lineHeight
              break
      curr.b = idx
      currLen += glyphRect.w

    longestWordLen = max(longestWordLen, currLen)

  var maxLine = 0.0
  for font in textLayout.fonts:
    maxLine = max(maxLine, font.lineHeight)

  result.minSize.x = longestWordLen
  result.minSize.y = maxLine

  result.maxSize.x = maxWidth
  result.maxSize.y = wordsHeight

  result.bounding =
    if glyphCount == 0:
      rect(0, 0, 0, 0)
    else:
      rect(minX, minY, maxX - minX, maxY - minY)

proc maxFontSize*(fontSizes: openArray[float]): float32 =
  for size in fontSizes:
    result = max(result, size.float32)

proc addFontSizePadding*(
    arrangement: var GlyphArrangement, fontSizes: openArray[float]
) =
  let maxLineHeight = maxFontSize(fontSizes)
  arrangement.minSize += vec2(maxLineHeight / 2, 0)
  arrangement.maxSize += vec2(maxLineHeight / 2, 0)
  arrangement.bounding = arrangement.bounding + rect(0, 0, 0, maxLineHeight / 2)
