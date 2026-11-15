# SPDX-License-Identifier: MIT
# Imported from Merenda; adapted from sdfy/src/sdfy/msdfgenSvg.nim.
# See docs/svg_sources.md for provenance; covered by FigDraw's MIT license.

## Parses SVG documents into paths and vector stroke metadata.

import std/[math, strutils, strtabs, tables]

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

  ParsedSvgCompositeGroup* = object
    opacity*: float32
    clipPathIds*, maskIds*: seq[string]
    clipPathTransforms*, maskTransforms*: seq[SvgAffine]
    sourceTransform*: SvgAffine

  ParsedSvgElement* = object
    kind*: SvgSourceElementKind
    fillPath*: Path
    hasFill*, hasStroke*: bool
    fillColor*, strokeColor*: Color
    fillOpacity*, strokeOpacity*: float32
    fillRule*: WindingRule
    strokeSegments*, sourceStrokeSegments*: seq[SvgStrokeSegment]
    strokeWidth*, sourceStrokeWidth*: float32
    strokeCap*: SvgStrokeCap
    strokeJoin*: SvgStrokeJoin
    primitiveTransform*: SvgAffine
    primitiveStrokeWidth*: float32
    strokePath*: Path
    strokeDashArray*: seq[float32]
    strokeDashOffset*, strokeMiterLimit*: float32
    opacityGroupStarts*: seq[float32]
    opacityGroupEnds*: int
    compositeGroupStarts*: seq[ParsedSvgCompositeGroup]
    compositeGroupEnds*: int
    fillPaintValue*, strokePaintValue*, currentColor*: string
    sourceTransform*: SvgAffine
    clipPathIds*, maskIds*: seq[string]
    clipPathTransforms*, maskTransforms*: seq[SvgAffine]

  ParsedSvgDocument* = object
    width*, height*: int
    viewportSize*: Vec2
    elements*: seq[ParsedSvgElement]
    root*: XmlNode

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
  parseHtmlColor(properties.fill).colorWithOpacity(properties.fillOpacity)

proc solidStrokeColor(properties: SvgProperties): Color =
  properties.stroke.rgba.color.colorWithOpacity(properties.strokeOpacity)

type ElementState = object
  props: SvgProperties
  currentColor: string
  fillValue, strokeValue: string
  dashOffset: float32
  clipPathIds, maskIds: seq[string]
  clipPathTransforms, maskTransforms: seq[SvgAffine]

proc declarations(node: XmlNode): Table[string, string] =
  if node.attrs != nil:
    for key, value in node.attrs:
      result[key] = value.strip()
  for pair in node.attr("style").split(';'):
    let colon = pair.find(':')
    if colon >= 0:
      result[pair[0 ..< colon].strip()] = pair[colon + 1 .. ^1].strip()

proc resolveState(
    node: XmlNode, inherited: ElementState
): tuple[state: ElementState, opacity: float32] =
  result.state = inherited
  result.state.clipPathIds = @[]
  result.state.maskIds = @[]
  result.state.clipPathTransforms = @[]
  result.state.maskTransforms = @[]
  result.opacity = 1
  let values = node.declarations()
  var clean = newElement("g")
  clean.attrs = newStringTable(modeCaseSensitive)
  for key in [
    "fill-rule", "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
    "stroke-miterlimit", "stroke-dasharray", "transform", "fill-opacity",
    "stroke-opacity",
  ]:
    if key in values and values[key] != "inherit":
      clean.attrs[key] = values[key]
  if "color" in values and values["color"] != "inherit":
    result.state.currentColor = values["color"]
  if "fill" in clean.attrs:
    result.state.fillValue = clean.attrs["fill"]
  if "stroke" in clean.attrs:
    result.state.strokeValue = clean.attrs["stroke"]
  clean.attrs["fill"] =
    if result.state.fillValue == "currentColor":
      result.state.currentColor
    else:
      result.state.fillValue
  clean.attrs["stroke"] =
    if result.state.strokeValue == "currentColor":
      result.state.currentColor
    else:
      result.state.strokeValue
  # Pixie appends inherited dash arrays and invents a stroke for stroke-width.
  if "stroke-dasharray" in clean.attrs:
    result.state.props.strokeDashArray.setLen(0)
    if clean.attrs["stroke-dasharray"] == "none":
      clean.attrs.del("stroke-dasharray")
  if "stroke" in clean.attrs and clean.attrs["stroke"].startsWith("url("):
    clean.attrs["stroke"] = "black"
  result.state.props = clean.parseSvgProperties(result.state.props)
  if result.state.strokeValue == "none":
    result.state.props.stroke = ColorRGBX()
  if "stroke-dashoffset" in values and values["stroke-dashoffset"] != "inherit":
    result.state.dashOffset = parseFloat(values["stroke-dashoffset"])
  if "display" in values and values["display"] == "none":
    result.state.props.display = false
  for key in ["clip-path", "mask"]:
    if key in values and values[key].startsWith("url(#") and values[key].endsWith(")"):
      let id = values[key][5 .. ^2]
      if key == "clip-path":
        result.state.clipPathIds.add id
        result.state.clipPathTransforms.add result.state.props.transform.affine()
      else:
        result.state.maskIds.add id
        result.state.maskTransforms.add result.state.props.transform.affine()
  if "opacity" in values:
    result.opacity = clamp(parseFloat(values["opacity"]), 0, 1)
  result.state.props.opacity = 1

proc elementKind(tag: string): SvgSourceElementKind =
  case tag
  of "path":
    sekPath
  of "line":
    sekLine
  of "polyline":
    sekPolyline
  of "polygon":
    sekPolygon
  of "rect":
    sekRectangle
  of "circle":
    sekCircle
  of "ellipse":
    sekEllipse
  else:
    raise newException(PixieError, "Unsupported SVG tag: " & tag)

proc geometryNode(node: XmlNode): XmlNode =
  result = newElement(node.tag)
  result.attrs = newStringTable(modeCaseSensitive)
  for key in [
    "d", "x", "y", "x1", "x2", "y1", "y2", "width", "height", "rx", "ry", "r", "cx",
    "cy", "points",
  ]:
    let value = node.attr(key)
    if value.len > 0:
      result.attrs[key] =
        if key == "points":
          value.replace(',', ' ').splitWhitespace().join(" ")
        else:
          value

proc appendElement(
    document: var ParsedSvgDocument,
    kind: SvgSourceElementKind,
    sourcePath: Path,
    state: ElementState,
) =
  let
    properties = state.props
    path = sourcePath.normalizePathArcs()
    hasFill =
      kind != sekLine and properties.display and properties.fillOpacity > 0 and
      properties.fill != "none"
    hasStroke =
      properties.display and properties.strokeOpacity > 0 and properties.strokeWidth > 0 and
      (state.strokeValue.startsWith("url(") or properties.stroke != rgbx(0, 0, 0, 0))
  if not hasFill and not hasStroke:
    return
  var element = ParsedSvgElement(
    kind: kind,
    hasFill: hasFill,
    hasStroke: hasStroke,
    fillColor: (
      if hasFill and not properties.fill.startsWith("url("): properties.solidFillColor()
      else: color(0.0, 0.0, 0.0, 0.0)
    ),
    strokeColor: (
      if hasStroke and not state.strokeValue.startsWith("url("):
      properties.solidStrokeColor()
      else: color(0.0, 0.0, 0.0, 0.0)
    ),
    fillRule: properties.fillRule,
    fillOpacity: properties.fillOpacity,
    strokeOpacity: properties.strokeOpacity,
    strokeWidth: properties.strokeWidth * properties.transform.transformScale(),
    sourceStrokeWidth: properties.strokeWidth,
    strokeCap: properties.strokeLineCap.toStrokeCap(),
    strokeJoin: properties.strokeLineJoin.toStrokeJoin(),
    strokePath: path,
    strokeDashArray: properties.strokeDashArray,
    strokeDashOffset: state.dashOffset,
    strokeMiterLimit: properties.strokeMiterLimit,
    primitiveTransform: properties.transform.affine(),
    sourceTransform: properties.transform.affine(),
    fillPaintValue: properties.fill,
    strokePaintValue: (
      if state.strokeValue == "currentColor": state.currentColor else: state.strokeValue
    ),
    currentColor: state.currentColor,
    clipPathIds: state.clipPathIds,
    maskIds: state.maskIds,
    clipPathTransforms: state.clipPathTransforms,
    maskTransforms: state.maskTransforms,
  )
  if hasFill or kind == sekEllipse and hasStroke:
    element.fillPath = path.copy()
    element.fillPath.transform(properties.transform)
  if kind == sekCircle:
    let bounds = path.computeBounds()
    let radiusX = bounds.w * 0.5'f32
    let radiusY = bounds.h * 0.5'f32
    let center = bounds.xy + bounds.wh * 0.5'f32
    element.primitiveTransform = (
      properties.transform * translate(center) * scale(vec2(radiusX, radiusY))
    ).affine()
    element.primitiveStrokeWidth =
      if hasStroke and max(radiusX, radiusY) > 0:
        properties.strokeWidth / max(radiusX, radiusY)
      else:
        0.0'f32
  else:
    if kind == sekEllipse:
      element.primitiveStrokeWidth = properties.strokeWidth
    if hasStroke and kind != sekEllipse:
      let parsedStroke = path.strokeSegments(properties.transform)
      if parsedStroke.complete:
        element.strokeSegments = parsedStroke.segments
        element.sourceStrokeSegments = path.strokeSegments(mat3()).segments
  document.elements.add element

proc symbolViewport(symbol, use: XmlNode): Mat3 =
  let box = symbol.attr("viewBox").replace(',', ' ').splitWhitespace()
  result = mat3()
  if box.len == 0:
    return
  if box.len != 4:
    raise newException(PixieError, "Invalid symbol viewBox")
  let
    minX = parseFloat(box[0]).float32
    minY = parseFloat(box[1]).float32
    boxWidth = parseFloat(box[2]).float32
    boxHeight = parseFloat(box[3]).float32
  if boxWidth <= 0 or boxHeight <= 0:
    raise newException(PixieError, "Invalid symbol viewBox")
  let
    width = parseFloat(use.attrOrDefault("width", $boxWidth)).float32
    height = parseFloat(use.attrOrDefault("height", $boxHeight)).float32
  if width <= 0 or height <= 0:
    raise newException(PixieError, "Invalid symbol viewport")
  let aspect = symbol.attr("preserveAspectRatio").splitWhitespace()
  let align =
    if aspect.len == 0:
      "xMidYMid"
    else:
      aspect[0]
  var sx = width / boxWidth
  var sy = height / boxHeight
  var dx, dy: float32
  if align != "none":
    if align notin [
      "xMinYMin", "xMidYMin", "xMaxYMin", "xMinYMid", "xMidYMid", "xMaxYMid",
      "xMinYMax", "xMidYMax", "xMaxYMax",
    ] or aspect.len > 2 or (aspect.len == 2 and aspect[1] notin ["meet", "slice"]):
      raise newException(PixieError, "Invalid preserveAspectRatio")
    let factor =
      if aspect.len == 2 and aspect[1] == "slice":
        max(sx, sy)
      else:
        min(sx, sy)
    sx = factor
    sy = factor
    let extraX = width - boxWidth * factor
    let extraY = height - boxHeight * factor
    if align.startsWith("xMid"):
      dx = extraX * 0.5'f32
    elif align.startsWith("xMax"):
      dx = extraX
    if align.endsWith("YMid"):
      dy = extraY * 0.5'f32
    elif align.endsWith("YMax"):
      dy = extraY
  result = translate(vec2(dx, dy)) * scale(vec2(sx, sy)) * translate(vec2(-minX, -minY))

proc walkSvg(
    node: XmlNode,
    inherited: ElementState,
    document: var ParsedSvgDocument,
    ids: Table[string, XmlNode],
    active: seq[string],
) =
  if node.kind != xnElement:
    return
  let resolved = node.resolveState(inherited)
  if not resolved.state.props.display or resolved.opacity <= 0:
    return
  let first = document.elements.len
  case node.tag
  of "svg", "g", "symbol":
    for child in node:
      child.walkSvg(resolved.state, document, ids, active)
  of "use":
    var reference = node.attr("href")
    if reference.len == 0:
      reference = node.attr("xlink:href")
    if reference.len < 2 or reference[0] != '#' or reference[1 .. ^1] notin ids:
      raise newException(PixieError, "Missing SVG use reference: " & reference)
    let id = reference[1 .. ^1]
    if id in active:
      raise newException(PixieError, "Cyclic SVG use reference: " & reference)
    var state = resolved.state
    state.props.transform =
      state.props.transform *
      translate(
        vec2(
          parseFloat(node.attrOrDefault("x", "0")),
          parseFloat(node.attrOrDefault("y", "0")),
        )
      )
    if ids[id].tag == "symbol":
      state.props.transform = state.props.transform * symbolViewport(ids[id], node)
    ids[id].walkSvg(state, document, ids, active & @[id])
  of "defs", "title", "desc", "clipPath", "mask", "linearGradient", "radialGradient":
    discard
  of "path", "line", "polyline", "polygon", "rect", "circle", "ellipse":
    var stack = @[resolved.state.props]
    let elements = node.geometryNode().parseSvgElement(Svg(), stack)
    for (path, _) in elements:
      document.appendElement(node.tag.elementKind(), path, resolved.state)
  else:
    raise newException(PixieError, "Unsupported SVG tag: " & node.tag)
  if document.elements.len > first and (
    resolved.opacity < 1 or resolved.state.clipPathIds.len > 0 or
    resolved.state.maskIds.len > 0
  ):
    let group = ParsedSvgCompositeGroup(
      opacity: resolved.opacity,
      clipPathIds: resolved.state.clipPathIds,
      maskIds: resolved.state.maskIds,
      clipPathTransforms: resolved.state.clipPathTransforms,
      maskTransforms: resolved.state.maskTransforms,
      sourceTransform: resolved.state.props.transform.affine(),
    )
    document.elements[first].compositeGroupStarts.insert(group, 0)
    inc document.elements[^1].compositeGroupEnds
  if resolved.opacity < 1 and document.elements.len > first:
    document.elements[first].opacityGroupStarts.insert(resolved.opacity, 0)
    inc document.elements[^1].opacityGroupEnds

proc collectIds(node: XmlNode, ids: var Table[string, XmlNode]) =
  if node.kind == xnElement:
    let id = node.attr("id")
    if id.len > 0:
      ids[id] = node
    for child in node:
      child.collectIds(ids)

proc parseSvgDocument*(svgData: string): ParsedSvgDocument =
  try:
    let root = parseSvgRoot(svgData)
    if root.kind != xnElement or root.tag != "svg":
      raise newException(PixieError, "Invalid SVG data")
    let box = root.attr("viewBox").replace(',', ' ').splitWhitespace()
    var x, y, width, height: float32
    if box.len == 4:
      x = parseFloat(box[0])
      y = parseFloat(box[1])
      width = parseFloat(box[2])
      height = parseFloat(box[3])
    elif box.len == 0:
      var widthText = root.attr("width")
      var heightText = root.attr("height")
      widthText.removeSuffix("px")
      heightText.removeSuffix("px")
      width = parseFloat(widthText)
      height = parseFloat(heightText)
    else:
      raise newException(PixieError, "Invalid SVG viewBox")
    if width <= 0 or height <= 0 or width.classify in {fcNan, fcInf, fcNegInf} or
        height.classify in {fcNan, fcInf, fcNegInf} or
        abs(x).classify in {fcNan, fcInf, fcNegInf} or
        abs(y).classify in {fcNan, fcInf, fcNegInf} or width > 1_000_000_000 or
        height > 1_000_000_000:
      raise newException(PixieError, "Invalid SVG viewport")
    result.root = root
    result.viewportSize = vec2(width, height)
    result.width = int(ceil(width))
    result.height = int(ceil(height))
    var state = ElementState(
      props: initSvgProperties(),
      currentColor: "black",
      fillValue: "black",
      strokeValue: "none",
    )
    state.props.transform = translate(vec2(-x, -y))
    var ids: Table[string, XmlNode]
    root.collectIds(ids)
    root.walkSvg(state, result, ids, @[])
  except PixieError:
    raise
  except CatchableError as error:
    raise newException(PixieError, error.msg)
