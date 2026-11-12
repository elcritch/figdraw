## Convenient nodes for common drawable primitives.
import ../fignodes

proc figEllipse*(
    bounds: Rect, fillValue: Fill, stroke: RenderStroke = RenderStroke()
): Fig =
  ## Construct an ellipse whose outer path follows `bounds`.
  var op = drawableEllipse(bounds.wh * 0.5'f32, bounds.wh * 0.5'f32)
  op.centeredStroke = true
  Fig(
    kind: nkDrawable,
    screenBox: bounds,
    fill: fillValue,
    drawStroke: stroke,
    drawOps: @[op],
  )

proc figCircle*(
    bounds: Rect, fillValue: Fill, stroke: RenderStroke = RenderStroke()
): Fig =
  ## Construct a centered circle using the smaller dimension of `bounds`.
  var op = drawableCircle(bounds.wh * 0.5'f32, min(bounds.w, bounds.h) * 0.5'f32)
  op.centeredStroke = true
  Fig(
    kind: nkDrawable,
    screenBox: bounds,
    fill: fillValue,
    drawStroke: stroke,
    drawOps: @[op],
  )
