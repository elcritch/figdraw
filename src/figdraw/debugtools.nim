import std/[math, options]

import pkg/pixie

import ./figbackend
import ./fignodes

export options

type
  FigLocation* = object ## Identifies a Fig inside a layered render tree.
    zlevel*: ZLevel
    index*: FigIdx

  FigVisibilityReason* = enum
    fvVisible
    fvMissingLayer
    fvMissingFig
    fvDisabled
    fvNoDrawable
    fvEmptyBounds
    fvClippedOut
    fvCovered

  FigVisibility* = object
    ## Conservative visibility answer for a Fig.
    ##
    ## `approximate` is true when the answer ignores details such as rounded
    ## clip corners, rotation, transform matrices, or partial multi-node cover.
    visible*: bool
    reason*: FigVisibilityReason
    location*: FigLocation
    bounds*: Rect
    clippedBounds*: Rect
    hasClipBounds*: bool
    clipBounds*: Rect
    hasCoveredBy*: bool
    coveredBy*: FigLocation
    approximate*: bool

  FigHit* = object ## A renderable Fig whose clipped bounds contain a point.
    location*: FigLocation
    node*: Fig
    bounds*: Rect
    hasClipBounds*: bool
    clipBounds*: Rect
    clippedBounds*: Rect
    approximate*: bool

type DebugFig = object
  hit: FigHit
  disabled: bool
  drawable: bool

func isPositive(r: Rect): bool =
  r.w > 0.0'f32 and r.h > 0.0'f32

func rectContainsPoint(r: Rect, p: Vec2): bool =
  p.x >= r.x and p.y >= r.y and p.x < r.x + r.w and p.y < r.y + r.h

func rectContainsRect(outer, inner: Rect): bool =
  inner.x >= outer.x and inner.y >= outer.y and inner.x + inner.w <= outer.x + outer.w and
    inner.y + inner.h <= outer.y + outer.h

func intersectRects(a, b: Rect): Rect =
  let
    x0 = max(a.x, b.x)
    y0 = max(a.y, b.y)
    x1 = min(a.x + a.w, b.x + b.w)
    y1 = min(a.y + a.h, b.y + b.h)

  if x1 <= x0 or y1 <= y0:
    return rect(x0, y0, 0.0'f32, 0.0'f32)
  rect(x0, y0, x1 - x0, y1 - y0)

func offsetRect(r: Rect, offset: Vec2): Rect =
  rect(r.x + offset.x, r.y + offset.y, r.w, r.h)

func hasRoundedCorners(node: Fig): bool =
  for radius in node.corners:
    if radius != 0'u16:
      return true

func hasFillAlpha(fill: Fill): bool =
  case fill.kind
  of flColor:
    fill.color.a > 0'u8
  of flLinear2:
    fill.lin2.start.a > 0'u8 or fill.lin2.stop.a > 0'u8
  of flLinear3:
    fill.lin3.start.a > 0'u8 or fill.lin3.mid.a > 0'u8 or fill.lin3.stop.a > 0'u8

func isOpaqueFill(fill: Fill): bool =
  case fill.kind
  of flColor:
    fill.color.a == 255'u8
  of flLinear2:
    fill.lin2.start.a == 255'u8 and fill.lin2.stop.a == 255'u8
  of flLinear3:
    fill.lin3.start.a == 255'u8 and fill.lin3.mid.a == 255'u8 and
      fill.lin3.stop.a == 255'u8

func isDrawableNode(node: Fig): bool =
  case node.kind
  of nkFrame, nkTransform:
    false
  of nkRectangle:
    hasFillAlpha(node.fill) or node.stroke.weight > 0.0'f32
  of nkBackdropBlur:
    node.backdropBlur.blur > 0.0'f32 or hasFillAlpha(node.fill)
  else:
    true

func isOpaqueCover(node: Fig): bool =
  node.kind == nkRectangle and node.rotation == 0.0'f32 and not node.hasRoundedCorners() and
    node.stroke.weight <= 0.0'f32 and isOpaqueFill(node.fill)

func childOf(node: Fig, parentIdx: FigIdx): bool =
  node.parent == parentIdx

proc collectDebugFigs(
    list: RenderList,
    zlevel: ZLevel,
    nodeIdx: FigIdx,
    hasClip: bool,
    clipBounds: Rect,
    translation: Vec2,
    parentApproximate: bool,
    result: var seq[DebugFig],
) =
  if nodeIdx.int < 0 or nodeIdx.int >= list.nodes.len:
    return

  let node = list.nodes[nodeIdx.int]
  let location = FigLocation(zlevel: zlevel, index: nodeIdx)
  var nodeTranslation = translation
  if node.kind == nkTransform:
    nodeTranslation += node.transform.translation
  let effectiveBox = node.screenBox.offsetRect(nodeTranslation)
  if NfDisableRender in node.flags:
    result.add DebugFig(
      hit: FigHit(location: location, node: node, bounds: effectiveBox),
      disabled: true,
    )
    return

  let nodeClips = NfClipContent in node.flags or NfRectMaskContent in node.flags
  var
    nextHasClip = hasClip
    nextClip = clipBounds
    approximate =
      parentApproximate or node.rotation != 0.0'f32 or
      (nodeClips and node.hasRoundedCorners()) or
      (node.kind == nkTransform and node.transform.useMatrix)

  if nodeClips:
    if nextHasClip:
      nextClip = intersectRects(nextClip, effectiveBox)
    else:
      nextClip = effectiveBox
    nextHasClip = true

  let clipped =
    if nextHasClip:
      intersectRects(effectiveBox, nextClip)
    else:
      effectiveBox

  result.add DebugFig(
    hit: FigHit(
      location: location,
      node: node,
      bounds: effectiveBox,
      hasClipBounds: nextHasClip,
      clipBounds: nextClip,
      clippedBounds: clipped,
      approximate: approximate,
    ),
    drawable: node.isDrawableNode(),
  )

  var childIdx = nodeIdx.int + 1
  var foundChildren = 0
  while childIdx < list.nodes.len and foundChildren < node.childCount.int:
    if list.nodes[childIdx].childOf(nodeIdx):
      collectDebugFigs(
        list, zlevel, childIdx.FigIdx, nextHasClip, nextClip, nodeTranslation,
        approximate, result
      )
      inc foundChildren
    inc childIdx

proc collectDebugFigs*(list: RenderList, zlevel: ZLevel = 0.ZLevel): seq[FigHit] =
  ## Returns renderable Fig debug entries in list render order.
  ##
  ## The clipped bounds use axis-aligned rectangular clip intersections.
  var debugFigs: seq[DebugFig]
  for rootIdx in list.rootIds:
    collectDebugFigs(
      list,
      zlevel,
      rootIdx,
      hasClip = false,
      clipBounds = rect(0, 0, 0, 0),
      translation = vec2(0, 0),
      parentApproximate = false,
      debugFigs,
    )

  for item in debugFigs:
    if item.drawable and item.hit.clippedBounds.isPositive():
      result.add item.hit

proc collectDebugFigs*(renders: Renders): seq[FigHit] =
  ## Returns renderable Fig debug entries in backend render order.
  ##
  ## The clipped bounds use axis-aligned rectangular clip intersections.
  for zlevel, list in renders.layers.pairs:
    result.add list.collectDebugFigs(zlevel)

proc figVisibility*(renders: Renders, location: FigLocation): FigVisibility =
  ## Checks whether a Fig has any visible axis-aligned bounds after clipping
  ## and simple later-opaque-rectangle coverage.
  result.location = location

  if location.zlevel notin renders.layers:
    result.reason = fvMissingLayer
    return

  let list = renders.layers[location.zlevel]
  if location.index.int < 0 or location.index.int >= list.nodes.len:
    result.reason = fvMissingFig
    return

  var debugFigs: seq[DebugFig]
  for zlevel, layer in renders.layers.pairs:
    for rootIdx in layer.rootIds:
      collectDebugFigs(
        layer,
        zlevel,
        rootIdx,
        hasClip = false,
        clipBounds = rect(0, 0, 0, 0),
        translation = vec2(0, 0),
        parentApproximate = false,
        debugFigs,
      )

  var targetPos = -1
  for i, item in debugFigs:
    if item.hit.location.zlevel == location.zlevel and
        item.hit.location.index == location.index:
      targetPos = i
      result.bounds = item.hit.bounds
      result.clippedBounds = item.hit.clippedBounds
      result.hasClipBounds = item.hit.hasClipBounds
      result.clipBounds = item.hit.clipBounds
      result.approximate = item.hit.approximate
      if item.disabled:
        result.reason = fvDisabled
        return
      if not item.drawable:
        result.reason = fvNoDrawable
        return
      break

  if targetPos < 0:
    result.reason = fvMissingFig
    return

  if not result.bounds.isPositive():
    result.reason = fvEmptyBounds
    return

  if not result.clippedBounds.isPositive():
    result.reason = fvClippedOut
    return

  for i in targetPos + 1 ..< debugFigs.len:
    let item = debugFigs[i]
    if item.drawable and item.hit.clippedBounds.isPositive() and
        item.hit.node.isOpaqueCover() and
        rectContainsRect(item.hit.clippedBounds, result.clippedBounds):
      result.reason = fvCovered
      result.hasCoveredBy = true
      result.coveredBy = item.hit.location
      result.approximate = result.approximate or item.hit.approximate
      return

  result.visible = true
  result.reason = fvVisible

proc figVisibility*(renders: Renders, zlevel: ZLevel, index: FigIdx): FigVisibility =
  ## Convenience overload for `figVisibility(renders, FigLocation(...))`.
  figVisibility(renders, FigLocation(zlevel: zlevel, index: index))

proc figVisibility*(
    list: RenderList, index: FigIdx, zlevel: ZLevel = 0.ZLevel
): FigVisibility =
  ## Checks whether a Fig in a single render list is visible.
  var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  renders.layers[zlevel] = list
  renders.figVisibility(zlevel, index)

proc hitsAtPoint*(renders: Renders, point: Vec2): seq[FigHit] =
  ## Returns renderable Figs whose clipped bounds contain `point`, back to front.
  for hit in renders.collectDebugFigs():
    if rectContainsPoint(hit.clippedBounds, point):
      result.add hit

proc hitsAtPoint*(
    list: RenderList, point: Vec2, zlevel: ZLevel = 0.ZLevel
): seq[FigHit] =
  ## Returns renderable Figs in a list whose clipped bounds contain `point`.
  for hit in list.collectDebugFigs(zlevel):
    if rectContainsPoint(hit.clippedBounds, point):
      result.add hit

proc topFigAtPoint*(renders: Renders, point: Vec2): Option[FigHit] =
  ## Returns the front-most renderable Fig whose clipped bounds contain `point`.
  let hits = renders.hitsAtPoint(point)
  if hits.len > 0:
    some(hits[^1])
  else:
    none(FigHit)

proc topFigAtPoint*(
    list: RenderList, point: Vec2, zlevel: ZLevel = 0.ZLevel
): Option[FigHit] =
  ## Returns the front-most renderable Fig in a list whose bounds contain `point`.
  let hits = list.hitsAtPoint(point, zlevel)
  if hits.len > 0:
    some(hits[^1])
  else:
    none(FigHit)

func colorAt*(image: Image, x, y: int): ColorRGBA =
  ## Returns the image pixel at `x, y`, or transparent black outside the image.
  rgba(image[x, y])

func colorAt*(image: Image, point: Vec2): ColorRGBA =
  ## Returns the image pixel at `floor(point.x), floor(point.y)`.
  image.colorAt(floor(point.x).int, floor(point.y).int)

proc colorAt*(ctx: BackendContext, x, y: int, readFront: bool = true): ColorRGBA =
  ## Reads one pixel from a backend framebuffer.
  ##
  ## Call this after rendering/flushing a frame. Backends that do not support
  ## readback raise the backend's `readPixels` exception.
  let image = ctx.readPixels(rect(x.float32, y.float32, 1.0'f32, 1.0'f32), readFront)
  image.colorAt(0, 0)

proc colorAt*(ctx: BackendContext, point: Vec2, readFront: bool = true): ColorRGBA =
  ## Reads the framebuffer pixel at `floor(point.x), floor(point.y)`.
  ctx.colorAt(floor(point.x).int, floor(point.y).int, readFront)
