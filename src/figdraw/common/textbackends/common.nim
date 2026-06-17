import std/unicode

import pkg/vmath

import ../fonttypes

proc calcMinMaxContent*(
    textLayout: GlyphArrangement
): tuple[maxSize, minSize: Vec2, bounding: Rect] =
  ## Estimate maximum and minimum content size for a glyph arrangement.
  var longestWord: Slice[int]
  var longestWordLen: float

  var words = 0
  var wordsHeight = 0.0
  var curr: Slice[int]
  var currLen: float
  var maxWidth: float
  var rect: Rect = rect(float32.high, float32.high, 0, 0)

  let glyphCount =
    if textLayout.arrangedGlyphs.len > 0:
      textLayout.arrangedGlyphs.len
    else:
      textLayout.runes.len

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
    rect.x = min(rect.x, glyphRect.x)
    rect.y = min(rect.y, glyphRect.y)
    rect.w = max(rect.w, glyphRect.x + glyphRect.w)
    rect.h = max(rect.h, glyphRect.y + glyphRect.h)

    if glyphRune.isWhiteSpace:
      curr = idx + 1 .. idx
      currLen = 0.0
    else:
      if curr.len() == 1:
        words.inc
        for fontIndex, span in textLayout.spans:
          if idx in span and fontIndex < textLayout.fonts.len:
            wordsHeight += textLayout.fonts[fontIndex].lineHeight
            break
      curr.b = idx
      currLen += glyphRect.w

    if currLen > longestWordLen:
      longestWord = curr
      longestWordLen = currLen

  var maxLine = 0.0
  for font in textLayout.fonts:
    maxLine = max(maxLine, font.lineHeight)

  result.minSize.x = longestWordLen
  result.minSize.y = maxLine

  result.maxSize.x = maxWidth
  result.maxSize.y = wordsHeight

  if glyphCount == 0:
    rect = rect(0, 0, 0, 0)
  result.bounding = rect

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
