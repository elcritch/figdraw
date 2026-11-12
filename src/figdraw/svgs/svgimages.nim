## SVG paint resources adapted from Merenda.
## Covered by FigDraw's MIT license.

import std/[hashes, math, strutils]

import pkg/pixie

import ../fignodes
import ../utils/drawmeshes
import ./[svgpathloader, svgfields, svgstrokes, svgraster]

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
    slkStrokeMesh
    slkCircle
    slkEllipse
    slkRectangle
    slkRasterGroup

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

  SvgMeshCache = ref object
    path: Path
    sourcePath: Path
    sourceTransform: SvgAffine
    width, miterLimit, dashOffset: float32
    cap: LineCap
    join: LineJoin
    dashes: seq[float32]
    key: string
    documentScale, requestedRange: float64
    image: ImageRef
    frame: Rect
    pixelRange: float32

  SvgLayer* = object ## One ordered SVG paint operation.
    paint*: Color
    transform*: SvgAffineTransform
    meshCache: SvgMeshCache
    case kind*: SvgLayerKind
    of slkMtsdfFill, slkMtsdfStroke:
      image*: ImageRef
      frame*: Rect
      pixelRange*: float32
      mtsdfStrokeWidth*: float32
    of slkStrokeMesh:
      meshOps*: seq[DrawableOp]
    of slkStrokePath:
      segments*: seq[SvgPathSegment]
      strokeWidth*: float32
      strokeCap*: SvgStrokeCap
      strokeJoin*: SvgStrokeJoin
      dashArray*: seq[float32]
      dashOffset*: float32
    of slkRasterGroup:
      rasterImage*, tintImage*: ImageRef
      rasterFrame*: Rect
    of slkCircle, slkEllipse, slkRectangle:
      primitiveBounds*: Rect
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

proc newMtsdfLayer(
    path: Path,
    windingRule: WindingRule,
    paint: Color,
    name: string,
    imageIndex, imageCount: int,
    documentScale, pixelRange: float64,
): SvgLayer =
  let field = generateSvgField(path, windingRule, documentScale, pixelRange)
  SvgLayer(
    kind: slkMtsdfFill,
    paint: paint,
    image: imageRef(imgId(layerName(name, imageIndex, imageCount)), field.image),
    frame: field.frame,
    pixelRange: field.pixelRange,
  )

proc matrix(value: SvgAffine): Mat3 =
  result = mat3()
  result[0, 0] = value.a
  result[0, 1] = value.b
  result[1, 0] = value.c
  result[1, 1] = value.d
  result[2, 0] = value.tx
  result[2, 1] = value.ty

proc lineCap(value: svgpathloader.SvgStrokeCap): LineCap =
  case value
  of sscButt: ButtCap
  of sscRound: RoundCap
  of sscSquare: SquareCap

proc lineJoin(value: svgpathloader.SvgStrokeJoin): LineJoin =
  case value
  of ssjMiter: MiterJoin
  of ssjRound: RoundJoin
  of ssjBevel: BevelJoin

proc nativeStroke(element: ParsedSvgElement): bool =
  ## Independent GPU ops are safe for one undashed segment. Rounded
  ## translucent caps need a union outline to avoid blending more than once.
  if element.sourceStrokeSegments.len != 1:
    return false
  if element.strokeColor.a < 1 and element.strokeCap != sscButt:
    return false
  if element.strokeDashArray.len > 0:
    if element.sourceStrokeSegments[0].kind != sskLine or element.strokeColor.a < 1:
      return false
    for dash in element.strokeDashArray:
      if dash <= 0:
        return false
  true

proc needsRaster(element: ParsedSvgElement): bool =
  element.fillPaintValue.startsWith("url(") or
    element.strokePaintValue.startsWith("url(") or element.clipPathIds.len > 0 or
    element.maskIds.len > 0

proc primitiveLayer(element: ParsedSvgElement, kind: static[SvgLayerKind]): SvgLayer =
  SvgLayer(
    kind: kind,
    paint: element.fillColor,
    transform: (
      when kind == slkCircle:
        element.primitiveTransform.toAffine()
      else: element.sourceTransform.toAffine()
    ),
    primitiveBounds: element.strokePath.computeBounds(),
    drawsFill: element.hasFill,
    drawsStroke: element.hasStroke,
    strokePaint: element.strokeColor,
    localStrokeWidth: element.primitiveStrokeWidth,
  )

proc meshFallback*(
    layer: SvgLayer
): tuple[image: ImageRef, frame: Rect, pixelRange: float32] =
  ## Lazily create and retain the union field for translucent stroke tints.
  if layer.kind notin {slkStrokePath, slkStrokeMesh} or layer.meshCache.isNil:
    raiseSvgMtsdfError("SVG layer has no stroke union fallback")
  let cache = layer.meshCache
  if cache.image.isNil:
    if cache.documentScale <= 0:
      raiseSvgMtsdfError("SVG MTSDF dimensions must exceed the pixel range")
    if cache.path.isNil:
      cache.path = strokeOutline(
        cache.sourcePath, cache.width, cache.cap, cache.join, cache.miterLimit,
        cache.dashes, cache.dashOffset,
      )
      cache.path.transform(cache.sourceTransform.matrix())
    let field =
      generateSvgField(cache.path, NonZero, cache.documentScale, cache.requestedRange)
    cache.image = imageRef(imgId(cache.key), field.image)
    cache.frame = field.frame
    cache.pixelRange = field.pixelRange
  (cache.image, cache.frame, cache.pixelRange)

proc newSvgMtsdfResource*(
    svgData: string,
    name = "",
    longEdge: Positive = DefaultSvgMtsdfLongEdge,
    minimumShortEdge: Positive = DefaultSvgMtsdfMinimumShortEdge,
    pixelRange = DefaultSvgMtsdfPixelRange,
): SvgMtsdfResource =
  ## Parses an SVG into ordered FigDraw vector strokes and MTSDF fill layers.
  ##
  ## Circles, ellipses, rectangles and independent stroke segments use native
  ## drawables. Opaque connected strokes use meshes; translucent strokes and
  ## complex fills use MTSDF images.
  ## Opacity groups and effects requiring compositing use cached RGBA images.
  ## Keep the resource alive while rendering its nodes, as with `ImageRef`.
  ## Image handles belong to the creating thread; transfer IDs across threads.
  ## `name` selects a cache identity; use distinct names for distinct resources.
  ## Invalid or unsupported documents raise `SvgMtsdfError`.
  if pixelRange <= 0.0 or classify(pixelRange) in {fcNan, fcInf, fcNegInf}:
    raiseSvgMtsdfError("SVG MTSDF pixel range must be finite and positive")

  try:
    let parsed = parseSvgDocument(svgData)
    result.size = parsed.viewportSize
    let dimensions =
      fieldDimensions(result.size.x, result.size.y, longEdge, minimumShortEdge)
    let usableWidth = dimensions.width.float64 - pixelRange
    let usableHeight = dimensions.height.float64 - pixelRange
    let documentScale =
      min(usableWidth / result.size.x.float64, usableHeight / result.size.y.float64)
    let resourceName =
      if name.len > 0:
        "figdraw.svg:" & name
      else:
        "figdraw.svg:" & $hash(svgData) & ":" & $longEdge & ":" & $minimumShortEdge & ":" &
          $pixelRange
    let imageCount = max(2, parsed.elements.len * 2)
    var imageIndex = 0
    var index = 0
    while index < parsed.elements.len:
      let element = parsed.elements[index]
      let firstLayer = result.layers.len
      if element.compositeGroupStarts.len > 0 or element.needsRaster():
        var last = index
        var depth = element.compositeGroupStarts.len - element.compositeGroupEnds
        while depth > 0 and last + 1 < parsed.elements.len:
          inc last
          depth +=
            parsed.elements[last].compositeGroupStarts.len -
            parsed.elements[last].compositeGroupEnds
        if depth != 0:
          raiseSvgMtsdfError("Unbalanced SVG opacity groups")
        let raster = rasterizeSvgElements(parsed, index, last, longEdge)
        let key = layerName(resourceName, imageIndex, imageCount)
        result.layers.add SvgLayer(
          kind: slkRasterGroup,
          rasterImage: imageRef(imgId(key), raster.image),
          tintImage: imageRef(imgId(key & ":tint"), raster.tintImage),
          rasterFrame: raster.frame,
        )
        inc imageIndex
        result.elementCount += last - index + 1
        index = last + 1
      else:
        let plainPrimitive =
          element.kind in {sekCircle, sekEllipse} and element.strokeDashArray.len == 0
        if plainPrimitive:
          if element.kind == sekCircle:
            result.layers.add primitiveLayer(element, slkCircle)
          else:
            result.layers.add primitiveLayer(element, slkEllipse)
        else:
          if element.hasFill and element.fillPath.hasArea():
            let squareRectangle =
              element.kind == sekRectangle and 'C' notin $element.strokePath
            if squareRectangle:
              result.layers.add SvgLayer(
                kind: slkRectangle,
                paint: element.fillColor,
                transform: element.sourceTransform.toAffine(),
                primitiveBounds: element.strokePath.computeBounds(),
                drawsFill: true,
              )
            else:
              if documentScale <= 0:
                raiseSvgMtsdfError("SVG MTSDF dimensions must exceed the pixel range")
              result.layers.add newMtsdfLayer(
                element.fillPath, element.fillRule, element.fillColor, resourceName,
                imageIndex, imageCount, documentScale, pixelRange,
              )
              inc imageIndex
          if element.hasStroke:
            if element.nativeStroke():
              var segments: seq[SvgPathSegment]
              for segment in element.sourceStrokeSegments:
                segments.add segment.toSegment()
              result.layers.add SvgLayer(
                kind: slkStrokePath,
                paint: element.strokeColor,
                transform: element.sourceTransform.toAffine(),
                segments: segments,
                strokeWidth: element.sourceStrokeWidth,
                strokeCap: element.strokeCap.toStrokeCap(),
                strokeJoin: element.strokeJoin.toStrokeJoin(),
                dashArray: element.strokeDashArray,
                dashOffset: element.strokeDashOffset,
                meshCache: SvgMeshCache(
                  sourcePath: element.strokePath,
                  sourceTransform: element.sourceTransform,
                  width: element.sourceStrokeWidth,
                  cap: element.strokeCap.lineCap(),
                  join: element.strokeJoin.lineJoin(),
                  miterLimit: element.strokeMiterLimit,
                  dashes: element.strokeDashArray,
                  dashOffset: element.strokeDashOffset,
                  key: layerName(resourceName, imageIndex, imageCount),
                  documentScale: documentScale,
                  requestedRange: pixelRange,
                ),
              )
              inc imageIndex
            else:
              let outline = strokeOutline(
                element.strokePath,
                element.sourceStrokeWidth,
                element.strokeCap.lineCap(),
                element.strokeJoin.lineJoin(),
                element.strokeMiterLimit,
                element.strokeDashArray,
                element.strokeDashOffset,
              )
              if outline.hasArea():
                if element.strokeColor.a >= 1:
                  let ops = drawableStrokeOutlineOps(outline)
                  outline.transform(element.sourceTransform.matrix())
                  result.layers.add SvgLayer(
                    kind: slkStrokeMesh,
                    paint: element.strokeColor,
                    transform: element.sourceTransform.toAffine(),
                    meshOps: ops,
                    meshCache: SvgMeshCache(
                      path: outline,
                      key: layerName(resourceName, imageIndex, imageCount),
                      documentScale: documentScale,
                      requestedRange: pixelRange,
                    ),
                  )
                else:
                  outline.transform(element.sourceTransform.matrix())
                  if documentScale <= 0:
                    raiseSvgMtsdfError(
                      "SVG MTSDF dimensions must exceed the pixel range"
                    )
                  result.layers.add newMtsdfLayer(
                    outline, NonZero, element.strokeColor, resourceName, imageIndex,
                    imageCount, documentScale, pixelRange,
                  )
                inc imageIndex
        if result.layers.len > firstLayer:
          inc result.elementCount
        inc index

    if result.layers.len == 0:
      raiseSvgMtsdfError("SVG contains no supported visible painted elements")
  except CatchableError as error:
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
