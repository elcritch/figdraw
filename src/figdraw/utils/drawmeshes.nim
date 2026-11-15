## Convert convex stroke outline pieces to filled drawable operations.
import pkg/pixie/paths
import ../fignodes
from ../svgs/svgflatten import flattenSvgPath

proc regularCircle(
    points: openArray[Vec2], count: int, center: var Vec2, radius: var float32
): bool =
  if count < 12:
    return false
  center = vec2(0, 0)
  for i in 0 ..< count:
    center += points[i]
  center /= count.float32
  radius = (points[0] - center).length
  if radius <= 0:
    return false
  let chord = (points[1] - points[0]).length
  for i in 0 ..< count:
    if abs((points[i] - center).length - radius) > radius * 0.001'f32 or
        abs((points[(i + 1) mod count] - points[i]).length - chord) > radius * 0.001'f32:
      return false
  true

proc drawableStrokeOutlineOps*(outline: Path): seq[DrawableOp] =
  ## Convert the convex, same-winding contours made by `strokeOutline`.
  ## Regular circular contours become filled circle primitives.
  ## These operations overlap and are intended for opaque fills. This is not a
  ## general triangulator: arbitrary concave contours and holes are unsupported.
  if outline.isNil:
    return
  for points in flattenSvgPath($outline):
    let count = points.len - (if points.len > 1 and points[0] == points[^1]: 1 else: 0)
    var center: Vec2
    var radius: float32
    if regularCircle(points, count, center, radius):
      result.add drawableCircle(center, radius)
    elif count == 4:
      result.add drawableFilledQuad([points[0], points[1], points[2], points[3]])
    elif count >= 3:
      for i in 1 ..< count - 1:
        result.add drawableFilledQuad(
          [points[0], points[i], points[i + 1], points[i + 1]]
        )
