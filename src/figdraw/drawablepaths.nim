import std/[algorithm, math]

import ./commons
import ./fignodes

const
  DrawableAdaptiveTolerancePx* = 0.5'f32
  MaxAdaptiveDrawableSteps* = max(DefaultDrawableBezierSteps.int * 4, 64)
  MaxAdaptiveCurveDepth* = 8
  PathGeometryEpsilon = 0.00001'f32

type
  DrawableTriangle* = array[3, Vec2]

  DrawableQuadraticBoundary* = object
    ## One quadratic boundary span and the side containing the path interior.
    ##
    ## `insideSign` is positive when the path is filled on the left side of
    ## the directed curve, and negative when it is filled on the right.
    p0*, p1*, p2*: Vec2
    insideSign*: float32

  PathEdge = object
    a, b: Vec2
    winding: int

  PathCrossing = object
    xTop, xMid, xBottom: float32
    winding: int

func vectorLength*(v: Vec2): float32 =
  sqrt(v.x * v.x + v.y * v.y)

func quadraticPoint(p0, p1, p2: Vec2, t: float32): Vec2 =
  let invT = 1.0'f32 - t
  p0 * (invT * invT) + p1 * (2.0'f32 * invT * t) + p2 * (t * t)

func pointsEqual(a, b: Vec2): bool =
  let delta = a - b
  delta.x * delta.x + delta.y * delta.y <= PathGeometryEpsilon * PathGeometryEpsilon

proc appendPoint(points: var seq[Vec2], point: Vec2) =
  if points.len == 0 or not points[^1].pointsEqual(point):
    points.add point

proc bezierPoint*(controls: openArray[Vec2], t: float32): Vec2 =
  if controls.len == 0:
    return vec2(0.0'f32, 0.0'f32)

  var work = newSeq[Vec2](controls.len)
  for idx, point in controls:
    work[idx] = point

  var count = controls.len
  while count > 1:
    for idx in 0 ..< count - 1:
      work[idx] = work[idx] * (1.0'f32 - t) + work[idx + 1] * t
    dec count
  work[0]

proc pointDistancePx*(a, b: Vec2): float32 =
  vectorLength((a - b).scaled())

func distanceToLine(point, a, b: Vec2): float32 =
  let
    ab = b - a
    denom = ab.x * ab.x + ab.y * ab.y
  if denom <= PathGeometryEpsilon:
    return vectorLength(point - a)

  let t = clamp(((point - a).x * ab.x + (point - a).y * ab.y) / denom, 0.0'f32, 1.0'f32)
  vectorLength(point - (a + ab * t))

proc distanceToLinePx(point, a, b: Vec2): float32 =
  distanceToLine(point.scaled(), a.scaled(), b.scaled())

proc appendAdaptiveBezierPoint(
    controls: openArray[Vec2], t0, t1: float32, depth: int, points: var seq[Vec2]
) =
  let
    p0 = bezierPoint(controls, t0)
    p1 = bezierPoint(controls, t1)
    tm = (t0 + t1) * 0.5'f32
    midpoint = bezierPoint(controls, tm)
    error = distanceToLinePx(midpoint, p0, p1)
  if error <= DrawableAdaptiveTolerancePx or depth >= MaxAdaptiveCurveDepth or
      points.len >= MaxAdaptiveDrawableSteps:
    points.add p1
  else:
    appendAdaptiveBezierPoint(controls, t0, tm, depth + 1, points)
    appendAdaptiveBezierPoint(controls, tm, t1, depth + 1, points)

func drawableStepCount*(steps, nodeSteps: uint16): int =
  if steps != 0'u16:
    max(1, steps.int)
  elif nodeSteps != 0'u16:
    max(1, nodeSteps.int)
  else:
    0

proc bezierSegmentPoints*(controls: openArray[Vec2], fixedSteps: int): seq[Vec2] =
  if controls.len < 2:
    return

  result.add bezierPoint(controls, 0.0'f32)
  if fixedSteps > 0:
    for step in 1 .. fixedSteps:
      result.add bezierPoint(controls, step.float32 / fixedSteps.float32)
  else:
    appendAdaptiveBezierPoint(controls, 0.0'f32, 1.0'f32, 0, result)

proc adaptiveArcStepCount*(radius, sweepAngle: float32): int =
  let
    radiusPx = max(0.0'f32, radius.scaled())
    absSweep = abs(sweepAngle)
  if radiusPx <= 0.0'f32 or absSweep <= 0.0'f32:
    return 1

  let
    cosLimit =
      clamp(1.0'f32 - DrawableAdaptiveTolerancePx / radiusPx, -1.0'f32, 1.0'f32)
    maxAngle = max(0.01'f32, 2.0'f32 * arccos(cosLimit))
  clamp(ceil(absSweep / maxAngle).int, 1, MaxAdaptiveDrawableSteps)

proc drawableArcStepCount*(radius, sweepAngle: float32, steps, nodeSteps: uint16): int =
  let explicit = drawableStepCount(steps, nodeSteps)
  if explicit > 0:
    explicit
  else:
    adaptiveArcStepCount(radius, sweepAngle)

func arcPoint*(center: Vec2, radius, angle: float32): Vec2 =
  center + vec2(cos(angle) * radius, sin(angle) * radius)

proc arcSegmentPoints*(
    center: Vec2, radius, startAngle, sweepAngle: float32, steps: int
): seq[Vec2] =
  if radius <= 0.0'f32 or sweepAngle == 0.0'f32 or steps <= 0:
    return

  for step in 0 .. steps:
    let angle = startAngle + sweepAngle * (step.float32 / steps.float32)
    result.add arcPoint(center, radius, angle)

proc flattenDrawableContour*(
    contour: DrawableContour, nodeSteps: uint16 = 0'u16
): seq[Vec2] =
  for segment in contour.segments:
    case segment.kind
    of dpsLine:
      result.appendPoint(segment.a)
      result.appendPoint(segment.b)
    of dpsBezier:
      let fixedSteps = drawableStepCount(segment.steps, nodeSteps)
      for point in bezierSegmentPoints(segment.controls, fixedSteps):
        result.appendPoint(point)
    of dpsArc:
      let steps = drawableArcStepCount(
        segment.arcRadius, segment.sweepAngle, segment.arcSteps, nodeSteps
      )
      for point in arcSegmentPoints(
        segment.arcCenter,
        max(0.0'f32, segment.arcRadius),
        segment.startAngle,
        segment.sweepAngle,
        steps,
      ):
        result.appendPoint(point)

  if result.len > 1 and result[0].pointsEqual(result[^1]):
    result.setLen(result.len - 1)

func quadraticSpan(
    controls: openArray[Vec2], t0, t2: float32
): DrawableQuadraticBoundary =
  let
    tm = (t0 + t2) * 0.5'f32
    p0 = bezierPoint(controls, t0)
    midpoint = bezierPoint(controls, tm)
    p2 = bezierPoint(controls, t2)
    p1 = midpoint * 2.0'f32 - (p0 + p2) * 0.5'f32
  DrawableQuadraticBoundary(p0: p0, p1: p1, p2: p2)

proc appendAdaptiveQuadraticSpans(
    controls: openArray[Vec2],
    t0, t2: float32,
    depth: int,
    spans: var seq[DrawableQuadraticBoundary],
) =
  let
    span = quadraticSpan(controls, t0, t2)
    midpoint = quadraticPoint(span.p0, span.p1, span.p2, 0.5'f32)
    error = distanceToLinePx(midpoint, span.p0, span.p2)
  if error <= DrawableAdaptiveTolerancePx or depth >= MaxAdaptiveCurveDepth or
      spans.len >= MaxAdaptiveDrawableSteps - 1:
    spans.add span
  else:
    let tm = (t0 + t2) * 0.5'f32
    appendAdaptiveQuadraticSpans(controls, t0, tm, depth + 1, spans)
    appendAdaptiveQuadraticSpans(controls, tm, t2, depth + 1, spans)

proc quadraticSpans(
    controls: openArray[Vec2], fixedSteps: int
): seq[DrawableQuadraticBoundary] =
  if fixedSteps > 0:
    for step in 0 ..< fixedSteps:
      result.add quadraticSpan(
        controls,
        step.float32 / fixedSteps.float32,
        (step + 1).float32 / fixedSteps.float32,
      )
  else:
    appendAdaptiveQuadraticSpans(controls, 0.0'f32, 1.0'f32, 0, result)

func pointInDrawablePath(
    contours: openArray[seq[Vec2]], fillRule: DrawableFillRule, point: Vec2
): bool =
  var
    winding = 0
    parity = false
  for contour in contours:
    if contour.len >= 3:
      for idx in 0 ..< contour.len:
        let
          a = contour[idx]
          b = contour[(idx + 1) mod contour.len]
          crosses =
            (a.y <= point.y and b.y > point.y) or (b.y <= point.y and a.y > point.y)
        if crosses:
          let x = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
          if x > point.x:
            case fillRule
            of dfrNonZero:
              winding += (if b.y > a.y: 1 else: -1)
            of dfrEvenOdd:
              parity = not parity

  case fillRule
  of dfrNonZero:
    winding != 0
  of dfrEvenOdd:
    parity

func normalizedBoundaryNormal(span: DrawableQuadraticBoundary): Vec2 =
  let
    tangent = span.p2 - span.p0
    length = vectorLength(tangent)
  if length <= PathGeometryEpsilon:
    vec2(0.0'f32, 1.0'f32)
  else:
    vec2(-tangent.y / length, tangent.x / length)

proc boundaryInsideSign(
    span: DrawableQuadraticBoundary,
    contours: openArray[seq[Vec2]],
    fillRule: DrawableFillRule,
): float32 =
  let
    midpoint = quadraticPoint(span.p0, span.p1, span.p2, 0.5'f32)
    normal = span.normalizedBoundaryNormal()
  for offsetPx in [1.5'f32, 0.5'f32, 3.0'f32]:
    let
      offset = normal * offsetPx.descaled()
      leftInside = pointInDrawablePath(contours, fillRule, midpoint + offset)
      rightInside = pointInDrawablePath(contours, fillRule, midpoint - offset)
    if leftInside != rightInside:
      return (if leftInside: 1.0'f32 else: -1.0'f32)

  0.0'f32

proc drawablePathQuadraticBoundaries*(
    path: DrawablePath, nodeSteps: uint16 = 0'u16
): seq[DrawableQuadraticBoundary] =
  ## Returns quadratic boundary spans suitable for an analytic fill fringe.
  ##
  ## The subdivision endpoints match the line segments used by adaptive path
  ## flattening. Generic and arc segments remain polygonal in this first pass.
  var flattened = newSeq[seq[Vec2]](path.contours.len)
  for idx, contour in path.contours:
    flattened[idx] = flattenDrawableContour(contour, nodeSteps)

  for contour in path.contours:
    for segment in contour.segments:
      if segment.kind == dpsBezier and segment.controls.len == 3:
        let fixedSteps = drawableStepCount(segment.steps, nodeSteps)
        for span in quadraticSpans(segment.controls, fixedSteps):
          if not pointsEqual(span.p0, span.p2):
            var boundary = span
            boundary.insideSign = boundaryInsideSign(span, flattened, path.fillRule)
            if abs(boundary.insideSign) > PathGeometryEpsilon:
              result.add boundary

proc addContourEdges(points: openArray[Vec2], edges: var seq[PathEdge]) =
  if points.len < 3:
    return

  for idx in 0 ..< points.len:
    let
      a = points[idx]
      b = points[(idx + 1) mod points.len]
      deltaY = b.y - a.y
    if abs(deltaY) > PathGeometryEpsilon:
      edges.add PathEdge(a: a, b: b, winding: (if deltaY > 0.0'f32: 1 else: -1))

proc sortedUnique(values: var seq[float32]) =
  values.sort()
  var write = 0
  for value in values:
    if write == 0 or abs(value - values[write - 1]) > PathGeometryEpsilon:
      values[write] = value
      inc write
  values.setLen(write)

func edgeXAt(edge: PathEdge, y: float32): float32 =
  let t = (y - edge.a.y) / (edge.b.y - edge.a.y)
  edge.a.x + (edge.b.x - edge.a.x) * t

proc addTriangle(triangles: var seq[DrawableTriangle], a, b, c: Vec2) =
  let area2 = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if abs(area2) > PathGeometryEpsilon:
    triangles.add [a, b, c]

proc addSpanTriangles(
    triangles: var seq[DrawableTriangle],
    left, right: PathCrossing,
    yTop, yBottom: float32,
) =
  let
    topLeft = vec2(left.xTop, yTop)
    topRight = vec2(right.xTop, yTop)
    bottomRight = vec2(right.xBottom, yBottom)
    bottomLeft = vec2(left.xBottom, yBottom)
  triangles.addTriangle(topLeft, topRight, bottomRight)
  triangles.addTriangle(topLeft, bottomRight, bottomLeft)

proc triangulateDrawablePath*(
    path: DrawablePath, nodeSteps: uint16 = 0'u16
): seq[DrawableTriangle] =
  ## Flattens the path and decomposes its filled scanline spans into triangles.
  ##
  ## Contours are implicitly closed. Both fill rules support concave simple
  ## contours, nested contours, and holes. Self-intersecting edges are not split
  ## at their intersection, so callers should currently provide simple contours.
  var
    edges: seq[PathEdge]
    levels: seq[float32]
  for contour in path.contours:
    let points = flattenDrawableContour(contour, nodeSteps)
    if points.len >= 3:
      for point in points:
        levels.add point.y
      addContourEdges(points, edges)

  levels.sortedUnique()
  if levels.len < 2 or edges.len < 2:
    return

  for level in 0 ..< levels.len - 1:
    let
      yTop = levels[level]
      yBottom = levels[level + 1]
      yMid = (yTop + yBottom) * 0.5'f32
    if yBottom - yTop > PathGeometryEpsilon:
      var crossings: seq[PathCrossing]
      for edge in edges:
        let
          minY = min(edge.a.y, edge.b.y)
          maxY = max(edge.a.y, edge.b.y)
        if yMid > minY and yMid < maxY:
          crossings.add PathCrossing(
            xTop: edge.edgeXAt(yTop),
            xMid: edge.edgeXAt(yMid),
            xBottom: edge.edgeXAt(yBottom),
            winding: edge.winding,
          )

      crossings.sort(
        proc(a, b: PathCrossing): int =
          cmp(a.xMid, b.xMid)
      )

      var
        at = 0
        winding = 0
        parity = false
        left: PathCrossing
      while at < crossings.len:
        let groupStart = at
        var windingDelta = 0
        while at < crossings.len and
            abs(crossings[at].xMid - crossings[groupStart].xMid) <= PathGeometryEpsilon:
          windingDelta += crossings[at].winding
          inc at

        let wasFilled =
          case path.fillRule
          of dfrNonZero:
            winding != 0
          of dfrEvenOdd:
            parity

        case path.fillRule
        of dfrNonZero:
          winding += windingDelta
        of dfrEvenOdd:
          if (at - groupStart) mod 2 == 1:
            parity = not parity

        let isFilled =
          case path.fillRule
          of dfrNonZero:
            winding != 0
          of dfrEvenOdd:
            parity

        if not wasFilled and isFilled:
          left = crossings[groupStart]
        elif wasFilled and not isFilled:
          result.addSpanTriangles(left, crossings[groupStart], yTop, yBottom)
