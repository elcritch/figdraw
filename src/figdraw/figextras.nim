import std/math

import ./fignodes

proc figLine*(a, b: Vec2, fill: Fill, weight: float32, zlevel: ZLevel = 0.ZLevel): Fig =
  let
    delta = b - a
    length = sqrt(delta.x * delta.x + delta.y * delta.y)
    center = (a + b) / 2.0'f32

  result = Fig(kind: nkRectangle)
  result.zlevel = zlevel
  result.screenBox =
    rect(center.x - length / 2.0'f32, center.y - weight / 2.0'f32, length, weight)
  result.rotation = arctan2(delta.y, delta.x).float32 * 180.0'f32 / PI.float32
  result.fill = fill

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
