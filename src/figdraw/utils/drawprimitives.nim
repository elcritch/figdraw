## Convenient nodes for common drawable primitives.
import ../fignodes

proc figEllipse*(
    bounds: Rect, fillValue: Fill, stroke: RenderStroke = RenderStroke()
): Fig =
  ## Construct an ellipse whose path follows `bounds`. After changing its stroke
  ## weight or geometry, call `prepareDrawableStroke` before rendering.
  var op = drawableEllipse(bounds.wh * 0.5'f32, bounds.wh * 0.5'f32)
  op.centeredStroke = true
  result = Fig(
    kind: nkDrawable,
    screenBox: bounds,
    fill: fillValue,
    drawStroke: stroke,
    drawOps: @[op],
  )
  result.prepareDrawableStroke()

proc figCircle*(
    bounds: Rect, fillValue: Fill, stroke: RenderStroke = RenderStroke()
): Fig =
  ## Construct a centered circle using the smaller dimension of `bounds`.
  ## After changing its stroke weight or geometry, call `prepareDrawableStroke`.
  var op = drawableCircle(bounds.wh * 0.5'f32, min(bounds.w, bounds.h) * 0.5'f32)
  op.centeredStroke = true
  result = Fig(
    kind: nkDrawable,
    screenBox: bounds,
    fill: fillValue,
    drawStroke: stroke,
    drawOps: @[op],
  )
  result.prepareDrawableStroke()
