import std/[tables, hashes]
export tables, hashes

import ./figbasics
export figbasics

type
  RenderList* = object
    nodes*: seq[Fig]
    rootIds*: seq[FigIdx]

  Renders* = ref object
    layers*: OrderedTable[ZLevel, RenderList]

  FigIdx* = distinct int16

  Fig* = object
    zlevel*: ZLevel
    parent*: FigIdx = (-1).FigIdx
    flags*: set[FigFlags]
    childCount*: int16

    screenBox*: Rect

    rotation*: float32
    fill*: Fill
    corners*: array[DirectionCorners, uint16]

    case kind*: FigKind
    of nkRectangle:
      shadows*: array[ShadowCount, RenderShadow]
      stroke*: RenderStroke
    of nkText:
      textLayout*: GlyphArrangement
      selectionRange*: Slice[int16]
    of nkDrawable:
      points*: seq[Vec2]
    of nkImage:
      image*: ImageStyle
    of nkMsdfImage:
      msdfImage*: MsdfImageStyle
    of nkMtsdfImage:
      mtsdfImage*: MsdfImageStyle
    of nkBackdropBlur:
      backdropBlur*: BackdropBlurStyle
    else:
      discard

static:
  {.warning: "Fig node size: " & $sizeof(Fig).}
  doAssert sizeof(Fig) < 256,
    "FigNode SIZE: should be smaller than 256! Got: " & $sizeof(Fig)

proc `$`*(id: FigIdx): string =
  "FigIdx(" & $(int(id)) & ")"

proc `+`*(a, b: FigIdx): FigIdx {.borrow.}
proc `<=`*(a, b: FigIdx): bool {.borrow.}
proc `==`*(a, b: FigIdx): bool {.borrow.}

proc `[]`*(r: Renders, lvl: ZLevel): RenderList =
  r.layers[lvl]

proc addRoot*(list: var RenderList, root: Fig): FigIdx {.discardable.} =
  ## Appends `root` to `list.nodes`, sets `root.parent = -1`, and adds the
  ## node index to `list.rootIds`.
  ##
  ## Returns the root's index within `list.nodes`.
  let newIdx = list.nodes.len
  assert newIdx <= high(int16).int

  var rootNode = root
  rootNode.parent = (-1).FigIdx
  list.nodes.add rootNode
  result = newIdx.FigIdx
  list.rootIds.add result

proc addChild*(
    list: var RenderList, parentIdx: FigIdx, child: Fig
): FigIdx {.discardable.} =
  ## Appends `child` to `list.nodes`, sets `child.parent` from `parentIdx`,
  ## and increments the parent's `childCount`.
  ##
  ## Returns the child's index within `list.nodes`.
  let pidx = parentIdx.int
  assert pidx >= 0 and pidx < list.nodes.len

  let newIdx = list.nodes.len
  assert newIdx <= high(int16).int

  if list.nodes[pidx].childCount == high(typeof(list.nodes[pidx].childCount)):
    raise newException(ValueError, "RenderList parent childCount overflow")
  inc list.nodes[pidx].childCount

  var childNode = child
  childNode.parent = parentIdx
  list.nodes.add childNode
  result = newIdx.FigIdx

proc ensureLayer*(renders: var Renders, lvl: ZLevel): var RenderList =
  if lvl notin renders.layers:
    renders.layers[lvl] = RenderList()
  renders.layers[lvl]

proc addRoot*(renders: var Renders, lvl: ZLevel, root: Fig): FigIdx {.discardable.} =
  ## Adds a root to the layer for `lvl`, creating the layer if needed.
  var node = root
  node.zlevel = lvl
  result = renders.ensureLayer(lvl).addRoot(node)

proc addRoot*(renders: var Renders, root: Fig): FigIdx {.discardable.} =
  ## Adds a root to the layer for `root.zlevel`.
  result = renders.addRoot(root.zlevel, root)

proc addChild*(
    renders: var Renders, lvl: ZLevel, parentIdx: FigIdx, child: Fig
): FigIdx {.discardable.} =
  ## Adds a child to the layer for `lvl`, creating the layer if needed.
  ## The child is forced to the same zlevel as its parent layer.
  var node = child
  node.zlevel = lvl
  result = renders.ensureLayer(lvl).addChild(parentIdx, node)

template pairs*(r: Renders): auto =
  r.layers.pairs()

template contains*(r: Renders, lvl: ZLevel): bool =
  r.layers.contains(lvl)

iterator childIndex*(nodes: seq[Fig], current: FigIdx): FigIdx =
  let childCnt = nodes[current.int].childCount

  var idx = current.int + 1
  var cnt = 0
  while cnt < childCnt:
    if idx >= nodes.len:
      break
    if nodes[idx.int].parent == current:
      cnt.inc()
      yield idx.FigIdx
    idx.inc()
