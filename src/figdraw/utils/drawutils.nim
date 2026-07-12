import std/[hashes, math]

import ../commons
import ../fignodes

import pkg/chroma

when defined(figdrawNativeDynlib):
  {.pragma: nativeAbi, exportabi.}
else:
  {.pragma: nativeAbi.}

const DrawablePathEpsilon = 0.000001'f32

type
  DrawableBorderSegmentKind = enum
    dbsLine
    dbsArc

  DrawableBorderSegment = object
    length: float32
    case kind: DrawableBorderSegmentKind
    of dbsLine:
      a, b: Vec2
    of dbsArc:
      center: Vec2
      radius, startAngle, sweepAngle: float32

proc hash(v: Vec2): Hash =
  hash((v.x, v.y))

proc hash(radii: array[DirectionCorners, float32]): Hash =
  for r in radii:
    result = result !& hash(r)

proc clampRadii*(
    radii: array[DirectionCorners, float32], rect: Rect
): array[DirectionCorners, float32] =
  let maxRadius = min(rect.w / 2, rect.h / 2)
  result = radii
  for corner in DirectionCorners:
    result[corner] = max(1.0, min(radii[corner], maxRadius)).round()

proc cornersToSdfRadii*(radii: array[DirectionCorners, float32]): Vec4 =
  vec4(radii[dcBottomRight], radii[dcTopRight], radii[dcBottomLeft], radii[dcTopLeft])

proc getCircleBoxSizes*(
    radii: array[DirectionCorners, float32],
    blur: float32,
    spread: float32,
    weight: float32 = 0.0,
    width = float32.high(),
    height = float32.high(),
    innerShadow = false,
): tuple[maxRadius, sideSize, totalSize, padding, paddingOffset, inner, weightSize: int] =
  result.maxRadius = 0
  for r in radii:
    result.maxRadius = max(result.maxRadius, r.round().int)
  let ww = int(weight.round())
  let bw = width.round().int
  let bh = height.round().int
  let blur = round(1.5 * blur).int
  let spread = spread.round().int
  # let padding = max(spread + blur, result.maxRadius)
  let padding = spread + blur

  result.padding = padding
  result.paddingOffset = result.padding
  if innerShadow:
    result.sideSize = min(result.maxRadius + padding, min(bw, bh)).max(ww)
  else:
    result.sideSize = min(result.maxRadius, min(bw, bh)).max(ww)
  result.totalSize = 3 * result.sidesize + 3 * padding
  result.inner = 3 * result.sideSize
  result.weightSize = ww

proc roundedBoxCornerSizes*(
    cbs:
      tuple[
        maxRadius, sideSize, totalSize, padding, paddingOffset, inner, weightSize: int
      ],
    radii: array[DirectionCorners, float32],
    innerShadow: bool,
): array[DirectionCorners, tuple[radius, sideSize, inner, sideDelta, center: int]] =
  let ww = cbs.weightSize

  for corner in DirectionCorners:
    let dim =
      if innerShadow:
        max(cbs.maxRadius, cbs.paddingOffset)
      else:
        max(int(round(radii[corner])), ww)
    let sideSize = cbs.paddingOffset + dim
    let center = sideSize
    result[corner] = (
      radius: int(round(radii[corner])),
      sideSize: sideSize,
      inner: dim,
      sideDelta: cbs.sideSize - dim,
      center: center,
    )

func positiveMod(v, cycle: float32): float32 =
  if cycle <= DrawablePathEpsilon:
    return 0.0'f32
  result = v - floor(v / cycle) * cycle
  if result < 0.0'f32:
    result += cycle

func borderRadii(
    box: Rect, corners: array[DirectionCorners, uint16]
): array[DirectionCorners, float32] =
  let maxRadius = max(0.0'f32, min(box.w, box.h) * 0.5'f32)
  for corner in DirectionCorners:
    result[corner] = min(corners[corner].float32, maxRadius)

  let
    top = result[dcTopLeft] + result[dcTopRight]
    bottom = result[dcBottomLeft] + result[dcBottomRight]
    left = result[dcTopLeft] + result[dcBottomLeft]
    right = result[dcTopRight] + result[dcBottomRight]
  var scale = 1.0'f32
  if top > DrawablePathEpsilon:
    scale = min(scale, box.w / top)
  if bottom > DrawablePathEpsilon:
    scale = min(scale, box.w / bottom)
  if left > DrawablePathEpsilon:
    scale = min(scale, box.h / left)
  if right > DrawablePathEpsilon:
    scale = min(scale, box.h / right)
  if scale < 1.0'f32:
    for corner in DirectionCorners:
      result[corner] *= scale

proc addLineSegment(segments: var seq[DrawableBorderSegment], a, b: Vec2) =
  let length = sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
  if length > DrawablePathEpsilon:
    segments.add DrawableBorderSegment(kind: dbsLine, length: length, a: a, b: b)

proc addArcSegment(
    segments: var seq[DrawableBorderSegment],
    center: Vec2,
    radius, startAngle, sweepAngle: float32,
) =
  let length = abs(radius * sweepAngle)
  if radius > DrawablePathEpsilon and length > DrawablePathEpsilon:
    segments.add DrawableBorderSegment(
      kind: dbsArc,
      length: length,
      center: center,
      radius: radius,
      startAngle: startAngle,
      sweepAngle: sweepAngle,
    )

proc roundedRectBorderSegments(
    box: Rect, corners: array[DirectionCorners, uint16]
): seq[DrawableBorderSegment] =
  if box.w <= 0.0'f32 or box.h <= 0.0'f32:
    return

  let
    x0 = box.x
    y0 = box.y
    x1 = box.x + box.w
    y1 = box.y + box.h
    radii = borderRadii(box, corners)
    topLeft = radii[dcTopLeft]
    topRight = radii[dcTopRight]
    bottomLeft = radii[dcBottomLeft]
    bottomRight = radii[dcBottomRight]
    quarterTurn = PI.float32 * 0.5'f32

  result.addLineSegment(vec2(x0 + topLeft, y0), vec2(x1 - topRight, y0))
  result.addArcSegment(
    vec2(x1 - topRight, y0 + topRight), topRight, -quarterTurn, quarterTurn
  )
  result.addLineSegment(vec2(x1, y0 + topRight), vec2(x1, y1 - bottomRight))
  result.addArcSegment(
    vec2(x1 - bottomRight, y1 - bottomRight), bottomRight, 0.0'f32, quarterTurn
  )
  result.addLineSegment(vec2(x1 - bottomRight, y1), vec2(x0 + bottomLeft, y1))
  result.addArcSegment(
    vec2(x0 + bottomLeft, y1 - bottomLeft), bottomLeft, quarterTurn, quarterTurn
  )
  result.addLineSegment(vec2(x0, y1 - bottomLeft), vec2(x0, y0 + topLeft))
  result.addArcSegment(
    vec2(x0 + topLeft, y0 + topLeft), topLeft, PI.float32, quarterTurn
  )

func totalLength(segments: openArray[DrawableBorderSegment]): float32 =
  for segment in segments:
    result += segment.length

func linePoint(a, b: Vec2, t: float32): Vec2 =
  a + (b - a) * t

func arcPoint(segment: DrawableBorderSegment, distance: float32): Vec2 =
  let angle = segment.startAngle + segment.sweepAngle * (distance / segment.length)
  segment.center + vec2(cos(angle) * segment.radius, sin(angle) * segment.radius)

proc addBorderInterval(
    ops: var seq[DrawableOp],
    segment: DrawableBorderSegment,
    startDistance, stopDistance: float32,
) =
  let intervalLength = stopDistance - startDistance
  if intervalLength <= DrawablePathEpsilon:
    return

  case segment.kind
  of dbsLine:
    let
      startT = startDistance / segment.length
      stopT = stopDistance / segment.length
    ops.add drawableLine(
      linePoint(segment.a, segment.b, startT), linePoint(segment.a, segment.b, stopT)
    )
  of dbsArc:
    let
      startT = startDistance / segment.length
      stopT = stopDistance / segment.length
    ops.add drawableArc(
      segment.center,
      segment.radius,
      segment.startAngle + segment.sweepAngle * startT,
      segment.sweepAngle * (stopT - startT),
    )

proc addBorderInterval(
    ops: var seq[DrawableOp],
    segments: openArray[DrawableBorderSegment],
    startDistance, stopDistance: float32,
) =
  var segmentStart = 0.0'f32
  for segment in segments:
    let
      segmentStop = segmentStart + segment.length
      localStart = max(startDistance, segmentStart)
      localStop = min(stopDistance, segmentStop)
    if localStop > localStart + DrawablePathEpsilon:
      ops.addBorderInterval(
        segment, localStart - segmentStart, localStop - segmentStart
      )
    segmentStart = segmentStop

func pointAtDistance(
    segments: openArray[DrawableBorderSegment], distance: float32
): Vec2 =
  var segmentStart = 0.0'f32
  for segment in segments:
    let segmentStop = segmentStart + segment.length
    if distance <= segmentStop + DrawablePathEpsilon:
      let localDistance = clamp(distance - segmentStart, 0.0'f32, segment.length)
      case segment.kind
      of dbsLine:
        return linePoint(segment.a, segment.b, localDistance / segment.length)
      of dbsArc:
        return segment.arcPoint(localDistance)
    segmentStart = segmentStop

proc drawableRoundedRectBorderOps*(
    box: Rect, corners: array[DirectionCorners, uint16]
): seq[DrawableOp] =
  ## Returns solid border operations for a rounded rectangle perimeter.
  for segment in roundedRectBorderSegments(box, corners):
    case segment.kind
    of dbsLine:
      result.add drawableLine(segment.a, segment.b)
    of dbsArc:
      result.add drawableArc(
        segment.center, segment.radius, segment.startAngle, segment.sweepAngle
      )

proc drawableDashedRoundedRectBorderOps*(
    box: Rect,
    corners: array[DirectionCorners, uint16],
    dashLength, gapLength: float32,
    offset: float32 = 0.0'f32,
): seq[DrawableOp] =
  ## Returns line and arc operations for a dashed rounded-rectangle border.
  ##
  ## `dashLength`, `gapLength`, and `offset` are measured along the border path
  ## in the same local units as `box`.
  if dashLength <= DrawablePathEpsilon:
    return
  if gapLength <= DrawablePathEpsilon:
    return drawableRoundedRectBorderOps(box, corners)

  let
    segments = roundedRectBorderSegments(box, corners)
    pathLength = segments.totalLength()
    cycleLength = dashLength + gapLength
  if pathLength <= DrawablePathEpsilon or cycleLength <= DrawablePathEpsilon:
    return

  var
    distance = 0.0'f32
    phase = positiveMod(offset, cycleLength)
    drawing = phase < dashLength
    runRemaining =
      if drawing:
        dashLength - phase
      else:
        cycleLength - phase
  while distance < pathLength - DrawablePathEpsilon:
    let runStop = min(pathLength, distance + runRemaining)
    if drawing:
      result.addBorderInterval(segments, distance, runStop)
    distance = runStop
    drawing = not drawing
    runRemaining = if drawing: dashLength else: gapLength

proc drawableDottedRoundedRectBorderOps*(
    box: Rect,
    corners: array[DirectionCorners, uint16],
    dotRadius, gapLength: float32,
    offset: float32 = 0.0'f32,
): seq[DrawableOp] =
  ## Returns circle operations for a dotted rounded-rectangle border.
  ##
  ## `gapLength` is the distance between dot edges, not centers.
  if dotRadius <= DrawablePathEpsilon:
    return

  let
    segments = roundedRectBorderSegments(box, corners)
    pathLength = segments.totalLength()
    spacing = dotRadius * 2.0'f32 + max(0.0'f32, gapLength)
  if pathLength <= DrawablePathEpsilon or spacing <= DrawablePathEpsilon:
    return

  let phase = positiveMod(offset, spacing)
  var distance =
    if phase <= DrawablePathEpsilon:
      0.0'f32
    else:
      spacing - phase
  while distance < pathLength - DrawablePathEpsilon:
    result.add drawableCircle(segments.pointAtDistance(distance), dotRadius)
    distance += spacing

proc figDashedRoundedRectBorder*(
    box: Rect,
    corners: CornerRadii,
    fill: Fill,
    weight, dashLength, gapLength: float32,
    offset: float32 = 0.0'f32,
    cap: StrokeCap = scButt,
    zlevel: ZLevel = 0.ZLevel,
): Fig {.nativeAbi.} =
  ## Returns an `nkDrawable` dashed rounded-rectangle border.
  let
    halfWeight = max(0.0'f32, weight) * 0.5'f32
    bounds = rect(
      box.x - halfWeight,
      box.y - halfWeight,
      box.w + halfWeight * 2.0'f32,
      box.h + halfWeight * 2.0'f32,
    )
    localBox = rect(halfWeight, halfWeight, box.w, box.h)

  result = Fig(kind: nkDrawable)
  result.zlevel = zlevel
  result.screenBox = bounds
  result.fill = rgba(0, 0, 0, 0)
  result.drawStroke = RenderStroke(weight: weight, fill: fill, cap: cap)
  result.drawOps =
    drawableDashedRoundedRectBorderOps(localBox, corners, dashLength, gapLength, offset)

proc figRoundedRectBorder*(
    box: Rect,
    corners: CornerRadii,
    fill: Fill,
    weight: float32,
    cap: StrokeCap = scButt,
    zlevel: ZLevel = 0.ZLevel,
): Fig {.nativeAbi.} =
  ## Returns an `nkDrawable` solid rounded-rectangle border.
  let
    halfWeight = max(0.0'f32, weight) * 0.5'f32
    bounds = rect(
      box.x - halfWeight,
      box.y - halfWeight,
      box.w + halfWeight * 2.0'f32,
      box.h + halfWeight * 2.0'f32,
    )
    localBox = rect(halfWeight, halfWeight, box.w, box.h)

  result = Fig(kind: nkDrawable)
  result.zlevel = zlevel
  result.screenBox = bounds
  result.fill = rgba(0, 0, 0, 0)
  result.drawStroke = RenderStroke(weight: weight, fill: fill, cap: cap)
  result.drawOps = drawableRoundedRectBorderOps(localBox, corners)

proc figDottedRoundedRectBorder*(
    box: Rect,
    corners: CornerRadii,
    fill: Fill,
    weight, gapLength: float32,
    offset: float32 = 0.0'f32,
    zlevel: ZLevel = 0.ZLevel,
): Fig {.nativeAbi.} =
  ## Returns an `nkDrawable` dotted rounded-rectangle border.
  let
    dotRadius = max(0.0'f32, weight) * 0.5'f32
    bounds = rect(
      box.x - dotRadius,
      box.y - dotRadius,
      box.w + dotRadius * 2.0'f32,
      box.h + dotRadius * 2.0'f32,
    )
    localBox = rect(dotRadius, dotRadius, box.w, box.h)

  result = Fig(kind: nkDrawable)
  result.zlevel = zlevel
  result.screenBox = bounds
  result.fill = fill
  result.drawStroke = RenderStroke()
  result.drawOps =
    drawableDottedRoundedRectBorderOps(localBox, corners, dotRadius, gapLength, offset)
