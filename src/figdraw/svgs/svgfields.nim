## Distance fields for SVG paths, adapted from Merenda.
## Covered by FigDraw's MIT license.

import std/math
import pkg/pixie
import pkg/sdfy/msdfgen

type SvgField* = object
  image*: Image
  frame*: Rect
  pixelRange*: float32

proc correctMtsdfSign(
    image: Image,
    path: Path,
    windingRule: WindingRule,
    fieldScale: float32,
    fieldTranslation: Vec2,
) =
  let mask = newImage(image.width, image.height)
  mask.fillPath(
    path,
    color(1.0, 1.0, 1.0, 1.0),
    translate(fieldTranslation * fieldScale) * scale(vec2(fieldScale)),
    windingRule,
  )
  for index in 0 ..< image.data.len:
    if (image.data[index].a >= 128) != (mask.data[index].a >= 128):
      image.data[index].a = 255 - image.data[index].a

proc adaptiveFieldScale(
    path: Path, windingRule: WindingRule, bounds: Rect, documentScale: float64
): float64 =
  # Estimate average feature width from area / perimeter at twice the base
  # resolution. This cheap raster probe avoids generating candidate MTSDFs.
  let probeScale = documentScale.float32 * 2
  let mask = newImage(
    max(3, int(ceil(bounds.w * probeScale)) + 2),
    max(3, int(ceil(bounds.h * probeScale)) + 2),
  )
  mask.fillPath(
    path,
    color(1, 1, 1, 1),
    translate(vec2(1) - bounds.xy * probeScale) * scale(vec2(probeScale)),
    windingRule,
  )
  var area, perimeter: float64
  for y in 0 ..< mask.height:
    for x in 0 ..< mask.width:
      let a = mask[x, y].a.float64 / 255
      area += a
      if x > 0:
        perimeter += abs(a - mask[x - 1, y].a.float64 / 255)
      if y > 0:
        perimeter += abs(a - mask[x, y - 1].a.float64 / 255)
  # Two texels across an average narrow feature, at most four times the
  # requested scale. Quantized tiers keep resource sizes predictable.
  result = documentScale
  if perimeter > 0:
    let width = area / perimeter # 2 * area / perimeter, in base texels
    if width < 1:
      result *= 4
    elif width < 2:
      result *= 2

proc generateSvgField*(
    path: Path,
    windingRule: WindingRule,
    documentScale, pixelRange: float64,
    strokeWidth = 0.0,
    adaptive = true,
): SvgField =
  ## Stroke width is measured in SVG document coordinates. Reserve both the
  ## stroke width and the original range for the encoded distances and frame.
  ## Adaptive fields use up to 4x the document scale for narrow paths.
  let bounds = path.computeBounds()
  if bounds.w <= 0.0'f32 or bounds.h <= 0.0'f32:
    raise newException(PixieError, "SVG path has empty bounds")
  let
    fieldDocumentScale =
      if adaptive:
        adaptiveFieldScale(path, windingRule, bounds, documentScale)
      else:
        documentScale
    range = pixelRange + max(0.0, strokeWidth) * fieldDocumentScale
    minimumDimension = int(ceil(range + 1.0))
    width =
      max(minimumDimension, int(ceil(bounds.w.float64 * fieldDocumentScale + range)))
    height =
      max(minimumDimension, int(ceil(bounds.h.float64 * fieldDocumentScale + range)))
    field = generateMtsdfPath(path, width, height, range)
    fieldScale = field.scale.float32
  field.image.flipVertical()
  field.image.correctMtsdfSign(
    path,
    windingRule,
    fieldScale,
    vec2(field.translate.x.float32, field.translate.y.float32),
  )
  SvgField(
    image: field.image,
    frame: rect(
      (-field.translate.x).float32,
      (-field.translate.y).float32,
      width.float32 / fieldScale,
      height.float32 / fieldScale,
    ),
    pixelRange: (field.range * field.scale).float32,
  )
