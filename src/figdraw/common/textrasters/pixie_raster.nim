import std/unicode

import pkg/chronicles
import pkg/pixie
import pkg/pixie/fonts

import ../fonttypes
import ../imgutils
import ../shared
import ../typefaces

const lcdFilterWeights = [8'i32, 77'i32, 86'i32, 77'i32, 8'i32]
  ## FreeType's default 5-tap LCD filter weights.

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

proc renderPixieGlyph*(
    imageId: ImageId,
    fontId: FontId,
    rune: Rune,
    glyphRect: Rect,
    lcdFiltering = false,
    subpixelVariant = 0,
    subpixelSteps = 10,
    upload = true,
): Image {.discardable.} =
  ## Renders one glyph through Pixie's rune-based raster path.
  let font = getPixieFont(fontId)

  var
    text = $rune
    arrangement = pixie.typeset(
      @[newSpan(text, font)],
      bounds = glyphRect.wh.scaled(),
      hAlign = CenterAlign,
      vAlign = TopAlign,
      wrap = false,
    )

  if subpixelVariant > 0:
    let subpixelOffset = subpixelVariant.float32 / subpixelSteps.float32
    for i in 0 ..< arrangement.positions.len:
      arrangement.positions[i].x += subpixelOffset

  let snappedBounds = arrangement.computeBounds().snapToPixels()

  let
    lineHeight = font.defaultLineHeight()
    bounds = rect(0, 0, scaled(snappedBounds.w + snappedBounds.x), scaled(lineHeight))

  if bounds.w == 0 or bounds.h == 0:
    debug "GEN IMG: ",
      rune = $rune, rectWh = repr glyphRect.wh, snapped = repr snappedBounds
    return nil

  try:
    font.paint = parseHex"FFFFFF"
    var image = newImage(bounds.w.int, bounds.h.int)
    image.fillText(arrangement)
    if lcdFiltering:
      image.applyLcdFilter()

    if upload:
      loadGlyphImage(imageId, fontId, getFigFont(fontId).typefaceId, image)
    return image
  except PixieError:
    return nil
