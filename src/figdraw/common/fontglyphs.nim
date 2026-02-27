import std/[os, unicode, sequtils, tables, strutils, sets, hashes]
import std/isolation

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
import pkg/chronicles

import ./rchannels
import ./imgutils
import ./shared

import ./fonttypes
import ./typefaces

type GlyphPosition* = ref object ## Represents a glyph position after typesetting.
  fontId*: FontId
  rune*: Rune
  pos*: Vec2 # Where to draw the image character.
  rect*: Rect
  descent*: float32
  lineHeight*: float32
  fill*: Fill

const
  lcdFilterWeights = [8'i32, 77'i32, 86'i32, 77'i32, 8'i32] # FT_LCD_FILTER_DEFAULT
  glyphVariantSubpixelSteps* = 10

proc clampGlyphVariantSubpixelStep*(subpixelVariant: int): int {.inline.} =
  if subpixelVariant <= 0:
    return 0
  min(subpixelVariant, glyphVariantSubpixelSteps - 1)

proc toGlyphVariantSubpixelStep*(fractionalX: float32): int {.inline.} =
  let clamped = max(0.0'f32, min(fractionalX, 0.999'f32))
  clampGlyphVariantSubpixelStep((clamped * glyphVariantSubpixelSteps.float32).int)

proc applyLcdFilter*(image: var Image) =
  ## Applies FreeType's default 5-tap LCD filter horizontally.
  if image.width <= 0 or image.height <= 0:
    return

  let src = image.data
  var filtered = newSeq[type(src[0])](src.len)
  let maxX = image.width - 1

  for y in 0 ..< image.height:
    let rowStart = y * image.width
    for x in 0 ..< image.width:
      var sumR, sumG, sumB, sumA: int32
      for i, weight in lcdFilterWeights:
        let sx = min(max(x + i - 2, 0), maxX)
        let px = src[rowStart + sx]
        sumR += px.r.int32 * weight
        sumG += px.g.int32 * weight
        sumB += px.b.int32 * weight
        sumA += px.a.int32 * weight

      let idx = rowStart + x
      filtered[idx] = src[idx]
      filtered[idx].r = uint8((sumR + 128'i32) shr 8)
      filtered[idx].g = uint8((sumG + 128'i32) shr 8)
      filtered[idx].b = uint8((sumB + 128'i32) shr 8)
      filtered[idx].a = uint8((sumA + 128'i32) shr 8)

  image.data = move(filtered)

proc hash*(
    glyph: GlyphPosition, lcdFiltering = false, subpixelVariant = 0
): Hash {.inline.} =
  #result = hash((2344, glyph.fontId, glyph.rune, app.uiScale))
  let variant = clampGlyphVariantSubpixelStep(subpixelVariant)
  result = hash((2344, glyph.fontId, glyph.rune, lcdFiltering, variant))

proc generateGlyph*(glyph: GlyphPosition, lcdFiltering = false, subpixelVariant = 0) =
  if unicode.isWhiteSpace(glyph.rune):
    return

  let
    variant = clampGlyphVariantSubpixelStep(subpixelVariant)
    hashFill = glyph.hash(lcdFiltering = lcdFiltering, subpixelVariant = variant)

  if not hasImage(hashFill.ImageId):
    let
      fontId = glyph.fontId
      font = getPixieFont(fontId)

    var
      text = $glyph.rune
      arrangement = pixie.typeset(
        @[newSpan(text, font)],
        bounds = glyph.rect.wh.scaled(),
        hAlign = CenterAlign,
        vAlign = TopAlign,
        wrap = false,
      )
    if variant > 0:
      let subpixelOffset = variant.float32 / glyphVariantSubpixelSteps.float32
      for i in 0 ..< arrangement.positions.len:
        arrangement.positions[i].x += subpixelOffset

    let snappedBounds = arrangement.computeBounds().snapToPixels()

    let
      lh = font.defaultLineHeight()
      bounds = rect(0, 0, scaled(snappedBounds.w + snappedBounds.x), scaled(lh))

    if bounds.w == 0 or bounds.h == 0:
      error "GEN IMG: ", rune = $glyph.rune, wh = repr wh, snapped = repr snappedBounds
      return

    try:
      font.paint = parseHex"FFFFFF"
      var image = newImage(bounds.w.int, bounds.h.int)
      image.fillText(arrangement)
      if lcdFiltering:
        image.applyLcdFilter()

      # put into cache
      loadImage(hashFill.ImageId, image)
    except PixieError:
      discard

iterator glyphs*(arrangement: GlyphArrangement): GlyphPosition =
  var idx = 0

  block:
    for i, span in arrangement.spans:
      let gfont = arrangement.fonts[i]
      let spanColor =
        if i < arrangement.spanColors.len:
          arrangement.spanColors[i]
        else:
          fill(rgba(0, 0, 0, 255))
      while idx < arrangement.runes.len():
        let
          pos = arrangement.positions[idx]
          rune = arrangement.runes[idx]
          selection = arrangement.selectionRects[idx]

        #let descent = gfont.lineHeight - gfont.descentAdj
        let descent = gfont.lineHeight

        yield GlyphPosition(
          fontId: gfont.fontId,
          rune: rune,
          pos: pos,
          rect: selection,
          descent: descent,
          lineHeight: gfont.lineHeight,
          fill: spanColor,
        )

        idx.inc()
        if idx notin span:
          break

proc generateGlyphImages*(arrangement: GlyphArrangement, lcdFiltering = false) =
  ## returns Glyph's hash, will generate glyph if needed
  ##
  ## Font Glyphs are generated with Bottom vAlign and Center hAlign
  ## this puts the glyphs in the right position
  ## so that the renderer doesn't need to figure out adjustments

  for glyph in arrangement.glyphs():
    glyph.generateGlyph(lcdFiltering = lcdFiltering)

proc convertArrangement*(
    arrangement: Arrangement,
    box: Rect,
    uiSpans: openArray[(FontStyle, string)],
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

  for i, span in arrangement.spans:
    # hmmm, really should figure this out based on the font coordinate inversion
    # or whatever causes this...
    for j in span[0] .. span[1]:
      selectionRects[j].y -= gfonts[i].lineHeight / 6

  result = GlyphArrangement(
    contentHash: block:
      var h = Hash(0)
      h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign)
      h = h !& hash(figUiScale())
      !$h,
    lines: lines,
    spans: spanSlices,
    fonts: gfonts,
    spanColors: uiSpans.mapIt(it[0].color),
    runes: arrangement.runes,
    positions: arrangement.positions,
    selectionRects: selectionRects,
  )
