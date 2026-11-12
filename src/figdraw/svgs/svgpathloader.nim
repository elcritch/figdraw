# SPDX-License-Identifier: Apache-2.0
# Imported from Merenda; adapted from sdfy/src/sdfy/msdfgenSvg.nim.
# See docs/licenses/SVG-SOURCES.md for provenance and license notices.

## Parses SVG documents into paths and vector stroke metadata.

import std/[math, strutils]

import pkg/pixie
include pixie/fileformats/svg

type
  SvgSourceElementKind* = enum
    sekPath
    sekLine
    sekPolyline
    sekPolygon
    sekRectangle
    sekCircle
    sekEllipse

  SvgStrokeCap* = enum
    sscButt
    sscRound
    sscSquare

  SvgStrokeJoin* = enum
    ssjMiter
    ssjRound
    ssjBevel

  SvgStrokeSegmentKind* = enum
    sskLine
    sskQuadratic
    sskCubic

  SvgStrokeSegment* = object
    kind*: SvgStrokeSegmentKind
    start*, control1*, control2*, stop*: Vec2

  SvgAffine* = object
    a*, b*, c*, d*, tx*, ty*: float32

  ParsedSvgElement* = object
    kind*: SvgSourceElementKind
    fillPath*: Path
    hasFill*, hasStroke*: bool
    fillColor*, strokeColor*: Color
    fillRule*: WindingRule
    strokeSegments*: seq[SvgStrokeSegment]
    strokeWidth*: float32
    strokeCap*: SvgStrokeCap
    strokeJoin*: SvgStrokeJoin
    primitiveTransform*: SvgAffine
    primitiveStrokeWidth*: float32

  ParsedSvgDocument* = object
    width*, height*: int
    elements*: seq[ParsedSvgElement]

proc normalizeSvgData(data: string): string =
  result = data.replace(",", " ")
  let
    key = "viewBox=\""
    start = result.find(key)
  if start < 0:
    return

  let
    valueStart = start + key.len
    valueEnd = result.find('"', valueStart)
  if valueEnd < 0:
    return

  let
    viewBox = result[valueStart ..< valueEnd]
    parts = viewBox.splitWhitespace()
  if parts.len != 4:
    return

  var
    fixed = parts
    updated = false
  for index in 0 ..< fixed.len:
    if fixed[index].contains('.'):
      let value =
        try:
          parseFloat(fixed[index])
        except ValueError:
          return
      fixed[index] = $int(round(value))
      updated = true

  if updated:
    let normalizedViewBox = fixed.join(" ")
    result = result[0 ..< valueStart] & normalizedViewBox & result[valueEnd .. ^1]

proc collectElementKinds(node: XmlNode, kinds: var seq[SvgSourceElementKind]) =
  if node.kind != xnElement:
    return

  case node.tag
  of "g":
    for child in node:
      collectElementKinds(child, kinds)
  of "path":
    kinds.add sekPath
  of "line":
    kinds.add sekLine
  of "polyline":
    kinds.add sekPolyline
  of "polygon":
    kinds.add sekPolygon
  of "rect":
    kinds.add sekRectangle
  of "circle":
    kinds.add sekCircle
  of "ellipse":
    kinds.add sekEllipse
  else:
    discard

proc affine(matrix: Mat3): SvgAffine =
  SvgAffine(
    a: matrix[0, 0],
    b: matrix[0, 1],
    c: matrix[1, 0],
    d: matrix[1, 1],
    tx: matrix[2, 0],
    ty: matrix[2, 1],
  )

proc transformScale(matrix: Mat3): float32 =
  max(
    sqrt(matrix[0, 0] * matrix[0, 0] + matrix[0, 1] * matrix[0, 1]),
    sqrt(matrix[1, 0] * matrix[1, 0] + matrix[1, 1] * matrix[1, 1]),
  )

proc readNumber(data: string, index: var int): float32 =
  while index < data.len and data[index].isSpaceAscii:
    inc index
  let start = index
  while index < data.len and not data[index].isSpaceAscii:
    inc index
  if start == index:
    raise newException(PixieError, "Invalid normalized SVG path")
  try:
    parseFloat(data[start ..< index])
  except ValueError:
    raise newException(PixieError, "Invalid normalized SVG path number")

proc addArcAsCubics(
    path: Path,
    start: Vec2,
    rawRadii: Vec2,
    rotation: float32,
    largeArc, sweep: bool,
    stop: Vec2,
) =
  ## Converts an SVG endpoint arc to cubic Beziers using the SVG 1.1 formula.
  if start == stop:
    return

  var radii = vec2(abs(rawRadii.x), abs(rawRadii.y))
  if radii.x == 0.0'f32 or radii.y == 0.0'f32:
    path.lineTo(stop)
    return

  let
    angle = rotation / 180.0'f32 * PI
    cosAngle = cos(angle)
    sinAngle = sin(angle)
    midpointDelta = (start - stop) * 0.5'f32
    transformedStart = vec2(
      cosAngle * midpointDelta.x + sinAngle * midpointDelta.y,
      -sinAngle * midpointDelta.x + cosAngle * midpointDelta.y,
    )
    radiusScale =
      transformedStart.x * transformedStart.x / (radii.x * radii.x) +
      transformedStart.y * transformedStart.y / (radii.y * radii.y)
  if radiusScale > 1.0'f32:
    radii *= sqrt(radiusScale)

  let
    radiiSquared = vec2(radii.x * radii.x, radii.y * radii.y)
    startSquared = vec2(
      transformedStart.x * transformedStart.x, transformedStart.y * transformedStart.y
    )
    denominator = radiiSquared.x * startSquared.y + radiiSquared.y * startSquared.x
    numerator = max(0.0'f32, radiiSquared.x * radiiSquared.y - denominator)
    direction = if largeArc == sweep: -1.0'f32 else: 1.0'f32
    centerScale =
      if denominator == 0.0'f32:
        0.0'f32
      else:
        direction * sqrt(numerator / denominator)
    transformedCenter = vec2(
      centerScale * radii.x * transformedStart.y / radii.y,
      -centerScale * radii.y * transformedStart.x / radii.x,
    )
    center = vec2(
      cosAngle * transformedCenter.x - sinAngle * transformedCenter.y +
        (start.x + stop.x) * 0.5'f32,
      sinAngle * transformedCenter.x + cosAngle * transformedCenter.y +
        (start.y + stop.y) * 0.5'f32,
    )
    startVector = vec2(
      (transformedStart.x - transformedCenter.x) / radii.x,
      (transformedStart.y - transformedCenter.y) / radii.y,
    )
    stopVector = vec2(
      (-transformedStart.x - transformedCenter.x) / radii.x,
      (-transformedStart.y - transformedCenter.y) / radii.y,
    )
  var
    startAngle = arctan2(startVector.y, startVector.x)
    sweepAngle = arctan2(
      startVector.x * stopVector.y - startVector.y * stopVector.x,
      startVector.x * stopVector.x + startVector.y * stopVector.y,
    )
  if sweep and sweepAngle < 0.0'f32:
    sweepAngle += 2.0'f32 * PI
  elif not sweep and sweepAngle > 0.0'f32:
    sweepAngle -= 2.0'f32 * PI

  let
    segmentCount = max(1, int(ceil(abs(sweepAngle) / (PI * 0.5'f32))))
    segmentAngle = sweepAngle / segmentCount.float32
  proc pointAt(value: float32): Vec2 =
    let local = vec2(radii.x * cos(value), radii.y * sin(value))
    vec2(
      center.x + cosAngle * local.x - sinAngle * local.y,
      center.y + sinAngle * local.x + cosAngle * local.y,
    )

  proc derivativeAt(value: float32): Vec2 =
    let local = vec2(-radii.x * sin(value), radii.y * cos(value))
    vec2(
      cosAngle * local.x - sinAngle * local.y, sinAngle * local.x + cosAngle * local.y
    )

  for index in 0 ..< segmentCount:
    let
      nextAngle = startAngle + segmentAngle
      alpha = 4.0'f32 / 3.0'f32 * tan(segmentAngle * 0.25'f32)
      segmentStart = pointAt(startAngle)
      segmentStop =
        if index == segmentCount - 1:
          stop
        else:
          pointAt(nextAngle)
      control1 = segmentStart + derivativeAt(startAngle) * alpha
      control2 = segmentStop - derivativeAt(nextAngle) * alpha
    path.bezierCurveTo(control1, control2, segmentStop)
    startAngle = nextAngle

proc normalizePathArcs(path: Path): Path =
  ## Pixie retains SVG arcs in Path. SDFY accepts Beziers but not arc commands.
  let data = $path
  result = newPath()
  var
    index = 0
    current = vec2(0.0'f32, 0.0'f32)
    subpathStart = current
    previousControl = current
    previousCommand = '\0'

  while index < data.len:
    while index < data.len and data[index].isSpaceAscii:
      inc index
    if index >= data.len:
      break

    let command = data[index]
    inc index
    let relative = command in {'a' .. 'z'}
    case command.toUpperAscii
    of 'M':
      let value = vec2(data.readNumber(index), data.readNumber(index))
      current =
        if relative:
          current + value
        else:
          value
      result.moveTo(current)
      subpathStart = current
      previousControl = current
    of 'L':
      let value = vec2(data.readNumber(index), data.readNumber(index))
      current =
        if relative:
          current + value
        else:
          value
      result.lineTo(current)
      previousControl = current
    of 'H':
      let value = data.readNumber(index)
      current.x =
        if relative:
          current.x + value
        else:
          value
      result.lineTo(current)
      previousControl = current
    of 'V':
      let value = data.readNumber(index)
      current.y =
        if relative:
          current.y + value
        else:
          value
      result.lineTo(current)
      previousControl = current
    of 'C':
      let
        rawControl1 = vec2(data.readNumber(index), data.readNumber(index))
        rawControl2 = vec2(data.readNumber(index), data.readNumber(index))
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control1 =
          if relative:
            current + rawControl1
          else:
            rawControl1
        control2 =
          if relative:
            current + rawControl2
          else:
            rawControl2
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.bezierCurveTo(control1, control2, stop)
      current = stop
      previousControl = control2
    of 'S':
      let
        rawControl2 = vec2(data.readNumber(index), data.readNumber(index))
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control1 =
          if previousCommand.toUpperAscii in {'C', 'S'}:
            current * 2.0'f32 - previousControl
          else:
            current
        control2 =
          if relative:
            current + rawControl2
          else:
            rawControl2
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.bezierCurveTo(control1, control2, stop)
      current = stop
      previousControl = control2
    of 'Q':
      let
        rawControl = vec2(data.readNumber(index), data.readNumber(index))
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control =
          if relative:
            current + rawControl
          else:
            rawControl
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.quadraticCurveTo(control, stop)
      current = stop
      previousControl = control
    of 'T':
      let
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control =
          if previousCommand.toUpperAscii in {'Q', 'T'}:
            current * 2.0'f32 - previousControl
          else:
            current
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.quadraticCurveTo(control, stop)
      current = stop
      previousControl = control
    of 'A':
      let
        radii = vec2(data.readNumber(index), data.readNumber(index))
        rotation = data.readNumber(index)
        largeArc = data.readNumber(index) != 0.0'f32
        sweep = data.readNumber(index) != 0.0'f32
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.addArcAsCubics(current, radii, rotation, largeArc, sweep, stop)
      current = stop
      previousControl = current
    of 'Z':
      result.closePath()
      current = subpathStart
      previousControl = current
    else:
      raise newException(PixieError, "Unsupported normalized SVG path command")
    previousCommand = command

proc addLine(segments: var seq[SvgStrokeSegment], start, stop: Vec2, matrix: Mat3) =
  if start != stop:
    segments.add SvgStrokeSegment(
      kind: sskLine, start: matrix * start, stop: matrix * stop
    )

proc strokeSegments(
    path: Path, matrix: Mat3
): tuple[segments: seq[SvgStrokeSegment], complete: bool] =
  let data = $path
  var
    index = 0
    current = vec2(0.0'f32, 0.0'f32)
    subpathStart = current
    previousControl = current
    previousCommand = '\0'
  result.complete = true

  while index < data.len:
    while index < data.len and data[index].isSpaceAscii:
      inc index
    if index >= data.len:
      break

    let command = data[index]
    inc index
    let relative = command in {'a' .. 'z'}
    case command.toUpperAscii
    of 'M':
      let value = vec2(data.readNumber(index), data.readNumber(index))
      current =
        if relative:
          current + value
        else:
          value
      subpathStart = current
      previousControl = current
    of 'L':
      let
        value = vec2(data.readNumber(index), data.readNumber(index))
        stop =
          if relative:
            current + value
          else:
            value
      result.segments.addLine(current, stop, matrix)
      current = stop
      previousControl = current
    of 'H':
      let value = data.readNumber(index)
      let stop = vec2(
        if relative:
          current.x + value
        else:
          value,
        current.y,
      )
      result.segments.addLine(current, stop, matrix)
      current = stop
      previousControl = current
    of 'V':
      let value = data.readNumber(index)
      let stop = vec2(
        current.x,
        if relative:
          current.y + value
        else:
          value,
      )
      result.segments.addLine(current, stop, matrix)
      current = stop
      previousControl = current
    of 'C':
      let
        rawControl1 = vec2(data.readNumber(index), data.readNumber(index))
        rawControl2 = vec2(data.readNumber(index), data.readNumber(index))
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control1 =
          if relative:
            current + rawControl1
          else:
            rawControl1
        control2 =
          if relative:
            current + rawControl2
          else:
            rawControl2
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.segments.add SvgStrokeSegment(
        kind: sskCubic,
        start: matrix * current,
        control1: matrix * control1,
        control2: matrix * control2,
        stop: matrix * stop,
      )
      current = stop
      previousControl = control2
    of 'S':
      let
        rawControl2 = vec2(data.readNumber(index), data.readNumber(index))
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control1 =
          if previousCommand.toUpperAscii in {'C', 'S'}:
            current * 2.0'f32 - previousControl
          else:
            current
        control2 =
          if relative:
            current + rawControl2
          else:
            rawControl2
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.segments.add SvgStrokeSegment(
        kind: sskCubic,
        start: matrix * current,
        control1: matrix * control1,
        control2: matrix * control2,
        stop: matrix * stop,
      )
      current = stop
      previousControl = control2
    of 'Q':
      let
        rawControl = vec2(data.readNumber(index), data.readNumber(index))
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control =
          if relative:
            current + rawControl
          else:
            rawControl
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.segments.add SvgStrokeSegment(
        kind: sskQuadratic,
        start: matrix * current,
        control1: matrix * control,
        stop: matrix * stop,
      )
      current = stop
      previousControl = control
    of 'T':
      let
        rawStop = vec2(data.readNumber(index), data.readNumber(index))
        control =
          if previousCommand.toUpperAscii in {'Q', 'T'}:
            current * 2.0'f32 - previousControl
          else:
            current
        stop =
          if relative:
            current + rawStop
          else:
            rawStop
      result.segments.add SvgStrokeSegment(
        kind: sskQuadratic,
        start: matrix * current,
        control1: matrix * control,
        stop: matrix * stop,
      )
      current = stop
      previousControl = control
    of 'Z':
      result.segments.addLine(current, subpathStart, matrix)
      current = subpathStart
      previousControl = current
    of 'A':
      # Circular and elliptical SVG elements are handled as transformed FigDraw
      # circles. General elliptical path arcs need a future drawable conversion.
      result.complete = false
      return
    else:
      result.complete = false
      return
    previousCommand = command

proc toStrokeCap(cap: LineCap): SvgStrokeCap =
  case cap
  of ButtCap: sscButt
  of RoundCap: sscRound
  of SquareCap: sscSquare

proc toStrokeJoin(join: LineJoin): SvgStrokeJoin =
  case join
  of MiterJoin: ssjMiter
  of RoundJoin: ssjRound
  of BevelJoin: ssjBevel

proc parseSvgRoot(data: string): XmlNode =
  try:
    parseXml(data)
  except CatchableError as error:
    raise newException(PixieError, error.msg)

proc colorWithOpacity(value: Color, opacity: float32): Color =
  result = value
  result.a *= opacity

proc solidFillColor(properties: SvgProperties): Color =
  if properties.fill.startsWith("url("):
    raise newException(
      PixieError, "SVG gradient fills are not supported by the MTSDF loader"
    )
  parseHtmlColor(properties.fill).colorWithOpacity(
    properties.opacity * properties.fillOpacity
  )

proc solidStrokeColor(properties: SvgProperties): Color =
  properties.stroke.rgba.color.colorWithOpacity(
    properties.opacity * properties.strokeOpacity
  )

proc parseSvgDocument*(svgData: string): ParsedSvgDocument =
  let
    normalized = normalizeSvgData(svgData)
    root = parseSvgRoot(normalized)
    svg = parseSvg(root)
  result.width = svg.width
  result.height = svg.height

  var kinds: seq[SvgSourceElementKind]
  for child in root:
    collectElementKinds(child, kinds)
  if kinds.len != svg.elements.len:
    raise newException(PixieError, "SVG element metadata does not match parsed paths")

  for index, (sourcePath, properties) in svg.elements:
    let
      path = sourcePath.normalizePathArcs()
      kind = kinds[index]
      hasFill =
        kind != sekLine and properties.display and properties.opacity > 0 and
        properties.fillOpacity > 0 and properties.fill != "none"
      hasStroke =
        properties.display and properties.opacity > 0 and properties.strokeOpacity > 0 and
        properties.strokeWidth > 0 and properties.stroke != rgbx(0, 0, 0, 0)
    if not hasFill and not hasStroke:
      continue

    var element = ParsedSvgElement(
      kind: kind,
      hasFill: hasFill,
      hasStroke: hasStroke,
      fillColor:
        if hasFill:
          properties.solidFillColor()
        else:
          color(0.0, 0.0, 0.0, 0.0),
      strokeColor:
        if hasStroke:
          properties.solidStrokeColor()
        else:
          color(0.0, 0.0, 0.0, 0.0),
      fillRule: properties.fillRule,
      strokeWidth: properties.strokeWidth * properties.transform.transformScale(),
      strokeCap: properties.strokeLineCap.toStrokeCap(),
      strokeJoin: properties.strokeLineJoin.toStrokeJoin(),
    )

    if kind == sekCircle:
      let bounds = path.computeBounds()
      let
        radiusX = bounds.w * 0.5'f32
        radiusY = bounds.h * 0.5'f32
        center = bounds.xy + bounds.wh * 0.5'f32
        primitiveMatrix =
          properties.transform * translate(center) * scale(vec2(radiusX, radiusY))
      element.primitiveTransform = primitiveMatrix.affine()
      element.primitiveStrokeWidth =
        if hasStroke and max(radiusX, radiusY) > 0:
          properties.strokeWidth / max(radiusX, radiusY)
        else:
          0.0'f32
    else:
      if hasFill or kind == sekEllipse and hasStroke:
        element.fillPath = path.copy()
        element.fillPath.transform(properties.transform)
      if hasStroke and kind != sekEllipse:
        let parsedStroke = path.strokeSegments(properties.transform)
        if parsedStroke.complete:
          element.strokeSegments = parsedStroke.segments

    result.elements.add element
