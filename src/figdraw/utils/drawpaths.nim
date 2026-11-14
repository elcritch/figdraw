## Reusable drawable line and stroke geometry helpers.
import std/math
import ../fignodes
import ../svgs/svgstrokes
export svgstrokes

proc drawableDashedLineOps*(
    a, b: Vec2, dashArray: openArray[float32], dashOffset: float32 = 0
): seq[DrawableOp] =
  ## Build disjoint line operations; distances are measured from `a`.
  ## Round or square caps can overlap when gaps are shorter than the stroke
  ## width, so translucent strokes should use a union outline in that case.
  let delta = b - a
  let length = sqrt(delta.x * delta.x + delta.y * delta.y)
  if length <= 0:
    return
  if dashArray.len == 0:
    return @[drawableLine(a, b)]
  var pattern = @dashArray
  if pattern.len mod 2 != 0:
    pattern.add(@dashArray)
  var total = 0'f32
  for d in pattern:
    if d < 0 or d.classify in {fcNan, fcInf, fcNegInf}:
      return
    total += d
  if total <= 0:
    return @[drawableLine(a, b)]
  if dashOffset.classify in {fcNan, fcInf, fcNegInf}:
    return
  var phase = dashOffset mod total
  if phase < 0:
    phase += total
  var index = 0
  while pattern[index] == 0 or phase >= pattern[index]:
    phase -= pattern[index]
    index = (index + 1) mod pattern.len
  var remaining = pattern[index] - phase
  var position = 0'f32
  while position < length:
    let next = min(length, position + remaining)
    if index mod 2 == 0 and next > position:
      result.add drawableLine(
        a + delta * (position / length), a + delta * (next / length)
      )
    position = next
    index = (index + 1) mod pattern.len
    while pattern[index] == 0:
      index = (index + 1) mod pattern.len
    remaining = pattern[index]

proc figDashedLine*(
    a, b: Vec2,
    stroke: RenderStroke,
    dashArray: openArray[float32],
    dashOffset: float32 = 0,
    zlevel: ZLevel = 0.ZLevel,
): Fig =
  ## Draw a dashed line. See `drawableDashedLineOps` for translucent caps.
  let half = max(0'f32, stroke.weight) / 2
  let bounds = rect(
    min(a.x, b.x) - half,
    min(a.y, b.y) - half,
    abs(b.x - a.x) + half * 2,
    abs(b.y - a.y) + half * 2,
  )
  result = Fig(kind: nkDrawable, screenBox: bounds, zlevel: zlevel, drawStroke: stroke)
  result.drawOps =
    drawableDashedLineOps(a - bounds.xy, b - bounds.xy, dashArray, dashOffset)

proc figLine*(a, b: Vec2, stroke: RenderStroke, zlevel: ZLevel = 0.ZLevel): Fig =
  ## Draw a line with an explicit stroke style.
  figDashedLine(a, b, stroke, [], 0, zlevel)
