import ./fignodes

proc figLine*(a, b: Vec2, fill: Fill, weight: float32, zlevel: ZLevel = 0.ZLevel): Fig =
  let
    delta = b - a
    halfWeight = max(0.0'f32, weight) / 2.0'f32
    bounds = rect(
      min(a.x, b.x) - halfWeight,
      min(a.y, b.y) - halfWeight,
      abs(delta.x) + halfWeight * 2.0'f32,
      abs(delta.y) + halfWeight * 2.0'f32,
    )

  result = Fig(kind: nkDrawable)
  result.zlevel = zlevel
  result.screenBox = bounds
  result.fill = fill
  result.drawStroke = RenderStroke(weight: weight, fill: fill)
  result.drawOps.add drawableLine(a - bounds.xy, b - bounds.xy)

proc figLine*(
    x1: float32,
    y1: float32,
    x2: float32,
    y2: float32,
    fill: Fill,
    weight: float32,
    zlevel: ZLevel = 0.ZLevel,
): Fig =
  figLine(vec2(x1, y1), vec2(x2, y2), fill, weight, zlevel)

proc figCircle*(
    center: Vec2, fill: Fill, radius: float32, zlevel: ZLevel = 0.ZLevel
): Fig =
  let
    clampedRadius = max(0.0'f32, radius)
    diameter = clampedRadius * 2.0'f32

  result = Fig(kind: nkDrawable)
  result.zlevel = zlevel
  result.fill = fill
  result.screenBox =
    rect(center.x - clampedRadius, center.y - clampedRadius, diameter, diameter)
  result.drawOps.add drawableCircle(vec2(clampedRadius, clampedRadius), clampedRadius)

proc figCircle*(
    x1: float32, y1: float32, fill: Fill, radius: float32, zlevel: ZLevel = 0.ZLevel
): Fig =
  figCircle(vec2(x1, y1), fill, radius, zlevel)
