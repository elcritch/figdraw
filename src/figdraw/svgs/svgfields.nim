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

proc generateSvgField*(
    path: Path,
    windingRule: WindingRule,
    documentScale, pixelRange: float64,
    strokeWidth = 0.0,
): SvgField =
  ## Stroke width is measured in SVG document coordinates. Reserve both the
  ## stroke width and the original range for the encoded distances and frame.
  let bounds = path.computeBounds()
  if bounds.w <= 0.0'f32 or bounds.h <= 0.0'f32:
    raise newException(PixieError, "SVG path has empty bounds")
  let
    range = pixelRange + max(0.0, strokeWidth) * documentScale
    minimumDimension = int(ceil(range + 1.0))
    width = max(minimumDimension, int(ceil(bounds.w.float64 * documentScale + range)))
    height = max(minimumDimension, int(ceil(bounds.h.float64 * documentScale + range)))
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
