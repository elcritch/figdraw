import std/[math, tables]

import pkg/chroma
import pkg/pixie
import pkg/vmath

import ../fonttypes
import ../imgutils
import ../shared
import ../typefaces
import ../textbackends/state
import ./pixie_raster

when figdrawTextBackend == "harfnim":
  import pkg/harfbuzzy/harfnim_backend as hb
else:
  import pkg/harfbuzzy as hb

var hbFontCache {.threadvar.}: Table[FontId, hb.Typeface]

proc initHbFont(fontId: FontId): hb.Typeface =
  let
    font = getFigFont(fontId)
    source = getTypefaceSource(font.typefaceId)

  if source.data.len == 0:
    raise newException(ValueError, "typeface source data is empty")

  result = hb.initTypeface(hb.initFace(hb.initBlob(source.data), source.faceIndex))
  var variations = newSeqOfCap[hb.Variation](font.variations.len)
  for variation in font.variations:
    variations.add hb.initVariation(hb.toTag(variation.tag), variation.value)
  result.font.setVariations(variations)

proc cachedHbFont(fontId: FontId): hb.Typeface =
  if fontId notin hbFontCache:
    hbFontCache[fontId] = initHbFont(fontId)
  hbFontCache[fontId]

proc clearGlyphIdFontCache*(fontId: FontId) =
  hbFontCache.del(fontId)

proc clearGlyphIdTypefaceCache*(typefaceId: TypefaceId) =
  var fontIds: seq[FontId]
  for fontId in hbFontCache.keys:
    if getFigFont(fontId).typefaceId == typefaceId:
      fontIds.add fontId
  for fontId in fontIds:
    hbFontCache.del(fontId)

proc drawGlyphPath(font: hb.Font, glyphId: FontGlyphId): Path =
  result = newPath()
  for command in font.glyphOutline(uint32(glyphId)):
    case command.kind
    of hb.OutlineCommandKind.moveTo:
      result.moveTo(command.to.x, command.to.y)
    of hb.OutlineCommandKind.lineTo:
      result.lineTo(command.to.x, command.to.y)
    of hb.OutlineCommandKind.quadraticTo:
      result.quadraticCurveTo(
        command.control1.x, command.control1.y, command.to.x, command.to.y
      )
    of hb.OutlineCommandKind.cubicTo:
      result.bezierCurveTo(
        command.control1.x, command.control1.y, command.control2.x, command.control2.y,
        command.to.x, command.to.y,
      )
    of hb.OutlineCommandKind.closePath:
      result.closePath()

proc imageBoundsFor(path: Path, fallbackSize: Vec2): Rect =
  var bounds = path.computeBounds().snapToPixels()
  if bounds.w <= 0 or bounds.h <= 0:
    bounds = rect(0, 0, fallbackSize.x, fallbackSize.y).snapToPixels()
  bounds.w = max(bounds.w, fallbackSize.x)
  bounds.h = max(bounds.h, fallbackSize.y)
  bounds

proc renderGlyphIdGlyph*(
    imageId: ImageId,
    fontId: FontId,
    glyphId: FontGlyphId,
    glyphRect: Rect,
    descent: float32,
    imageOffset: Vec2,
    lcdFiltering = false,
    subpixelVariant = 0,
    subpixelSteps = 10,
    upload = true,
): Image {.discardable.} =
  ## Renders one glyph by shaped font glyph id through HarfBuzz draw callbacks.
  let handles = cachedHbFont(fontId)

  let
    figFont = getFigFont(fontId)
    upem = handles.face.upem
  if upem == 0:
    return nil

  var path = handles.font.drawGlyphPath(glyphId)
  if path == nil or ($path).len == 0:
    return nil

  let
    fontScale = figFont.size.getScaledFont() / upem.float32
    subpixelOffset =
      if subpixelVariant > 0:
        subpixelVariant.float32 / subpixelSteps.float32
      else:
        0.0'f32
    imageOffsetPx = imageOffset.scaled()
    baselineY = descent.scaled()
    transform =
      translate(vec2(subpixelOffset - imageOffsetPx.x, baselineY - imageOffsetPx.y)) *
      scale(vec2(fontScale, -fontScale))

  path.transform(transform)

  let
    fallbackSize = vec2(1.0'f32, 1.0'f32)
    bounds = imageBoundsFor(path, fallbackSize)
    imageWidth = max(ceil(bounds.x + bounds.w).int, 1)
    imageHeight = max(ceil(bounds.y + bounds.h).int, 1)

  if imageWidth <= 0 or imageHeight <= 0:
    return nil

  try:
    var image = newImage(imageWidth, imageHeight)
    image.fillPath(path, parseSomePaint(rgba(255, 255, 255, 255)))
    if lcdFiltering:
      image.applyLcdFilter()

    if upload:
      loadGlyphImage(imageId, fontId, figFont.typefaceId, image)
    return image
  except PixieError:
    return nil
