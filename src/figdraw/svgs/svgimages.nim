## SVG paint resources adapted from Merenda (BSD-3-Clause).
## See docs/licenses/MERENDA.txt for the original license.

import std/[hashes, math]

import pkg/pixie
import pkg/sdfy/msdfgen

import ../fignodes
import ./svgpathloader

const
  DefaultSvgMtsdfLongEdge* = 192
  DefaultSvgMtsdfMinimumShortEdge* = 48
  DefaultSvgMtsdfPixelRange* = 6.0

type
  SvgMtsdfError* = object of CatchableError
    ## Raised when SVG path loading or MTSDF generation fails.

  SvgLayerKind* = enum
    slkMtsdfFill
    slkMtsdfStroke
    slkStrokePath
    slkCircle

  SvgPathSegmentKind* = enum
    spsLine
    spsQuadratic
    spsCubic

  SvgStrokeCap* = enum
    svcButt
    svcRound
    svcSquare

  SvgStrokeJoin* = enum
    svjMiter
    svjRound
    svjBevel

  SvgPathSegment* = object ## One stroked path segment in SVG document coordinates.
    kind*: SvgPathSegmentKind
    start*, control1*, control2*, stop*: Vec2

  SvgAffineTransform* = object ## A 2D affine transform in SVG document coordinates.
    a*, b*, c*, d*, tx*, ty*: float32

  SvgLayer* = object ## One ordered SVG paint operation.
    paint*: Color
    case kind*: SvgLayerKind
    of slkMtsdfFill, slkMtsdfStroke:
      image*: ImageRef
      frame*: Rect
      pixelRange*: float32
      mtsdfStrokeWidth*: float32
    of slkStrokePath:
      segments*: seq[SvgPathSegment]
      strokeWidth*: float32
      strokeCap*: SvgStrokeCap
      strokeJoin*: SvgStrokeJoin
    of slkCircle:
      transform*: SvgAffineTransform
      drawsFill*, drawsStroke*: bool
      strokePaint*: Color
      localStrokeWidth*: float32

  SvgMtsdfResource* = object
    ## Reusable ordered vector and MTSDF layers generated from an SVG.
    layers*: seq[SvgLayer]
    elementCount*: Natural
    size*: Vec2

proc fieldDimensions(
    width, height: float32, longEdge, minimumShortEdge: Positive
): tuple[width, height: int] =
  if width <= 0.0'f32 or height <= 0.0'f32:
    raise newException(PixieError, "SVG has empty bounds")

  let
    aspect = width / height
    shortest = min(minimumShortEdge.int, longEdge.int)
  if aspect >= 1.0'f32:
    result.width = longEdge
    result.height = max(shortest, int(round(longEdge.float32 / aspect)))
  else:
    result.width = max(shortest, int(round(longEdge.float32 * aspect)))
    result.height = longEdge

proc raiseSvgMtsdfError(message: string) {.noinline, noreturn.} =
  raise newException(SvgMtsdfError, message)

proc layerName(name: string, index, count: int): string =
  if name.len == 0:
    return ""
  if count == 1:
    return name
  name & ":" & $index

proc hasArea(path: Path): bool =
  if path.isNil:
    return
  let bounds = path.computeBounds()
  bounds.w > 0.0'f32 and bounds.h > 0.0'f32

proc toSegment(segment: svgpathloader.SvgStrokeSegment): SvgPathSegment =
  let kind =
    case segment.kind
    of sskLine: spsLine
    of sskQuadratic: spsQuadratic
    of sskCubic: spsCubic
  SvgPathSegment(
    kind: kind,
    start: segment.start,
    control1: segment.control1,
    control2: segment.control2,
    stop: segment.stop,
  )

proc toStrokeCap(value: svgpathloader.SvgStrokeCap): SvgStrokeCap =
  case value
  of sscButt: svcButt
  of sscRound: svcRound
  of sscSquare: svcSquare

proc toStrokeJoin(value: svgpathloader.SvgStrokeJoin): SvgStrokeJoin =
  case value
  of ssjMiter: svjMiter
  of ssjRound: svjRound
  of ssjBevel: svjBevel

proc toAffine(value: SvgAffine): SvgAffineTransform =
  SvgAffineTransform(
    a: value.a, b: value.b, c: value.c, d: value.d, tx: value.tx, ty: value.ty
  )

proc correctMtsdfSign(
    image: Image,
    path: Path,
    windingRule: WindingRule,
    fieldScale: float32,
    fieldTranslation: Vec2,
) =
  ## SVG paths can be self-intersecting or use overlapping contours whose
  ## winding differs from the distance generator's contour orientation. Keep
  ## its distance magnitude, but use Pixie's SVG fill result for the sign.
  let mask = newImage(image.width, image.height)
  mask.fillPath(
    path,
    color(1.0, 1.0, 1.0, 1.0),
    translate(fieldTranslation * fieldScale) * scale(vec2(fieldScale)),
    windingRule,
  )
  for index in 0 ..< image.data.len:
    let
      generatedInside = image.data[index].a >= 128
      rasterInside = mask.data[index].a >= 128
    if generatedInside != rasterInside:
      image.data[index].a = 255 - image.data[index].a

proc newMtsdfLayer(
    path: Path,
    windingRule: WindingRule,
    paint: Color,
    name: string,
    imageIndex, imageCount: int,
    documentScale, pixelRange: float64,
): SvgLayer =
  let bounds = path.computeBounds()
  if bounds.w <= 0.0'f32 or bounds.h <= 0.0'f32:
    raise newException(PixieError, "SVG path has empty bounds")

  let
    minimumDimension = int(ceil(pixelRange + 1.0))
    width =
      max(minimumDimension, int(ceil(bounds.w.float64 * documentScale + pixelRange)))
    height =
      max(minimumDimension, int(ceil(bounds.h.float64 * documentScale + pixelRange)))
    field = generateMtsdfPath(path, width, height, pixelRange)
    fieldScale = field.scale.float32
  field.image.flipVertical()
  field.image.correctMtsdfSign(
    path,
    windingRule,
    fieldScale,
    vec2(field.translate.x.float32, field.translate.y.float32),
  )

  SvgLayer(
    kind: slkMtsdfFill,
    paint: paint,
    image: imageRef(imgId(layerName(name, imageIndex, imageCount)), field.image),
    frame: rect(
      (-field.translate.x).float32,
      (-field.translate.y).float32,
      width.float32 / fieldScale,
      height.float32 / fieldScale,
    ),
    pixelRange: (field.range * field.scale).float32,
  )

proc mtsdfStrokeLayer(
    fillLayer: SvgLayer, strokeWidth: float32, paint: Color
): SvgLayer =
  SvgLayer(
    kind: slkMtsdfStroke,
    paint: paint,
    image: fillLayer.image,
    frame: fillLayer.frame,
    pixelRange: fillLayer.pixelRange,
    mtsdfStrokeWidth: strokeWidth,
  )

proc newSvgMtsdfResource*(
    svgData: string,
    name = "",
    longEdge: Positive = DefaultSvgMtsdfLongEdge,
    minimumShortEdge: Positive = DefaultSvgMtsdfMinimumShortEdge,
    pixelRange = DefaultSvgMtsdfPixelRange,
): SvgMtsdfResource =
  ## Parses an SVG into ordered FigDraw vector strokes and MTSDF fill layers.
  ##
  ## Circles, lines, and Bezier strokes remain vector drawables. Ellipses and
  ## independently filled complex elements receive separate compact MTSDFs.
  ## Solid SVG fill and stroke colors, including inherited colors and opacity,
  ## are kept. Gradient fills are not yet supported.
  ## Keep the resource alive while rendering its nodes, as with `ImageRef`.
  ## Image handles belong to the creating thread; transfer IDs across threads.
  ## `name` selects a cache identity; use distinct names for distinct resources.
  ## Invalid or unsupported documents raise `SvgMtsdfError`.
  if pixelRange <= 0.0 or classify(pixelRange) in {fcNan, fcInf, fcNegInf}:
    raiseSvgMtsdfError("SVG MTSDF pixel range must be finite and positive")

  try:
    let parsed = parseSvgDocument(svgData)
    result.size = vec2(parsed.width.float32, parsed.height.float32)
    let
      imageCount = block:
        var count = 0
        for element in parsed.elements:
          if element.kind != sekCircle and element.fillPath.hasArea():
            inc count
        count
      dimensions =
        fieldDimensions(result.size.x, result.size.y, longEdge, minimumShortEdge)
      usableWidth = dimensions.width.float64 - pixelRange
      usableHeight = dimensions.height.float64 - pixelRange
    if imageCount > 0 and (usableWidth <= 0.0 or usableHeight <= 0.0):
      raiseSvgMtsdfError("SVG MTSDF dimensions must exceed the pixel range")

    let documentScale =
      if imageCount > 0:
        min(usableWidth / result.size.x.float64, usableHeight / result.size.y.float64)
      else:
        0.0
    let resourceName =
      if name.len > 0:
        "figdraw.svg:" & name
      else:
        "figdraw.svg:" & $hash(svgData) & ":" & $longEdge & ":" & $minimumShortEdge & ":" &
          $pixelRange
    var imageIndex = 0

    for element in parsed.elements:
      let firstLayer = result.layers.len
      if element.kind == sekCircle:
        result.layers.add SvgLayer(
          kind: slkCircle,
          paint: element.fillColor,
          transform: element.primitiveTransform.toAffine(),
          drawsFill: element.hasFill,
          drawsStroke: element.hasStroke,
          strokePaint: element.strokeColor,
          localStrokeWidth: element.primitiveStrokeWidth,
        )
      elif element.kind == sekEllipse:
        if element.fillPath.hasArea():
          let mtsdfLayer = newMtsdfLayer(
            element.fillPath, element.fillRule, element.fillColor, resourceName,
            imageIndex, imageCount, documentScale, pixelRange,
          )
          inc imageIndex
          if element.hasFill:
            result.layers.add mtsdfLayer
          if element.hasStroke:
            result.layers.add mtsdfLayer.mtsdfStrokeLayer(
              element.strokeWidth, element.strokeColor
            )
      else:
        if element.hasFill and element.fillPath.hasArea():
          result.layers.add newMtsdfLayer(
            element.fillPath, element.fillRule, element.fillColor, resourceName,
            imageIndex, imageCount, documentScale, pixelRange,
          )
          inc imageIndex
        if element.hasStroke and element.strokeSegments.len > 0:
          var segments = newSeqOfCap[SvgPathSegment](element.strokeSegments.len)
          for segment in element.strokeSegments:
            segments.add segment.toSegment()
          result.layers.add SvgLayer(
            kind: slkStrokePath,
            paint: element.strokeColor,
            segments: segments,
            strokeWidth: element.strokeWidth,
            strokeCap: element.strokeCap.toStrokeCap(),
            strokeJoin: element.strokeJoin.toStrokeJoin(),
          )
      if result.layers.len > firstLayer:
        inc result.elementCount

    if result.layers.len == 0:
      raiseSvgMtsdfError("SVG contains no supported visible painted elements")
  except PixieError as error:
    raiseSvgMtsdfError(error.msg)

proc newSvgMtsdfResourceFromFile*(
    filePath: string,
    name = "",
    longEdge: Positive = DefaultSvgMtsdfLongEdge,
    minimumShortEdge: Positive = DefaultSvgMtsdfMinimumShortEdge,
    pixelRange = DefaultSvgMtsdfPixelRange,
): SvgMtsdfResource =
  ## Reads an SVG file and creates its ordered vector and MTSDF layers.
  let data =
    try:
      readFile(filePath)
    except IOError as error:
      raiseSvgMtsdfError("Failed to read SVG: " & error.msg)
  newSvgMtsdfResource(data, name, longEdge, minimumShortEdge, pixelRange)

proc len*(resource: SvgMtsdfResource): int =
  ## Returns the number of ordered paint layers.
  resource.layers.len

proc image*(resource: SvgMtsdfResource): ImageRef =
  ## Returns the first MTSDF image, retained for single-image compatibility.
  for layer in resource.layers:
    if layer.kind in {slkMtsdfFill, slkMtsdfStroke}:
      return layer.image

proc pixelRange*(resource: SvgMtsdfResource): float32 =
  ## Returns the first MTSDF layer's pixel range, or zero for vector-only SVGs.
  for layer in resource.layers:
    if layer.kind in {slkMtsdfFill, slkMtsdfStroke}:
      return layer.pixelRange
