import std/[os, unicode, sequtils, tables, strutils, sets, hashes]
import std/isolation

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
import pkg/chronicles

import ./rchannels
import ./imgutils
import ./fonttypes
import ./shared

type GlyphPosition* = ref object ## Represents a glyph position after typesetting.
  fontId*: FontId
  rune*: Rune
  pos*: Vec2 # Where to draw the image character.
  rect*: Rect
  descent*: float32
  lineHeight*: float32

proc toSlices*[T: SomeInteger](a: openArray[(T, T)]): seq[Slice[T]] =
  a.mapIt(it[0] .. it[1])

proc hash*(tp: Typeface): Hash =
  var h = Hash(0)
  h = h !& hash tp.filePath
  result = !$h

proc hash*(glyph: GlyphPosition): Hash {.inline.} =
  result = hash((2344, glyph.fontId, glyph.rune))

proc getId*(typeface: Typeface): TypefaceId =
  result = TypefaceId typeface.hash()
  for i in 1 .. 100:
    if result.int == 0:
      result = TypefaceId(typeface.hash() !& hash(i))
    else:
      break
  doAssert result.int != 0, "Typeface hash results in invalid id"

iterator glyphs*(arrangement: GlyphArrangement): GlyphPosition =
  var idx = 0

  block:
    for i, (span, gfont) in zip(arrangement.spans, arrangement.fonts):
      while idx < arrangement.runes.len():
        let
          pos = arrangement.positions[idx]
          rune = arrangement.runes[idx]
          selection = arrangement.selectionRects[idx]

        let descent = gfont.lineHeight - gfont.descentAdj

        yield GlyphPosition(
          fontId: gfont.fontId,
          # fontSize: gfont.size,
          rune: rune,
          pos: pos,
          rect: selection,
          descent: descent,
          lineHeight: gfont.lineHeight,
        )

        idx.inc()
        if idx notin span:
          break

var
  typefaceTable*: Table[TypefaceId, Typeface] ## holds the table of parsed fonts
  fontTable* {.threadvar.}: Table[FontId, pixie.Font]

proc generateGlyphImage(arrangement: GlyphArrangement) =
  ## returns Glyph's hash, will generate glyph if needed
  ##
  ## Font Glyphs are generated with Bottom vAlign and Center hAlign
  ## this puts the glyphs in the right position
  ## so that the renderer doesn't need to figure out adjustments

  for glyph in arrangement.glyphs():
    if unicode.isWhiteSpace(glyph.rune):
      # echo "skipped:rune: ", glyph.rune, " ", glyph.rune.int
      continue

    let hashFill = glyph.hash()

    if not hasImage(hashFill.ImageId):
      let
        wh = glyph.rect.wh
        fontId = glyph.fontId
        font = fontTable[fontId]
        text = $glyph.rune
        arrangement = pixie.typeset(
          @[newSpan(text, font)],
          bounds = wh,
          hAlign = CenterAlign,
          vAlign = TopAlign,
          wrap = false,
        )
      let
        snappedBounds = arrangement.computeBounds().snapToPixels()

      let
        lh = font.defaultLineHeight()
        bounds = rect(0, 0, snappedBounds.w + snappedBounds.x, lh)

      if bounds.w == 0 or bounds.h == 0:
        echo "GEN IMG: ", glyph.rune, " wh: ", wh, " snapped: ", snappedBounds
        continue

      try:
        font.paint = parseHex"FFFFFF"
        var image = newImage(bounds.w.int, bounds.h.int)
        image.fillText(arrangement)

        # put into cache
        loadImage(hashFill.ImageId, image)
      except PixieError:
        discard

type TypeFaceKinds* = enum
  TTF
  OTF
  SVG

proc readTypefaceImpl(
    name, data: string, kind: TypeFaceKinds
): Typeface {.raises: [PixieError].} =
  ## Loads a typeface from a buffer
  try:
    result =
      case kind
      of TTF:
        parseTtf(data)
      of OTF:
        parseOtf(data)
      of SVG:
        parseSvgFont(data)
  except IOError as e:
    raise newException(PixieError, e.msg, e)

  result.filePath = name

proc loadTypeface*(name: string): FontId =
  ## loads a font from a file and adds it to the font index

  let
    typefacePath = figDataDir() / name
    typeface = readTypeface(typefacePath)
    id = typeface.getId()

  doAssert id != 0
  if id in typefaceTable:
    doAssert typefaceTable[id] == typeface
  typefaceTable[id] = typeface
  result = id

proc loadTypeface*(name, data: string, kind: TypeFaceKinds): FontId =
  ## loads a font from buffer and adds it to the font index

  let
    typeface = readTypefaceImpl(name, data, kind)
    id = typeface.getId()

  typefaceTable[id] = typeface
  result = id

proc convertFont*(font: UiFont): (FontId, Font) =
  ## does the typesetting using pixie, then converts to Figuro's internal
  ## types

  let
    id = FontId(hash((font.getId(), app.uiScale)))
    typeface = typefaceTable[font.typefaceId]

  if not fontTable.hasKey(id):
    var pxfont = newFont(typeface)
    pxfont.size = font.size.scaled()
    pxfont.typeface = typeface
    pxfont.textCase = parseEnum[TextCase]($font.fontCase)
    pxfont.lineHeight      = font.lineHeight.scaled()
    pxfont.underline            = font.underline
    pxfont.strikethrough        = font.strikethrough
    pxfont.noKerningAdjustments = font.noKerningAdjustments

    if font.lineHeight == 0.0'f32:
      pxfont.lineHeight = pxfont.defaultLineHeight()

    fontTable[id] = pxfont
    result = (id, pxfont)
  else:
    result = (id, fontTable[id])

proc getLineHeightImpl*(font: UiFont): float32 =
  let (_, pf) = font.convertFont()
  result = pf.lineHeight.descaled()

proc calcMinMaxContent(
    textLayout: GlyphArrangement
): tuple[maxSize, minSize: Vec2, bounding: Rect] =
  ## estimate the maximum and minimum size of a given typesetting

  var longestWord: Slice[int]
  var longestWordLen: float

  var words = 0
  var wordsHeight = 0.0
  var curr: Slice[int]
  var currLen: float
  var maxWidth: float
  var rect: Rect = rect(float32.high, float32.high, 0, 0)

  # find longest word and count the number of words
  # herein min content width is longest word
  # herein max content height is a word on each line
  var idx = 0
  for glyph in textLayout.glyphs():
    maxWidth += glyph.rect.w
    rect.x = min(rect.x, glyph.rect.x)
    rect.y = min(rect.y, glyph.rect.y)
    rect.w = max(rect.w, glyph.rect.x + glyph.rect.w)
    rect.h = max(rect.h, glyph.rect.y + glyph.rect.h)

    if glyph.rune.isWhiteSpace:
      curr = idx + 1 .. idx
      currLen = 0.0
    else:
      if curr.len() == 1:
        words.inc
        wordsHeight += glyph.lineHeight
      curr.b = idx
      currLen += glyph.rect.w

    if currLen > longestWordLen:
      longestWord = curr
      longestWordLen = currLen

    idx.inc()

  # find tallest font
  var maxLine = 0.0
  for font in textLayout.fonts:
    maxLine = max(maxLine, font.lineHeight)

  # set results
  result.minSize.x = longestWordLen.descaled()
  result.minSize.y = maxLine.descaled()

  result.maxSize.x = maxWidth.descaled()
  result.maxSize.y = wordsHeight.descaled()

  result.bounding = rect.descaled()

proc convertArrangement(
    arrangement: Arrangement,
    box: Rect,
    uiSpans: openArray[(UiFont, string)],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    gfonts: seq[GlyphFont],
): GlyphArrangement =
  var
    lines = newSeqOfCap[Slice[int]](arrangement.lines.len())
    spanSlices = newSeqOfCap[Slice[int]](arrangement.spans.len())
    selectionRects = newSeqOfCap[Rect](arrangement.selectionRects.len())
  for line in arrangement.lines:
    lines.add line[0] .. line[1]
  for span in arrangement.spans:
    spanSlices.add span[0] .. span[1]
  for rect in arrangement.selectionRects:
    selectionRects.add rect

  result = GlyphArrangement(
    contentHash:
      block:
        var h = Hash(0)
        h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign)
        h = h !& hash(app.uiScale)
        !$h,
    lines: lines, # arrangement.lines.toSlices(),
    spans: spanSlices, # arrangement.spans.toSlices(),
    fonts: gfonts,
    runes: arrangement.runes,
    positions: arrangement.positions,
    selectionRects: selectionRects,
  )

proc typeset*(
    box: Rect,
    uiSpans: openArray[(UiFont, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent: bool,
    wrap: bool,
): GlyphArrangement =
  ## does the typesetting using pixie, then converts the typeseet results
  ## into Figuro's own internal types
  ## Primarily done for thread safety
  threadEffects:
    AppMainThread

  var
    wh = box.scaled().wh
    sz = uiSpans.mapIt(it[0].size.float)
    minSz = sz.foldl(max(a, b), 0.0)

  var spans: seq[Span]
  var pfs: seq[Font]
  var gfonts: seq[GlyphFont]
  for (uiFont, txt) in uiSpans:
    let (fontId, pf) = uiFont.convertFont()
    pfs.add(pf)
    spans.add(newSpan(txt, pf))
    assert not pf.typeface.isNil
    # There's gotta be a better way. Need to lookup the font formulas or equations or something
    #let lhAdj = pf.lineHeight
    #let lhAdj = max(pf.lineHeight - pf.size, 0.0)
    let lhAdj = (pf.lineHeight - pf.size * pf.lineHeight / pf.defaultLineHeight()) / 2
    gfonts.add GlyphFont(
      fontId: fontId, lineHeight: pf.lineHeight, descentAdj: lhAdj
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
    ## calcaulate min width of content
    var wh = wh
    wh.y = result.maxSize.y.scaled()
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
      let wh = vec2(wh.x, minContent.bounding.h.scaled())
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

  let maxLineHeight = max(sz)
  result.minSize += vec2(maxLineHeight / 2, 0)
  result.maxSize += vec2(maxLineHeight / 2, 0)
  result.bounding = result.bounding + rect(0, 0, 0, maxLineHeight / 2)
  # debug "getTypesetImpl:post:", boxWh= box.wh, wh= wh, contentHash = getContentHash(box.wh, uiSpans, hAlign, vAlign),
  #           minSize = result.minSize, maxSize = result.maxSize, bounding = result.bounding

  result.generateGlyphImage()
  # echo "font: "
  # print arrangement.fonts[0].size
  # print arrangement.fonts[0].lineHeight
  # echo "arrangement: "
  # print result

proc glyphFontFor(uiFont: UiFont): tuple[id: FontId, font: Font,
    glyph: GlyphFont] =
  let (fontId, pf) = uiFont.convertFont()
  let defaultLineHeight = pf.defaultLineHeight()
  let lineHeight =
    if pf.lineHeight >= 0:
      pf.lineHeight
    else:
      defaultLineHeight
  let lhAdj = 0.0'f32
  #if defaultLineHeight > 0:
  #  (lineHeight - pf.size * lineHeight / defaultLineHeight) / 2
  #else:
  #  0.0'f32
  result = (
    id: fontId,
    font: pf,
    glyph: GlyphFont(fontId: fontId, lineHeight: lineHeight, descentAdj: lhAdj),
  )

proc placeGlyphs*(
    font: UiFont,
    glyphs: openArray[(Rune, Vec2)],
    origin: GlyphOrigin = GlyphTopLeft,
): GlyphArrangement =
  ## Builds a glyph arrangement using explicit positions for each glyph.
  ## `origin` controls whether positions are the glyph's top-left or baseline.
  threadEffects:
    AppMainThread

  result = GlyphArrangement()
  if glyphs.len == 0:
    return

  let fontInfo = glyphFontFor(font)
  let cachedFont = (font: fontInfo.font, glyph: fontInfo.glyph)

  var
    runes = newSeqOfCap[Rune](glyphs.len)
    positions = newSeqOfCap[Vec2](glyphs.len)
    selectionRects = newSeqOfCap[Rect](glyphs.len)
    contentHash = Hash(0)

  for (rune, pos) in glyphs:

    let scaledPos = pos.scaled()
    let descent = cachedFont.glyph.lineHeight - cachedFont.glyph.descentAdj
    var baselinePos = scaledPos
    if origin == GlyphTopLeft:
      baselinePos.y = scaledPos.y + descent

    runes.add(rune)
    positions.add(baselinePos)

    let drawPos = vec2(baselinePos.x, baselinePos.y - descent)
    let advance = cachedFont.font.typeface.getAdvance(rune) *
        cachedFont.font.scale
    selectionRects.add(
      rect(drawPos.x, drawPos.y, advance, cachedFont.glyph.lineHeight)
    )

    contentHash =
      contentHash !& hash((fontInfo.id, rune, pos.x, pos.y, origin, app.uiScale))

  result.lines = @[0 .. glyphs.len - 1]
  result.spans = @[0 .. glyphs.len - 1]
  result.fonts = @[cachedFont.glyph]
  result.runes = runes
  result.positions = positions
  result.selectionRects = selectionRects
  result.contentHash = !$contentHash

  var
    minX = float32.high
    minY = float32.high
    maxX = -float32.high
    maxY = -float32.high
  for rect in selectionRects:
    minX = min(minX, rect.x)
    minY = min(minY, rect.y)
    maxX = max(maxX, rect.x + rect.w)
    maxY = max(maxY, rect.y + rect.h)
  if selectionRects.len > 0:
    let boundingScaled = rect(minX, minY, maxX - minX, maxY - minY)
    result.bounding = boundingScaled.descaled()
    result.minSize = result.bounding.wh
    result.maxSize = result.bounding.wh

  result.generateGlyphImage()
