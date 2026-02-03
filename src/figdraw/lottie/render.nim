import std/[hashes, math, options]

import pkg/pixie
import pkg/sdfy/msdfgen

import ../fignodes
import ../common/imgutils
import ./types
import ./anim

type
  LottieResolvedTransform = object
    anchor: Vec2
    position: Vec2
    scale: Vec2
    rotation: float32
    opacity: float32

  LottieMtsdfRenderer* = object
    animation*: LottieAnimation
    pxRange*: float32
    sdThreshold*: float32

proc vec2FromSeq(vals: seq[float32], fallback: Vec2): Vec2 =
  if vals.len >= 2:
    vec2(vals[0], vals[1])
  elif vals.len == 1:
    vec2(vals[0], vals[0])
  else:
    fallback

proc colorFromSeq(vals: seq[float32], alpha: float32): Color =
  if vals.len >= 3:
    color(vals[0], vals[1], vals[2], alpha)
  else:
    color(0.0'f32, 0.0'f32, 0.0'f32, alpha)

proc resolvedTransform(tr: LottieTransform, frame: float32): LottieResolvedTransform =
  result.anchor =
    vec2FromSeq(valueAtOr(tr.a, frame, @[0.0'f32, 0.0'f32]), vec2(0.0, 0.0))
  result.position =
    vec2FromSeq(valueAtOr(tr.p, frame, @[0.0'f32, 0.0'f32]), vec2(0.0, 0.0))
  result.scale =
    vec2FromSeq(valueAtOr(tr.s, frame, @[100.0'f32, 100.0'f32]), vec2(100.0, 100.0))
  result.rotation = valueAtOr(tr.r, frame, 0.0'f32)
  result.opacity = valueAtOr(tr.o, frame, 100.0'f32)

proc resolvedTransformFromShape(shape: LottieShape, frame: float32): LottieResolvedTransform =
  result.anchor = vec2FromSeq(valueAtOr(shape.a, frame, @[0.0'f32, 0.0'f32]), vec2(0.0, 0.0))
  result.position =
    vec2FromSeq(valueAtOr(shape.p, frame, @[0.0'f32, 0.0'f32]), vec2(0.0, 0.0))
  result.scale =
    vec2FromSeq(valueAtOr(shape.s, frame, @[100.0'f32, 100.0'f32]), vec2(100.0, 100.0))
  result.rotation = valueAtOr(shape.r, frame, 0.0'f32)
  result.opacity = valueAtOr(shape.o, frame, 100.0'f32)

proc applyTransform(
    center, size: Vec2, transform: LottieResolvedTransform
): tuple[center, size: Vec2, opacity: float32] =
  let scale = vec2(transform.scale.x / 100.0'f32, transform.scale.y / 100.0'f32)
  let local = center - transform.anchor
  let angle = transform.rotation * (PI / 180.0'f32)
  let cosA = cos(angle)
  let sinA = sin(angle)
  let scaled = vec2(local.x * scale.x, local.y * scale.y)
  let rotated = vec2(
    scaled.x * cosA - scaled.y * sinA,
    scaled.x * sinA + scaled.y * cosA,
  )
  result.center = transform.position + rotated
  result.size = vec2(size.x * scale.x, size.y * scale.y)
  result.opacity = transform.opacity / 100.0'f32

proc ellipseImageId(size: Vec2): ImageId =
  let key = "lottie:ellipse:" & $size.x & "x" & $size.y
  imgId(key)

proc ensureEllipseMtsdf(
    size: Vec2, pxRange: float32
): ImageId =
  let id = ellipseImageId(size)
  if hasImage(id):
    return id

  let width = max(1, size.x.round().int)
  let height = max(1, size.y.round().int)
  var path = newPath()
  path.ellipse(vec2(size.x / 2.0'f32, size.y / 2.0'f32), size.x / 2.0'f32, size.y / 2.0'f32)

  let mtsdf = generateMtsdfPath(path, width, height, pxRange.float64)
  loadImage(id, mtsdf.image)
  id

proc renderEllipseGroup(
    list: var RenderList,
    parentIdx: FigIdx,
    layerTransform: LottieResolvedTransform,
    group: LottieShape,
    frame: float32,
    pxRange: float32,
    sdThreshold: float32,
) =
  var fillOpt: Option[LottieShape]
  var transformOpt: Option[LottieShape]
  var ellipses: seq[LottieShape]

  for item in group.it:
    case item.ty
    of "el":
      ellipses.add item
    of "fl":
      fillOpt = some(item)
    of "tr":
      transformOpt = some(item)
    else:
      discard

  if fillOpt.isNone:
    return

  let fill = fillOpt.get
  let fillOpacity = valueAtOr(fill.o, frame, 100.0'f32) / 100.0'f32
  let fillColor = colorFromSeq(valueAtOr(fill.c, frame, @[]), fillOpacity)

  var groupTransform = LottieResolvedTransform(
    anchor: vec2(0.0, 0.0),
    position: vec2(0.0, 0.0),
    scale: vec2(100.0, 100.0),
    rotation: 0.0,
    opacity: 100.0,
  )
  if transformOpt.isSome:
    groupTransform = resolvedTransformFromShape(transformOpt.get, frame)

  for ellipse in ellipses:
    let baseCenter =
      vec2FromSeq(valueAtOr(ellipse.p, frame, @[0.0'f32, 0.0'f32]), vec2(0.0, 0.0))
    let baseSize =
      vec2FromSeq(valueAtOr(ellipse.s, frame, @[0.0'f32, 0.0'f32]), vec2(0.0, 0.0))
    if baseSize.x <= 0.0'f32 or baseSize.y <= 0.0'f32:
      continue

    var tcenter = baseCenter
    var tsize = baseSize
    var topacity = 1.0'f32

    block applyGroup:
      let applied = applyTransform(tcenter, tsize, groupTransform)
      tcenter = applied.center
      tsize = applied.size
      topacity = topacity * applied.opacity

    block applyLayer:
      let applied = applyTransform(tcenter, tsize, layerTransform)
      tcenter = applied.center
      tsize = applied.size
      topacity = topacity * applied.opacity

    let imageId = ensureEllipseMtsdf(baseSize, pxRange)
    let color = color(fillColor.r, fillColor.g, fillColor.b, fillColor.a * topacity)
    let box = rect(
      tcenter.x - tsize.x / 2.0'f32,
      tcenter.y - tsize.y / 2.0'f32,
      tsize.x,
      tsize.y,
    )

    list.addChild(
      parentIdx,
      Fig(
        kind: nkMtsdfImage,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: box,
        fill: color,
        mtsdfImage: MsdfImageStyle(
          color: color,
          id: imageId,
          pxRange: pxRange,
          sdThreshold: sdThreshold,
        ),
      ),
    )

proc initLottieMtsdfRenderer*(animation: LottieAnimation,
    pxRange: float32 = 4.0'f32,
    sdThreshold: float32 = 0.5'f32,
): LottieMtsdfRenderer =
  LottieMtsdfRenderer(animation: animation, pxRange: pxRange, sdThreshold: sdThreshold)

proc renderLottieFrame*(renderer: var LottieMtsdfRenderer, frame: float32): Renders =
  var list = RenderList()
  let rootIdx = list.addRoot(
    Fig(
      kind: nkFrame,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0.0, 0.0, renderer.animation.w.float32, renderer.animation.h.float32),
      fill: color(0.0, 0.0, 0.0, 0.0),
    )
  )

  for layer in renderer.animation.layers:
    if layer.ty != 4:
      continue
    if frame < layer.ip or frame >= layer.op:
      continue

    let layerTransform = resolvedTransform(layer.ks, frame)
    for shape in layer.shapes:
      if shape.ty == "gr":
        renderEllipseGroup(
          list,
          rootIdx,
          layerTransform,
          shape,
          frame,
          renderer.pxRange,
          renderer.sdThreshold,
        )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list
