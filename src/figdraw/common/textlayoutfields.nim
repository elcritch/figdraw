# Field-style access for both the static and native-library arrangements.

template lines*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.lines

template `lines=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.lines = value

template sourceRunes*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.sourceRunes

template `sourceRunes=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.sourceRunes = value

template arrangedGlyphs*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.arrangedGlyphs

template `arrangedGlyphs=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.arrangedGlyphs = value

template runes*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.runes

template `runes=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.runes = value

template positions*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.positions

template `positions=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.positions = value

template selectionRects*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.selectionRects

template `selectionRects=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.selectionRects = value

template maxSize*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.maxSize

template `maxSize=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.maxSize = value

template minSize*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.minSize

template `minSize=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.minSize = value

template bounding*(arrangement: GlyphArrangement): untyped =
  arrangement.textLayout.bounding

template `bounding=`*(arrangement: var GlyphArrangement, value: untyped) =
  arrangement.textLayout.bounding = value
