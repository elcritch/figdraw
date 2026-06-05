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
    of nkTransform:
      transform*: TransformStyle
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

proc validIdx(list: RenderList, idx: FigIdx): bool =
  idx.int >= 0 and idx.int < list.nodes.len

proc checkedFigIdx(idx: int): FigIdx =
  assert idx >= 0 and idx <= high(int16).int
  idx.FigIdx

proc checkNodeCapacity(list: RenderList, addCount: int) =
  assert addCount >= 0
  assert list.nodes.len + addCount <= high(int16).int

proc recomputeChildCounts(list: var RenderList) =
  for node in list.nodes.mitems:
    node.childCount = 0

  for node in list.nodes:
    let parentIdx = node.parent.int
    if parentIdx >= 0:
      assert parentIdx < list.nodes.len
      if list.nodes[parentIdx].childCount ==
          high(typeof(list.nodes[parentIdx].childCount)):
        raise newException(ValueError, "RenderList parent childCount overflow")
      inc list.nodes[parentIdx].childCount

proc shiftIndexes(list: var RenderList, insertIdx, count: int) =
  if count == 0:
    return

  for node in list.nodes.mitems:
    if node.parent.int >= insertIdx:
      node.parent = (node.parent.int + count).FigIdx

  for rootIdx in list.rootIds.mitems:
    if rootIdx.int >= insertIdx:
      rootIdx = (rootIdx.int + count).FigIdx

proc insertNodes(list: var RenderList, insertIdx: int, nodes: openArray[Fig]) =
  let count = nodes.len
  if count == 0:
    return

  assert insertIdx >= 0 and insertIdx <= list.nodes.len
  list.checkNodeCapacity(count)

  let oldLen = list.nodes.len
  list.nodes.setLen(oldLen + count)
  for idx in countdown(oldLen - 1, insertIdx):
    list.nodes[idx + count] = list.nodes[idx]

  for idx, node in nodes:
    list.nodes[insertIdx + idx] = node

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

proc childInsertIndex(list: RenderList, parentIdx: FigIdx, childPos: Natural): int =
  assert list.validIdx(parentIdx)

  let childCount = list.nodes[parentIdx.int].childCount.int
  assert childPos.int <= childCount
  if childPos.int == childCount:
    return list.nodes.len

  var pos = 0
  for childIdx in list.nodes.childIndex(parentIdx):
    if pos == childPos.int:
      return childIdx.int
    inc pos

  assert false

proc rootInsertIndex(list: RenderList, rootPos: Natural): int =
  assert rootPos.int <= list.rootIds.len
  if rootPos.int == list.rootIds.len:
    list.nodes.len
  else:
    list.rootIds[rootPos.int].int

proc hasRootIdx(list: RenderList, idx: int): bool =
  for rootIdx in list.rootIds:
    if rootIdx.int == idx:
      return true

proc validateRootIds(list: RenderList) =
  for rootIdx in list.rootIds:
    assert list.validIdx(rootIdx)
    assert list.nodes[rootIdx.int].parent.int < 0

  for idx, node in list.nodes:
    if node.parent.int < 0:
      assert list.hasRootIdx(idx)

proc remappedNodes(list: RenderList, insertIdx: int, parentIdx: FigIdx): seq[Fig] =
  list.validateRootIds()
  result = newSeqOfCap[Fig](list.nodes.len)
  for idx, node in list.nodes:
    var newNode = node
    if node.parent.int < 0:
      newNode.parent = parentIdx
    else:
      assert node.parent.int < list.nodes.len
      newNode.parent = checkedFigIdx(insertIdx + node.parent.int)
    result.add newNode

proc relevelNodes(nodes: var seq[Fig], lvl: ZLevel) =
  for node in nodes.mitems:
    node.zlevel = lvl

proc addRoot*(list: var RenderList, root: Fig): FigIdx {.discardable.} =
  ## Appends `root` to `list.nodes`, sets `root.parent = -1`, and adds the
  ## node index to `list.rootIds`.
  ##
  ## Cost: amortized O(1). This does not rewrite existing node indexes.
  ##
  ## Returns the root's index within `list.nodes`.
  let newIdx = list.nodes.len
  assert newIdx <= high(int16).int

  var rootNode = root
  rootNode.parent = (-1).FigIdx
  list.nodes.add rootNode
  result = newIdx.FigIdx
  list.rootIds.add result

proc insertRoot*(
    list: var RenderList, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  ## Inserts `root` into `list` at `rootPos` in root order.
  ##
  ## Existing node indexes, root indexes, and child counts are recomputed.
  ##
  ## Cost: O(n) in `list.nodes.len` because nodes may be shifted, root and
  ## parent indexes may be rewritten, and child counts are recomputed.
  let insertIdx = list.rootInsertIndex(rootPos)
  list.shiftIndexes(insertIdx, 1)

  var rootNode = root
  rootNode.parent = (-1).FigIdx
  list.insertNodes(insertIdx, [rootNode])

  result = insertIdx.FigIdx
  list.rootIds.insert(result, rootPos.int)
  list.recomputeChildCounts()

proc addChild*(
    list: var RenderList, parentIdx: FigIdx, child: Fig
): FigIdx {.discardable.} =
  ## Appends `child` to `list.nodes`, sets `child.parent` from `parentIdx`,
  ## and increments the parent's `childCount`.
  ##
  ## Cost: amortized O(1). This does not rewrite existing node indexes.
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

proc insertChild*(
    list: var RenderList, parentIdx: FigIdx, child: Fig, childPos: Natural
): FigIdx {.discardable.} =
  ## Inserts `child` under `parentIdx` at `childPos` in child order.
  ##
  ## Existing node indexes, root indexes, and child counts are recomputed.
  ##
  ## Cost: O(n) in `list.nodes.len` because the insert position is found by
  ## scanning children, nodes may be shifted, indexes may be rewritten, and
  ## child counts are recomputed.
  let insertIdx = list.childInsertIndex(parentIdx, childPos)
  list.shiftIndexes(insertIdx, 1)

  let shiftedParentIdx =
    if parentIdx.int >= insertIdx:
      (parentIdx.int + 1).FigIdx
    else:
      parentIdx

  var childNode = child
  childNode.parent = shiftedParentIdx
  list.insertNodes(insertIdx, [childNode])

  result = insertIdx.FigIdx
  list.recomputeChildCounts()

proc insertChildren*(
    list: var RenderList, parentIdx: FigIdx, children: RenderList, childPos: Natural
): seq[FigIdx] {.discardable.} =
  ## Inserts `children` under `parentIdx` at `childPos` in child order.
  ##
  ## Roots from `children.rootIds` become children of `parentIdx`. Internal
  ## child relationships from `children.nodes` are preserved.
  ##
  ## Cost: O(n + m), where `n` is `list.nodes.len` and `m` is
  ## `children.nodes.len`. Existing nodes may be shifted, destination indexes
  ## may be rewritten, inserted nodes are copied and remapped, and child counts
  ## are recomputed.
  assert list.validIdx(parentIdx)
  if children.nodes.len == 0:
    return @[]

  let insertIdx = list.childInsertIndex(parentIdx, childPos)
  list.shiftIndexes(insertIdx, children.nodes.len)

  let shiftedParentIdx =
    if parentIdx.int >= insertIdx:
      (parentIdx.int + children.nodes.len).FigIdx
    else:
      parentIdx

  let nodes = children.remappedNodes(insertIdx, shiftedParentIdx)
  list.insertNodes(insertIdx, nodes)

  for rootIdx in children.rootIds:
    assert rootIdx.int >= 0 and rootIdx.int < children.nodes.len
    result.add checkedFigIdx(insertIdx + rootIdx.int)

  list.recomputeChildCounts()

proc addChildren*(
    list: var RenderList, parentIdx: FigIdx, children: RenderList
): seq[FigIdx] {.discardable.} =
  ## Appends roots from `children.rootIds` as children of `parentIdx`.
  ##
  ## Cost: O(n + m), where `n` is `list.nodes.len` and `m` is
  ## `children.nodes.len`, because inserted nodes are copied and remapped and
  ## child counts are recomputed.
  result = list.insertChildren(
    parentIdx, children, list.nodes[parentIdx.int].childCount.Natural
  )

proc ensureLayer*(renders: var Renders, lvl: ZLevel): var RenderList =
  if lvl notin renders.layers:
    renders.layers[lvl] = RenderList()
  renders.layers[lvl]

proc addRoot*(renders: var Renders, lvl: ZLevel, root: Fig): FigIdx {.discardable.} =
  ## Adds a root to the layer for `lvl`, creating the layer if needed.
  ##
  ## Cost: amortized O(1) for the target layer, plus ordered-table lookup.
  var node = root
  node.zlevel = lvl
  result = renders.ensureLayer(lvl).addRoot(node)

proc insertRoot*(
    renders: var Renders, lvl: ZLevel, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  ## Inserts a root into the layer for `lvl`, creating the layer if needed.
  ##
  ## Cost: O(n) in the target layer's node count, plus ordered-table lookup.
  var node = root
  node.zlevel = lvl
  result = renders.ensureLayer(lvl).insertRoot(node, rootPos)

proc addRoot*(renders: var Renders, root: Fig): FigIdx {.discardable.} =
  ## Adds a root to the layer for `root.zlevel`.
  ##
  ## Cost: amortized O(1) for the target layer, plus ordered-table lookup.
  result = renders.addRoot(root.zlevel, root)

proc insertRoot*(
    renders: var Renders, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  ## Inserts a root into the layer for `root.zlevel`.
  ##
  ## Cost: O(n) in the target layer's node count, plus ordered-table lookup.
  result = renders.insertRoot(root.zlevel, root, rootPos)

proc addChild*(
    renders: var Renders, lvl: ZLevel, parentIdx: FigIdx, child: Fig
): FigIdx {.discardable.} =
  ## Adds a child to the layer for `lvl`, creating the layer if needed.
  ## The child is forced to the same zlevel as its parent layer.
  ##
  ## Cost: amortized O(1) for the target layer, plus ordered-table lookup.
  var node = child
  node.zlevel = lvl
  result = renders.ensureLayer(lvl).addChild(parentIdx, node)

proc insertChild*(
    renders: var Renders, lvl: ZLevel, parentIdx: FigIdx, child: Fig, childPos: Natural
): FigIdx {.discardable.} =
  ## Inserts a child into the layer for `lvl`, creating the layer if needed.
  ## The child is forced to the same zlevel as its parent layer.
  ##
  ## Cost: O(n) in the target layer's node count, plus ordered-table lookup.
  var node = child
  node.zlevel = lvl
  result = renders.ensureLayer(lvl).insertChild(parentIdx, node, childPos)

proc insertChildren*(
    renders: var Renders,
    lvl: ZLevel,
    parentIdx: FigIdx,
    children: RenderList,
    childPos: Natural,
): seq[FigIdx] {.discardable.} =
  ## Inserts children into the layer for `lvl`, creating the layer if needed.
  ## Inserted children are forced to the same zlevel as their parent layer.
  ##
  ## Cost: O(n + m), where `n` is the target layer's node count and `m` is
  ## `children.nodes.len`, plus ordered-table lookup.
  var nodes = children.remappedNodes(0, (-1).FigIdx)
  nodes.relevelNodes(lvl)

  var childList = RenderList(nodes: nodes, rootIds: children.rootIds)
  childList.recomputeChildCounts()
  result = renders.ensureLayer(lvl).insertChildren(parentIdx, childList, childPos)

proc addChildren*(
    renders: var Renders, lvl: ZLevel, parentIdx: FigIdx, children: RenderList
): seq[FigIdx] {.discardable.} =
  ## Appends children to the layer for `lvl`, creating the layer if needed.
  ##
  ## Cost: O(n + m), where `n` is the target layer's node count and `m` is
  ## `children.nodes.len`, plus ordered-table lookup.
  result = renders.insertChildren(
    lvl,
    parentIdx,
    children,
    renders.ensureLayer(lvl).nodes[parentIdx.int].childCount.Natural,
  )

template pairs*(r: Renders): auto =
  r.layers.pairs()

template contains*(r: Renders, lvl: ZLevel): bool =
  r.layers.contains(lvl)
