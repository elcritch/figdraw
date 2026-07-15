import std/[tables, hashes]
export tables, hashes

import ./figbasics
export figbasics

when defined(figdrawNativeDynlib):
  {.pragma: nativeAbi, exportabi.}
else:
  {.pragma: nativeAbi.}

type
  DrawableKind* = enum
    dkLine
    dkCircle
    dkRectangle
    dkBezier
    dkArc

  DrawableOp* = object
    case kind*: DrawableKind
    of dkLine:
      a*, b*: Vec2
    of dkCircle:
      center*: Vec2
      radius*: float32
    of dkRectangle:
      box*: Rect
      corners*: CornerRadii
    of dkBezier:
      controls*: seq[Vec2]
      steps*: uint16
    of dkArc:
      arcCenter*: Vec2
      arcRadius*: float32
      startAngle*: float32
      sweepAngle*: float32
      arcSteps*: uint16

  FigIdx* = distinct int16
  FigSelectionRange* = Slice[int16]

  RenderFragment* = ref object
    list: RenderList

  RenderChildKind = enum
    rckNode
    rckFragment

  RenderChild = object
    case kind: RenderChildKind
    of rckNode:
      node: FigIdx
    of rckFragment:
      fragment: RenderFragment
      root: FigIdx

  RenderList* = object
    ## An append-only physical list plus its logical child order.
    ##
    ## `nodes` and `rootIds` retain stable local indexes. `childEntries` may
    ## contain fragment roots, which are traversed without being copied into
    ## `nodes`.
    nodes*: seq[Fig]
    rootIds*: seq[FigIdx]
    childEntries: Table[int16, seq[RenderChild]]
    rootEntries: seq[RenderChild]
    entriesReady: bool

  Renders* = ref object
    layers*: OrderedTable[ZLevel, RenderList]

  RenderCursor* = object
    ## Identifies a Fig in a layer's physical list or in one of its fragments.
    zlevel*: ZLevel
    index*: FigIdx
    fragment: RenderFragment

  Fig* = object
    zlevel*: ZLevel
    parent*: FigIdx = (-1).FigIdx
    flags*: set[FigFlags]
    childCount*: int16

    screenBox*: Rect

    rotation*: float32
    fill*: Fill
    corners*: CornerRadii

    case kind*: FigKind
    of nkRectangle:
      shadows*: array[ShadowCount, RenderShadow]
      stroke*: RenderStroke
    of nkText:
      textLayout*: GlyphArrangement
      selectionRange*: FigSelectionRange
    of nkDrawable:
      drawStroke*: RenderStroke
      drawSteps*: uint16
      drawAa*: float32
      drawOps*: seq[DrawableOp]
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

const
  DefaultDrawableBezierSteps* = 48'u16
  DefaultDrawableArcSteps* = 48'u16

proc `$`*(id: FigIdx): string =
  "FigIdx(" & $(int(id)) & ")"

proc `+`*(a, b: FigIdx): FigIdx {.borrow.}
proc `<=`*(a, b: FigIdx): bool {.borrow.}
proc `==`*(a, b: FigIdx): bool {.borrow.}

proc `==`*(a, b: RenderCursor): bool =
  a.zlevel == b.zlevel and a.index == b.index and a.fragment == b.fragment

proc nodeChild(idx: FigIdx): RenderChild =
  RenderChild(kind: rckNode, node: idx)

func entryKey(idx: FigIdx): int16 =
  cast[int16](idx)

proc fragmentChild(fragment: RenderFragment, root: FigIdx): RenderChild =
  RenderChild(kind: rckFragment, fragment: fragment, root: root)

proc resetEntries(list: var RenderList) =
  list.childEntries.clear()
  list.rootEntries.setLen(0)

proc rebuildEntries(list: var RenderList) =
  list.resetEntries()
  for idx, node in list.nodes:
    let child = idx.FigIdx.nodeChild()
    if node.parent.int < 0:
      list.rootEntries.add child
    else:
      assert node.parent.int < list.nodes.len
      list.childEntries.mgetOrPut(node.parent.entryKey(), @[]).add child
  list.entriesReady = true

proc ensureEntries(list: var RenderList) =
  if not list.entriesReady:
    list.rebuildEntries()

proc shiftEntryIndexes(list: var RenderList, insertIdx, count: int) =
  if not list.entriesReady or count == 0:
    return

  var remapped = initTable[int16, seq[RenderChild]]()
  for parentIdx, entries in list.childEntries:
    var newEntries = entries
    for entry in newEntries.mitems:
      if entry.kind == rckNode and entry.node.int >= insertIdx:
        entry.node = (entry.node.int + count).FigIdx

    let newParentIdx =
      if parentIdx.int >= insertIdx:
        (parentIdx.int + count).int16
      else:
        parentIdx
    remapped[newParentIdx] = move newEntries
  list.childEntries = move remapped

  for entry in list.rootEntries.mitems:
    if entry.kind == rckNode and entry.node.int >= insertIdx:
      entry.node = (entry.node.int + count).FigIdx

proc validIdx(list: RenderList, idx: FigIdx): bool =
  idx.int >= 0 and idx.int < list.nodes.len

proc checkedFigIdx(idx: int): FigIdx =
  assert idx >= 0 and idx <= high(int16).int
  idx.FigIdx

proc checkNodeCapacity(list: RenderList, addCount: int) =
  assert addCount >= 0
  assert list.nodes.len + addCount <= high(int16).int

proc effectiveChildCount*(list: RenderList, parentIdx: FigIdx): int =
  ## Returns the physical and fragment children of `parentIdx`.
  assert list.validIdx(parentIdx)
  if list.entriesReady:
    result = list.childEntries.getOrDefault(parentIdx.entryKey()).len
  else:
    result = list.nodes[parentIdx.int].childCount.int

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

  list.shiftEntryIndexes(insertIdx, count)

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

template pairs*(r: Renders): auto =
  r.layers.pairs()

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

{.push nativeAbi.}

proc drawableLine*(a, b: Vec2): DrawableOp =
  DrawableOp(kind: dkLine, a: a, b: b)

proc drawableLine*(x1: float32, y1: float32, x2: float32, y2: float32): DrawableOp =
  drawableLine(vec2(x1, y1), vec2(x2, y2))

proc drawableCircle*(center: Vec2, radius: float32): DrawableOp =
  DrawableOp(kind: dkCircle, center: center, radius: radius)

proc drawableCircle*(x: float32, y: float32, radius: float32): DrawableOp =
  drawableCircle(vec2(x, y), radius)

proc drawableRect*(
    box: Rect, corners: CornerRadii = [0'u16, 0'u16, 0'u16, 0'u16]
): DrawableOp =
  DrawableOp(kind: dkRectangle, box: box, corners: corners)

proc drawableBezier*(controls: openArray[Vec2], steps: uint16): DrawableOp =
  ## Creates a stroked Bezier drawable op.
  ## `steps = 0` inherits the owning `nkDrawable.drawSteps` or uses adaptive spans.
  DrawableOp(kind: dkBezier, controls: @controls, steps: steps)

proc drawableBezier*(controls: openArray[Vec2]): DrawableOp =
  drawableBezier(controls, 0)

proc drawableBezier*(p0, p1, p2: Vec2, steps: uint16): DrawableOp =
  drawableBezier([p0, p1, p2], steps)

proc drawableBezier*(p0, p1, p2: Vec2): DrawableOp =
  drawableBezier(p0, p1, p2, 0)

proc drawableBezier*(p0, p1, p2, p3: Vec2, steps: uint16): DrawableOp =
  drawableBezier([p0, p1, p2, p3], steps)

proc drawableBezier*(p0, p1, p2, p3: Vec2): DrawableOp =
  drawableBezier(p0, p1, p2, p3, 0'u16)

proc drawableArc*(
    center: Vec2,
    radius: float32,
    startAngle: float32,
    sweepAngle: float32,
    steps: uint16,
): DrawableOp =
  ## Creates a stroked circular arc drawable op. Angles are radians.
  ## `steps = 0` inherits the owning `nkDrawable.drawSteps` or uses adaptive spans.
  DrawableOp(
    kind: dkArc,
    arcCenter: center,
    arcRadius: radius,
    startAngle: startAngle,
    sweepAngle: sweepAngle,
    arcSteps: steps,
  )

proc drawableArc*(
    center: Vec2, radius: float32, startAngle: float32, sweepAngle: float32
): DrawableOp =
  drawableArc(center, radius, startAngle, sweepAngle, 0'u16)

proc drawableArc*(
    x, y, radius, startAngle, sweepAngle: float32, steps: uint16
): DrawableOp =
  drawableArc(vec2(x, y), radius, startAngle, sweepAngle, steps)

proc drawableArc*(x, y, radius, startAngle, sweepAngle: float32): DrawableOp =
  drawableArc(vec2(x, y), radius, startAngle, sweepAngle, 0)

proc clear*(list: var RenderList) =
  list.nodes.setLen(0)
  list.rootIds.setLen(0)
  list.resetEntries()
  list.entriesReady = true

func len*(list: RenderList): int =
  list.nodes.len

proc addRoot*(list: var RenderList, root: Fig): FigIdx {.discardable.} =
  ## Appends `root` to `list.nodes`, sets `root.parent = -1`, and adds the
  ## node index to `list.rootIds`.
  ##
  ## Cost: amortized O(1). This does not rewrite existing node indexes.
  ##
  ## Returns the root's index within `list.nodes`.
  list.ensureEntries()
  let newIdx = list.nodes.len
  assert newIdx <= high(int16).int

  var rootNode = root
  rootNode.parent = (-1).FigIdx
  list.nodes.add rootNode
  result = newIdx.FigIdx
  list.rootIds.add result
  list.rootEntries.add result.nodeChild()

proc insertRoot*(
    list: var RenderList, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  ## Inserts `root` into `list` at `rootPos` in root order.
  ##
  ## Existing node indexes, root indexes, and child counts are recomputed.
  ##
  ## Cost: O(n) in `list.nodes.len` because nodes may be shifted, root and
  ## parent indexes may be rewritten, and child counts are recomputed.
  list.ensureEntries()
  let insertIdx = list.rootInsertIndex(rootPos)
  list.shiftIndexes(insertIdx, 1)

  var rootNode = root
  rootNode.parent = (-1).FigIdx
  list.insertNodes(insertIdx, [rootNode])

  result = insertIdx.FigIdx
  list.rootIds.insert(result, rootPos.int)
  list.rootEntries.insert(result.nodeChild(), rootPos.int)
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
  list.ensureEntries()
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
  list.childEntries.mgetOrPut(parentIdx.entryKey(), @[]).add result.nodeChild()

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
  list.ensureEntries()
  assert childPos.int <= list.effectiveChildCount(parentIdx)

  let physicalChildCount = list.nodes[parentIdx.int].childCount.int
  let insertIdx =
    if childPos.int <= physicalChildCount:
      list.childInsertIndex(parentIdx, childPos)
    else:
      list.nodes.len
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
  list.childEntries.mgetOrPut(shiftedParentIdx.entryKey(), @[]).insert(
    result.nodeChild(), childPos.int
  )
  list.recomputeChildCounts()

proc insertFragment(
    list: var RenderList,
    parentIdx: FigIdx,
    children: sink RenderList,
    childPos: Natural,
): RenderFragment =
  list.ensureEntries()
  assert list.validIdx(parentIdx)
  assert childPos.int <= list.effectiveChildCount(parentIdx)

  children.ensureEntries()
  children.validateRootIds()
  if children.rootEntries.len == 0:
    return nil

  result = RenderFragment(list: move children)
  var fragmentRoots = newSeqOfCap[RenderChild](result.list.rootEntries.len)
  for root in result.list.rootEntries:
    case root.kind
    of rckNode:
      fragmentRoots.add result.fragmentChild(root.node)
    of rckFragment:
      fragmentRoots.add root.fragment.fragmentChild(root.root)
  for offset, root in fragmentRoots:
    list.childEntries.mgetOrPut(parentIdx.entryKey(), @[]).insert(
      root, childPos.int + offset
    )

proc insertChildren*(
    list: var RenderList,
    parentIdx: FigIdx,
    children: sink RenderList,
    childPos: Natural,
): seq[FigIdx] {.discardable.} =
  ## Inserts `children` under `parentIdx` without shifting physical nodes.
  ##
  ## The incoming roots become a fragment branch at `childPos`. Rendering
  ## traverses that branch in place, while `nodes` and existing `FigIdx` values
  ## remain stable.
  ##
  ## The returned indexes are local to the inserted fragment. Use the `Renders`
  ## overload when fragment cursors are needed for traversal.
  let fragment = list.insertFragment(parentIdx, move children, childPos)
  if fragment.isNil:
    return @[]
  fragment.list.rootIds

proc addChildren*(
    list: var RenderList, parentIdx: FigIdx, children: sink RenderList
): seq[FigIdx] {.discardable.} =
  ## Physically appends roots from `children` as children of `parentIdx`.
  ##
  ## Cost: O(m), where `m` is `children.nodes.len`. Existing indexes are not
  ## shifted. Use `insertChildren` to add a non-owning fragment branch.
  list.ensureEntries()
  assert list.validIdx(parentIdx)
  children.ensureEntries()
  children.validateRootIds()
  if children.nodes.len == 0:
    return @[]

  list.checkNodeCapacity(children.nodes.len)
  let base = list.nodes.len
  let remapped = children.remappedNodes(base, parentIdx)
  for node in remapped:
    list.nodes.add node

  for root in children.rootEntries:
    case root.kind
    of rckNode:
      let appendedIdx = (base + root.node.int).FigIdx
      list.childEntries.mgetOrPut(parentIdx.entryKey(), @[]).add appendedIdx.nodeChild()
      if list.nodes[parentIdx.int].childCount ==
          high(typeof(list.nodes[parentIdx.int].childCount)):
        raise newException(ValueError, "RenderList parent childCount overflow")
      inc list.nodes[parentIdx.int].childCount
      result.add appendedIdx
    of rckFragment:
      list.childEntries.mgetOrPut(parentIdx.entryKey(), @[]).add(
        root.fragment.fragmentChild(root.root)
      )

  for sourceParentIdx, entries in children.childEntries:
    let destinationParentIdx = (base + sourceParentIdx.int).int16
    var destinationEntries = newSeqOfCap[RenderChild](entries.len)
    for entry in entries:
      case entry.kind
      of rckNode:
        destinationEntries.add (base + entry.node.int).FigIdx.nodeChild()
      of rckFragment:
        destinationEntries.add entry.fragment.fragmentChild(entry.root)
    list.childEntries[destinationParentIdx] = move destinationEntries

proc relevelList(list: var RenderList, lvl: ZLevel) =
  for node in list.nodes.mitems:
    node.zlevel = lvl

  for _, entries in list.childEntries.mpairs:
    for entry in entries:
      if entry.kind == rckFragment:
        entry.fragment.list.relevelList(lvl)

proc makeCursor(
    zlevel: ZLevel, index: FigIdx, fragment: RenderFragment = nil
): RenderCursor =
  RenderCursor(zlevel: zlevel, index: index, fragment: fragment)

proc `[]`*(renders: Renders, lvl: ZLevel): var RenderList =
  if lvl notin renders.layers:
    renders.layers[lvl] = RenderList()
  renders.layers[lvl]

template `[]`*(renders: Renders, cursor: RenderCursor): untyped =
  ## Returns the Fig designated by `cursor`.
  if cursor.fragment.isNil:
    renders.layers[cursor.zlevel].nodes[cursor.index.int]
  else:
    cursor.fragment.list.nodes[cursor.index.int]

iterator roots*(renders: Renders, lvl: ZLevel): RenderCursor =
  ## Iterates layer roots in render order, including fragment roots.
  renders[lvl].ensureEntries()
  for entry in renders[lvl].rootEntries:
    case entry.kind
    of rckNode:
      yield makeCursor(lvl, entry.node)
    of rckFragment:
      yield makeCursor(lvl, entry.root, entry.fragment)

iterator children*(renders: Renders, parent: RenderCursor): RenderCursor =
  ## Iterates direct children in render order without scanning descendants.
  if parent.fragment.isNil:
    renders[parent.zlevel].ensureEntries()
    for entry in renders[parent.zlevel].childEntries.getOrDefault(
      parent.index.entryKey()
    ):
      case entry.kind
      of rckNode:
        yield makeCursor(parent.zlevel, entry.node)
      of rckFragment:
        yield makeCursor(parent.zlevel, entry.root, entry.fragment)
  else:
    parent.fragment.list.ensureEntries()
    for entry in parent.fragment.list.childEntries.getOrDefault(parent.index.entryKey()):
      case entry.kind
      of rckNode:
        yield makeCursor(parent.zlevel, entry.node, parent.fragment)
      of rckFragment:
        yield makeCursor(parent.zlevel, entry.root, entry.fragment)

proc newRenders*(): Renders =
  Renders(layers: initOrderedTable[ZLevel, RenderList]())

proc setLayer*(renders: Renders, lvl: ZLevel, list: RenderList) =
  renders.layers[lvl] = list

proc clear*(renders: Renders) =
  renders.layers.clear()

func len*(renders: Renders, lvl: ZLevel): int =
  if lvl in renders.layers:
    renders.layers[lvl].nodes.len
  else:
    0

proc addRoot*(renders: Renders, lvl: ZLevel, root: Fig): FigIdx {.discardable.} =
  ## Adds a root to the layer for `lvl`, creating the layer if needed.
  ##
  ## Cost: amortized O(1) for the target layer, plus ordered-table lookup.
  var node = root
  node.zlevel = lvl
  result = renders[lvl].addRoot(node)

proc insertRoot*(
    renders: Renders, lvl: ZLevel, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  ## Inserts a root into the layer for `lvl`, creating the layer if needed.
  ##
  ## Cost: O(n) in the target layer's node count, plus ordered-table lookup.
  var node = root
  node.zlevel = lvl
  result = renders[lvl].insertRoot(node, rootPos)

proc addRoot*(renders: Renders, root: Fig): FigIdx {.discardable.} =
  ## Adds a root to the layer for `root.zlevel`.
  ##
  ## Cost: amortized O(1) for the target layer, plus ordered-table lookup.
  result = renders.addRoot(root.zlevel, root)

proc insertRoot*(
    renders: Renders, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  ## Inserts a root into the layer for `root.zlevel`.
  ##
  ## Cost: O(n) in the target layer's node count, plus ordered-table lookup.
  result = renders.insertRoot(root.zlevel, root, rootPos)

proc addChild*(
    renders: Renders, lvl: ZLevel, parentIdx: FigIdx, child: Fig
): FigIdx {.discardable.} =
  ## Adds a child to the layer for `lvl`, creating the layer if needed.
  ## The child is forced to the same zlevel as its parent layer.
  ##
  ## Cost: amortized O(1) for the target layer, plus ordered-table lookup.
  var node = child
  node.zlevel = lvl
  result = renders[lvl].addChild(parentIdx, node)

proc addChild*(
    renders: Renders, parent: RenderCursor, child: Fig
): RenderCursor {.discardable.} =
  ## Physically appends a child to a node in the main list or a fragment.
  var node = child
  node.zlevel = parent.zlevel
  if parent.fragment.isNil:
    let index = renders[parent.zlevel].addChild(parent.index, node)
    return makeCursor(parent.zlevel, index)

  let index = parent.fragment.list.addChild(parent.index, node)
  makeCursor(parent.zlevel, index, parent.fragment)

proc insertChild*(
    renders: Renders, lvl: ZLevel, parentIdx: FigIdx, child: Fig, childPos: Natural
): FigIdx {.discardable.} =
  ## Inserts a child into the layer for `lvl`, creating the layer if needed.
  ## The child is forced to the same zlevel as its parent layer.
  ##
  ## Cost: O(n) in the target layer's node count, plus ordered-table lookup.
  var node = child
  node.zlevel = lvl
  result = renders[lvl].insertChild(parentIdx, node, childPos)

proc insertChildren*(
    renders: Renders,
    lvl: ZLevel,
    parentIdx: FigIdx,
    children: sink RenderList,
    childPos: Natural,
): seq[RenderCursor] {.discardable.} =
  ## Adds a fragment branch to the layer for `lvl` without shifting node indexes.
  ##
  ## The returned cursors identify the inserted fragment roots.
  children.relevelList(lvl)
  let fragment = renders[lvl].insertFragment(parentIdx, move children, childPos)
  if fragment.isNil:
    return @[]
  for root in fragment.list.rootEntries:
    case root.kind
    of rckNode:
      result.add makeCursor(lvl, root.node, fragment)
    of rckFragment:
      result.add makeCursor(lvl, root.root, root.fragment)

proc insertChildren*(
    renders: Renders, parent: RenderCursor, children: sink RenderList, childPos: Natural
): seq[RenderCursor] {.discardable.} =
  ## Adds a fragment branch below a node in the main list or another fragment.
  children.relevelList(parent.zlevel)
  if parent.fragment.isNil:
    return renders.insertChildren(parent.zlevel, parent.index, move children, childPos)

  let fragment =
    parent.fragment.list.insertFragment(parent.index, move children, childPos)
  if fragment.isNil:
    return @[]
  for root in fragment.list.rootEntries:
    case root.kind
    of rckNode:
      result.add makeCursor(parent.zlevel, root.node, fragment)
    of rckFragment:
      result.add makeCursor(parent.zlevel, root.root, root.fragment)

proc addChildren*(
    renders: Renders, lvl: ZLevel, parentIdx: FigIdx, children: sink RenderList
): seq[FigIdx] {.discardable.} =
  ## Physically appends children to the layer for `lvl` without shifting indexes.
  children.relevelList(lvl)
  renders[lvl].addChildren(parentIdx, move children)

proc addChildren*(
    renders: Renders, parent: RenderCursor, children: sink RenderList
): seq[RenderCursor] {.discardable.} =
  ## Physically appends children to a node in the main list or a fragment.
  children.relevelList(parent.zlevel)
  if parent.fragment.isNil:
    for index in renders[parent.zlevel].addChildren(parent.index, move children):
      result.add makeCursor(parent.zlevel, index)
  else:
    for index in parent.fragment.list.addChildren(parent.index, move children):
      result.add makeCursor(parent.zlevel, index, parent.fragment)

proc contains*(r: Renders, lvl: ZLevel): bool =
  r.layers.contains(lvl)

{.pop.}
