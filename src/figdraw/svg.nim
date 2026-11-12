## Draw ordered SVG fill and stroke layers using ordinary FigDraw nodes.
## Adapted from Merenda; see docs/licenses/MERENDA.txt (BSD-3-Clause).

import ./fignodes
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
    scaleX = target.w / documentSize.x
    scaleY = target.h / documentSize.y
  result = Fig(
    kind: nkDrawable,
    screenBox: target,
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
      result.drawOps.add drawableLine(start, stop)
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

proc svgCircleNodes(
    list: var RenderList,
    parent: FigIdx,
    target: Rect,
    documentSize: Vec2,
    svgLayer: SvgLayer,
    fillValue: Fill,
    strokeFillValue: Fill,
): FigIdx =
  let
    scaleX = target.w / documentSize.x
    scaleY = target.h / documentSize.y
    transform = svgLayer.transform
    translation =
      vec2(target.x + transform.tx * scaleX, target.y + transform.ty * scaleY)
  var matrix = mat4()
  matrix[0, 0] = transform.a * scaleX
  matrix[0, 1] = transform.b * scaleY
  matrix[1, 0] = transform.c * scaleX
  matrix[1, 1] = transform.d * scaleY

  let transformIndex = list.addSvgNode(
    parent,
    Fig(
      kind: nkTransform,
      screenBox: target,
      transform:
        TransformStyle(translation: translation, matrix: matrix, useMatrix: true),
    ),
  )
  var circle = Fig(
    kind: nkDrawable,
    screenBox: rect(-1.0'f32, -1.0'f32, 2.0'f32, 2.0'f32),
    fill:
      if svgLayer.drawsFill:
        fillValue
      else:
        fill(rgba(0, 0, 0, 0)),
  )
  if svgLayer.drawsStroke:
    circle.drawStroke =
      RenderStroke(weight: svgLayer.localStrokeWidth, fill: strokeFillValue)
  circle.drawOps.add drawableCircle(vec2(1.0'f32, 1.0'f32), 1.0'f32)
  list.addSvgNode(transformIndex, circle)

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
  for svgLayer in svg.layers:
    let fillValue = svgLayer.layerFill(paintOverride)
    case svgLayer.kind
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
          parent,
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
      result =
        list.addSvgNode(parent, target.svgPathNode(svg.size, svgLayer, fillValue))
    of slkCircle:
      let strokeFillValue =
        if paintOverride.enabled:
          paintOverride.value
        else:
          fill(svgLayer.strokePaint.rgba)
      result = list.svgCircleNodes(
        parent, target, svg.size, svgLayer, fillValue, strokeFillValue
      )

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
