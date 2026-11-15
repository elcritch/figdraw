import std/math
import pixie/paths
import vmath
from svgflatten import flattenSvgPath

type StrokeRun = object
  points: seq[Vec2]
  closed: bool
  tangent: Vec2

proc dashRuns(
    points: seq[Vec2], pattern: seq[float32], offset: float32
): seq[StrokeRun] =
  if points.len == 0:
    return
  if pattern.len == 0:
    return
      @[StrokeRun(points: points, closed: points.len > 1 and points[0] == points[^1])]
  var dash = pattern
  if dash.len mod 2 != 0:
    dash.add(pattern)
  var total = 0'f32
  for d in dash:
    if d < 0 or d.classify in {fcNan, fcInf, fcNegInf}:
      return
    total += d
  if total <= 0:
    return
      @[StrokeRun(points: points, closed: points.len > 1 and points[0] == points[^1])]
  if offset.classify in {fcNan, fcInf, fcNegInf}:
    return
  var phase = offset mod total
  if phase < 0:
    phase += total
  var index = 0
  while dash[index] == 0 or phase >= dash[index]:
    if dash[index] == 0 and index mod 2 == 0 and phase == 0:
      let tangent =
        if points.len > 1:
          (points[1] - points[0]).normalize()
        else:
          vec2(1, 0)
      result.add StrokeRun(points: @[points[0]], tangent: tangent)
    phase -= dash[index]
    index = (index + 1) mod dash.len
  if points.len == 1:
    if index mod 2 == 0:
      result.add StrokeRun(points: points, tangent: vec2(1, 0))
    return
  var remain = dash[index] - phase
  var run: seq[Vec2]
  for i in 1 ..< points.len:
    let delta = points[i] - points[i - 1]
    let length = delta.length
    if length > 0:
      let direction = delta / length
      var at = points[i - 1]
      var left = length
      while left > 0.00001:
        let step = min(left, remain)
        let next =
          if step >= left:
            points[i]
          else:
            at + direction * step
        if index mod 2 == 0:
          if run.len == 0:
            run.add(at)
          run.add(next)
        at = next
        left -= step
        remain -= step
        if remain <= 0.00001:
          if index mod 2 == 0 and run.len > 1:
            result.add StrokeRun(points: run)
            run = @[]
          index = (index + 1) mod dash.len
          while dash[index] == 0:
            if index mod 2 == 0:
              result.add StrokeRun(points: @[at], tangent: direction)
            index = (index + 1) mod dash.len
          remain = dash[index]
  if run.len > 1:
    result.add StrokeRun(points: run)
  if points[0] == points[^1] and result.len > 0:
    if result.len == 1 and result[0].points[0] == result[0].points[^1]:
      result[0].closed = true
    elif result.len > 1 and result[0].points[0] == points[0] and
        result[^1].points[^1] == points[0]:
      var merged = result[^1].points
      merged.add(result[0].points[1 ..^ 1])
      result[0].points = merged
      result.setLen(result.len - 1)

proc addPolygon(path: Path, points: openArray[Vec2]) =
  if points.len < 3:
    return
  var area = 0'f32
  for i in 0 ..< points.len:
    let a = points[i]
    let b = points[(i + 1) mod points.len]
    area += a.x * b.y - b.x * a.y
  if abs(area) < 0.000001:
    return
  if area > 0:
    path.moveTo(points[0].x, points[0].y)
    for i in 1 ..< points.len:
      path.lineTo(points[i].x, points[i].y)
  else:
    path.moveTo(points[^1].x, points[^1].y)
    for i in countdown(points.len - 2, 0):
      path.lineTo(points[i].x, points[i].y)
  path.closePath()

proc addCircle(path: Path, p: Vec2, radius: float32) =
  # Use polygons with the same winding as all other stroke pieces.
  var points: seq[Vec2]
  let count = max(16, min(128, int(ceil(2 * PI * radius / 0.5))))
  for i in 0 ..< count:
    let angle = 2 * PI.float32 * i.float32 / count.float32
    points.add p + vec2(cos(angle), sin(angle)) * radius
  path.addPolygon(points)

proc normal(v: Vec2): Vec2 =
  vec2(-v.y, v.x)

proc cross(a, b: Vec2): float32 =
  a.x * b.y - a.y * b.x

proc addJoin(
    path: Path, a, b, c: Vec2, half: float32, join: LineJoin, miterLimit: float32
) =
  let u = (b - a).normalize()
  let v = (c - b).normalize()
  let turn = cross(u, v)
  if abs(turn) < 0.000001:
    if dot(u, v) < 0 and join == RoundJoin:
      path.addCircle(b, half)
    return
  if join == RoundJoin:
    path.addCircle(b, half)
    return
  let side = if turn > 0: -1'f32 else: 1'f32
  let p = b + normal(u) * (half * side)
  let q = b + normal(v) * (half * side)
  if join == MiterJoin:
    let t = cross(q - p, v) / turn
    let tip = p + u * t
    if (tip - b).length <= max(1'f32, miterLimit) * half:
      path.addPolygon([b, p, tip, q])
      return
  path.addPolygon([b, p, q])

proc strokeOutline*(
    path: Path,
    width: float32,
    cap: LineCap,
    join: LineJoin,
    miterLimit: float32,
    dashes: seq[float32],
    dashOffset: float32,
): Path =
  ## Convert a local-coordinate SVG stroke to same-winding filled contours.
  result = newPath()
  if path.isNil or width <= 0 or width.classify in {fcNan, fcInf, fcNegInf}:
    return
  let half = width / 2
  for points in flattenSvgPath($path):
    for run in dashRuns(points, dashes, dashOffset):
      let ps = run.points
      if ps.len == 1:
        case cap
        of ButtCap:
          discard
        of RoundCap:
          result.addCircle(ps[0], half)
        of SquareCap:
          let tangent =
            if run.tangent == vec2(0, 0):
              vec2(1, 0)
            else:
              run.tangent
          let a = tangent * half
          let b = normal(tangent) * half
          result.addPolygon(
            [ps[0] - a - b, ps[0] + a - b, ps[0] + a + b, ps[0] - a + b]
          )
      else:
        for i in 1 ..< ps.len:
          let dir = (ps[i] - ps[i - 1]).normalize()
          let n = normal(dir) * half
          result.addPolygon([ps[i - 1] + n, ps[i] + n, ps[i] - n, ps[i - 1] - n])
        for i in 1 ..< ps.len - 1:
          result.addJoin(ps[i - 1], ps[i], ps[i + 1], half, join, miterLimit)
        if run.closed:
          result.addJoin(ps[^2], ps[0], ps[1], half, join, miterLimit)
        else:
          case cap
          of ButtCap:
            discard
          of RoundCap:
            result.addCircle(ps[0], half)
            result.addCircle(ps[^1], half)
          of SquareCap:
            let first = (ps[1] - ps[0]).normalize() * half
            let last = (ps[^1] - ps[^2]).normalize() * half
            let a = normal(first)
            let b = normal(last)
            result.addPolygon(
              [ps[0] + a, ps[0] - a, ps[0] - a - first, ps[0] + a - first]
            )
            result.addPolygon(
              [ps[^1] + b, ps[^1] - b, ps[^1] - b + last, ps[^1] + b + last]
            )
