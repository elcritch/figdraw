## Draw ordered SVG fill and stroke layers using ordinary FigDraw nodes.
## Adapted from Merenda; covered by FigDraw's MIT license.

import ../fignodes
import ../utils/[drawprimitives, drawpaths]
import ./svgimages

export fignodes, svgimages

proc addSvgNode(list: var RenderList, parent: FigIdx, node: Fig): FigIdx =
  if parent.int < 0:
    list.addRoot(node)
  else:
    list.addChild(parent, node)

proc toFigStrokeCap(value: SvgStrokeCap): StrokeCap =
  case value
  of svcButt: scButt
  of svcRound: scRound
  of svcSquare: scSquare

proc toFigStrokeJoin(value: SvgStrokeJoin): StrokeJoin =
  case value
  of svjMiter: sjMiter
  of svjRound: sjRound
  of svjBevel: sjBevel

proc svgLayerRect(target: Rect, documentSize: Vec2, frame: Rect): Rect =
  let
    scaleX = target.w / documentSize.x
    scaleY = target.h / documentSize.y
  rect(
    target.x + frame.x * scaleX,
    target.y + frame.y * scaleY,
    frame.w * scaleX,
    frame.h * scaleY,
  )

proc svgLocalPoint(point: Vec2, scaleX, scaleY: float32): Vec2 =
  vec2(point.x * scaleX, point.y * scaleY)

proc svgPathNode(
    target: Rect, documentSize: Vec2, svgLayer: SvgLayer, fillValue: Fill
): Fig =
  let
    scaleX = 1.0'f32
    scaleY = 1.0'f32
  result = Fig(
    kind: nkDrawable,
    screenBox: rect(0, 0, documentSize.x, documentSize.y),
    fill: fill(rgba(0, 0, 0, 0)),
    drawStroke: RenderStroke(
      weight: svgLayer.strokeWidth * min(abs(scaleX), abs(scaleY)),
      fill: fillValue,
      cap: svgLayer.strokeCap.toFigStrokeCap(),
      join: svgLayer.strokeJoin.toFigStrokeJoin(),
    ),
  )
  for segment in svgLayer.segments:
    let
      start = segment.start.svgLocalPoint(scaleX, scaleY)
      stop = segment.stop.svgLocalPoint(scaleX, scaleY)
    case segment.kind
    of spsLine:
      result.drawOps.add drawableDashedLineOps(
        start, stop, svgLayer.dashArray, svgLayer.dashOffset
      )
    of spsQuadratic:
      result.drawOps.add drawableBezier(
        start, segment.control1.svgLocalPoint(scaleX, scaleY), stop
      )
    of spsCubic:
      result.drawOps.add drawableBezier(
        start,
        segment.control1.svgLocalPoint(scaleX, scaleY),
        segment.control2.svgLocalPoint(scaleX, scaleY),
        stop,
      )

proc svgTransformNode(
    list: var RenderList,
    parent: FigIdx,
    target: Rect,
    documentSize: Vec2,
    transform: SvgAffineTransform,
): FigIdx =
  let
    scaleX = target.w / documentSize.x
    scaleY = target.h / documentSize.y
    translation =
      vec2(target.x + transform.tx * scaleX, target.y + transform.ty * scaleY)
  var matrix = mat4()
  matrix[0, 0] = transform.a * scaleX
  matrix[0, 1] = transform.b * scaleY
  matrix[1, 0] = transform.c * scaleX
  matrix[1, 1] = transform.d * scaleY

  list.addSvgNode(
    parent,
    Fig(
      kind: nkTransform,
      screenBox: target,
      transform:
        TransformStyle(translation: translation, matrix: matrix, useMatrix: true),
    ),
  )

proc svgPrimitiveNodes(
    list: var RenderList,
    parent: FigIdx,
    target: Rect,
    documentSize: Vec2,
    svgLayer: SvgLayer,
    fillValue: Fill,
    strokeFillValue: Fill,
): FigIdx =
  let transformIndex =
    list.svgTransformNode(parent, target, documentSize, svgLayer.transform)
  let
    shapeFill =
      if svgLayer.drawsFill:
        fillValue
      else:
        fill(rgba(0, 0, 0, 0))
    shapeStroke =
      if svgLayer.drawsStroke:
        RenderStroke(weight: svgLayer.localStrokeWidth, fill: strokeFillValue)
      else:
        RenderStroke()
    shape =
      if svgLayer.kind == slkCircle:
        figCircle(rect(-1.0'f32, -1.0'f32, 2.0'f32, 2.0'f32), shapeFill, shapeStroke)
      elif svgLayer.kind == slkEllipse:
        figEllipse(svgLayer.primitiveBounds, shapeFill, shapeStroke)
      else:
        Fig(
          kind: nkRectangle,
          screenBox: svgLayer.primitiveBounds,
          fill: shapeFill,
          stroke: shapeStroke,
        )
  list.addSvgNode(transformIndex, shape)

type SvgPaintOverride = object
  enabled: bool
  value: Fill

proc layerFill(svgLayer: SvgLayer, paintOverride: SvgPaintOverride): Fill =
  if paintOverride.enabled:
    paintOverride.value
  else:
    fill(svgLayer.paint.rgba)

proc addSvgMtsdfLayers(
    list: var RenderList,
    parent: FigIdx,
    target: Rect,
    svg: SvgMtsdfResource,
    paintOverride: SvgPaintOverride,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  if svg.layers.len == 0 or svg.size.x <= 0.0'f32 or svg.size.y <= 0.0'f32:
    return (-1).FigIdx

  result = (-1).FigIdx
  var currentParent = parent
  var parents: seq[FigIdx]
  for svgLayer in svg.layers:
    let fillValue = svgLayer.layerFill(paintOverride)
    case svgLayer.kind
    of slkGroupStart:
      parents.add currentParent
      result = list.addSvgNode(
        currentParent,
        Fig(kind: nkOpacityGroup, screenBox: target, opacity: svgLayer.groupOpacity),
      )
      currentParent = result
    of slkGroupEnd:
      if parents.len == 0:
        raise newException(SvgMtsdfError, "Unbalanced SVG opacity groups")
      currentParent = parents.pop()
    of slkMtsdfFill, slkMtsdfStroke:
      if not svgLayer.image.isNil:
        let
          layerRect = target.svgLayerRect(svg.size, svgLayer.frame)
          layerStrokeWeight =
            if svgLayer.kind == slkMtsdfStroke:
              svgLayer.mtsdfStrokeWidth *
                min(abs(target.w / svg.size.x), abs(target.h / svg.size.y))
            else:
              strokeWeight
        result = list.addSvgNode(
          currentParent,
          Fig(
            kind: nkMtsdfImage,
            screenBox: layerRect,
            mtsdfImage: MsdfImageStyle(
              id: svgLayer.image.id,
              fill: fillValue,
              pxRange: svgLayer.pixelRange,
              sdThreshold: sdThreshold,
              strokeWeight: layerStrokeWeight,
            ),
          ),
        )
    of slkStrokePath:
      let requiresUnion =
        (svgLayer.strokeCap != svcButt or svgLayer.dashArray.len > 0) and
        (fillValue.kind != flColor or fillValue.color.a < 255)
      if requiresUnion:
        let field = svgLayer.meshFallback()
        result = list.addSvgNode(
          currentParent,
          Fig(
            kind: nkMtsdfImage,
            screenBox: target.svgLayerRect(svg.size, field.frame),
            mtsdfImage: MsdfImageStyle(
              id: field.image.id,
              fill: fillValue,
              pxRange: field.pixelRange,
              sdThreshold: sdThreshold,
            ),
          ),
        )
      else:
        let transformIndex =
          list.svgTransformNode(currentParent, target, svg.size, svgLayer.transform)
        result = list.addSvgNode(
          transformIndex, target.svgPathNode(svg.size, svgLayer, fillValue)
        )
    of slkStrokeMesh:
      let screenScale = max(abs(target.w / svg.size.x), abs(target.h / svg.size.y))
      let screenWidth = svgLayer.meshStrokeWidth * screenScale
      if screenWidth > 0 and screenWidth < 2:
        let coverage = svgLayer.meshCoverage(screenScale)
        result = list.addSvgNode(
          currentParent,
          Fig(
            kind: nkImage,
            screenBox: target.svgLayerRect(svg.size, coverage.frame),
            image: imageStyle(coverage.image, fillValue),
          ),
        )
      elif fillValue.kind == flColor and fillValue.color.a == 255:
        let transformIndex =
          list.svgTransformNode(currentParent, target, svg.size, svgLayer.transform)
        result = list.addSvgNode(
          transformIndex,
          Fig(
            kind: nkDrawable,
            screenBox: rect(0, 0, svg.size.x, svg.size.y),
            fill: fillValue,
            drawOps: svgLayer.meshOps,
          ),
        )
      else:
        let field = svgLayer.meshFallback()
        result = list.addSvgNode(
          currentParent,
          Fig(
            kind: nkMtsdfImage,
            screenBox: target.svgLayerRect(svg.size, field.frame),
            mtsdfImage: MsdfImageStyle(
              id: field.image.id,
              fill: fillValue,
              pxRange: field.pixelRange,
              sdThreshold: sdThreshold,
            ),
          ),
        )
    of slkRasterGroup:
      let image =
        if paintOverride.enabled: svgLayer.tintImage else: svgLayer.rasterImage
      let tint =
        if paintOverride.enabled:
          paintOverride.value
        else:
          fill(rgba(255, 255, 255, 255))
      result = list.addSvgNode(
        currentParent,
        Fig(
          kind: nkImage,
          screenBox: target.svgLayerRect(svg.size, svgLayer.rasterFrame),
          image: imageStyle(image, tint),
        ),
      )
    of slkCircle, slkEllipse, slkRectangle:
      let strokeFillValue =
        if paintOverride.enabled:
          paintOverride.value
        else:
          fill(svgLayer.strokePaint.rgba)
      result = list.svgPrimitiveNodes(
        currentParent, target, svg.size, svgLayer, fillValue, strokeFillValue
      )

  if parents.len != 0:
    raise newException(SvgMtsdfError, "Unbalanced SVG opacity groups")

proc addSvgMtsdf*(
    list: var RenderList,
    target: Rect,
    svg: SvgMtsdfResource,
    parent = (-1).FigIdx,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  ## Appends source-colored SVG layers beneath `parent`, or as roots by default.
  ## Returns the last appended node index, or -1 for an empty resource.
  ## Keep `svg` alive while rendering: nodes borrow its image IDs.
  list.addSvgMtsdfLayers(
    parent, target, svg, SvgPaintOverride(), strokeWeight, sdThreshold
  )

proc addSvgMtsdf*(
    list: var RenderList,
    target: Rect,
    svg: SvgMtsdfResource,
    fillValue: Fill,
    parent = (-1).FigIdx,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  ## Appends SVG layers with a tint replacing every source fill and stroke.
  ## Keep `svg` alive while rendering: nodes borrow its image IDs.
  list.addSvgMtsdfLayers(
    parent,
    target,
    svg,
    SvgPaintOverride(enabled: true, value: fillValue),
    strokeWeight,
    sdThreshold,
  )
