import std/tables

import ./fignodes

type
  RenderFragmentError* = object of CatchableError

  RenderFragmentStatus* = enum
    rfsValid
    rfsForeignTree
    rfsStaleTree
    rfsStaleLayer
    rfsDetached
    rfsStaleFragment

  RenderChildKind = enum
    rckNode
    rckFragment

  RenderChild = object
    case kind: RenderChildKind
    of rckNode:
      node: FigIdx
    of rckFragment:
      fragment: RenderFragment

  RenderEntries = object
    childEntries: Table[int16, seq[RenderChild]]
    rootEntries: seq[RenderChild]
    ready: bool

  RenderFragment = ref object
    id: uint64
    list: RenderList
    entries: RenderEntries
    zlevel: ZLevel
    generation: uint64
    nodeGeneration: uint64
    attached: bool

  RenderFragments* = ref object
    ## A render tree containing independently replaceable logical subtrees.
    ##
    ## Fragment edges are stored separately from physical `RenderList` nodes, so
    ## replacement does not change indexes in the surrounding lists.
    base: Renders
    layerEntries: OrderedTable[ZLevel, RenderEntries]
    layerGenerations: Table[ZLevel, uint64]
    baseNodeGenerations: Table[ZLevel, uint64]
    treeGeneration: uint64
    nextFragmentId: uint64

  RenderFragmentHandle* = object
    ## Opaque identity for one attached, independently replaceable subtree.
    owner: RenderFragments
    treeGeneration: uint64
    layerGeneration: uint64
    fragmentGeneration: uint64
    fragment: RenderFragment

  RenderCursor* = object ## Identifies a Fig in a particular version of a render tree.
    zlevel*: ZLevel
    index*: FigIdx
    owner: RenderFragments
    treeGeneration: uint64
    layerGeneration: uint64
    nodeGeneration: uint64
    fragment: RenderFragment

  RenderInput* = Renders | RenderFragments

proc `==`*(a, b: RenderFragmentHandle): bool =
  a.owner == b.owner and a.treeGeneration == b.treeGeneration and
    a.layerGeneration == b.layerGeneration and
    a.fragmentGeneration == b.fragmentGeneration and a.fragment == b.fragment

proc `==`*(a, b: RenderCursor): bool =
  a.zlevel == b.zlevel and a.index == b.index and a.owner == b.owner and
    a.treeGeneration == b.treeGeneration and a.layerGeneration == b.layerGeneration and
    a.nodeGeneration == b.nodeGeneration and a.fragment == b.fragment

func entryKey(idx: FigIdx): int16 =
  idx.int.int16

proc nodeChild(idx: FigIdx): RenderChild =
  RenderChild(kind: rckNode, node: idx)

proc fragmentChild(fragment: RenderFragment): RenderChild =
  RenderChild(kind: rckFragment, fragment: fragment)

proc validIdx(list: RenderList, idx: FigIdx): bool =
  idx.int >= 0 and idx.int < list.nodes.len

proc checkedFigIdx(idx: int): FigIdx =
  if idx < 0 or idx > high(int16).int:
    raise newException(RenderFragmentError, "RenderList node index is out of range")
  idx.FigIdx

proc invalidRenderList(message: string) {.noinline, noreturn.} =
  raise newException(RenderFragmentError, message)

proc validateRootIds(list: RenderList) =
  var roots = newSeq[bool](list.nodes.len)
  for rootIdx in list.rootIds:
    if not list.validIdx(rootIdx):
      invalidRenderList("RenderList contains an invalid root index")
    if list.nodes[rootIdx.int].parent.int >= 0:
      invalidRenderList("RenderList root has a parent")
    if roots[rootIdx.int]:
      invalidRenderList("RenderList contains a duplicate root index")
    roots[rootIdx.int] = true

  for idx, node in list.nodes:
    if node.parent.int < 0:
      if not roots[idx]:
        invalidRenderList("RenderList omits a root node from rootIds")
    elif not list.validIdx(node.parent):
      invalidRenderList("RenderList node has an invalid parent index")

proc rebuildEntries(list: RenderList, entries: var RenderEntries) =
  entries.childEntries.clear()
  entries.rootEntries.setLen(0)
  for idx, node in list.nodes:
    let child = idx.FigIdx.nodeChild()
    if node.parent.int < 0:
      entries.rootEntries.add child
    else:
      entries.childEntries.mgetOrPut(node.parent.entryKey(), @[]).add child
  entries.ready = true

proc ensureEntries(list: RenderList, entries: var RenderEntries) =
  if not entries.ready:
    list.validateRootIds()
    list.rebuildEntries(entries)

proc reset(entries: var RenderEntries) =
  entries.childEntries.clear()
  entries.rootEntries.setLen(0)
  entries.ready = false

proc shiftEntryIndexes(entries: var RenderEntries, insertIdx, count: int) =
  if not entries.ready or count == 0:
    return

  var remapped = initTable[int16, seq[RenderChild]]()
  for parentIdx, currentEntries in entries.childEntries:
    var newEntries = currentEntries
    for entry in newEntries.mitems:
      if entry.kind == rckNode and entry.node.int >= insertIdx:
        entry.node = (entry.node.int + count).FigIdx

    let newParentIdx =
      if parentIdx.int >= insertIdx:
        (parentIdx.int + count).int16
      else:
        parentIdx
    remapped[newParentIdx] = move newEntries
  entries.childEntries = move remapped

  for entry in entries.rootEntries.mitems:
    if entry.kind == rckNode and entry.node.int >= insertIdx:
      entry.node = (entry.node.int + count).FigIdx

proc cloneRenderList(list: RenderList): RenderList =
  result.nodes = newSeqOfCap[Fig](list.nodes.len)
  for node in list.nodes:
    result.nodes.add node
  result.rootIds = newSeqOfCap[FigIdx](list.rootIds.len)
  for root in list.rootIds:
    result.rootIds.add root

proc cloneRenders(renders: Renders): Renders =
  result = newRenders()
  for lvl, list in renders.pairs():
    result.setLayer(lvl, list.cloneRenderList())

proc relevelList(list: var RenderList, lvl: ZLevel) =
  for node in list.nodes.mitems:
    node.zlevel = lvl

proc ensureLayer(fragments: RenderFragments, lvl: ZLevel) =
  if lvl notin fragments.base.layers:
    fragments.base.layers[lvl] = RenderList()
  if lvl notin fragments.layerEntries:
    fragments.layerEntries[lvl] = RenderEntries()
  if lvl notin fragments.layerGenerations:
    fragments.layerGenerations[lvl] = 1
  if lvl notin fragments.baseNodeGenerations:
    fragments.baseNodeGenerations[lvl] = 1
  fragments.base.layers[lvl].ensureEntries(fragments.layerEntries[lvl])

proc layerGeneration(fragments: RenderFragments, lvl: ZLevel): uint64 =
  fragments.layerGenerations.getOrDefault(lvl)

proc baseNodeGeneration(fragments: RenderFragments, lvl: ZLevel): uint64 =
  fragments.baseNodeGenerations.getOrDefault(lvl)

proc advance(value: var uint64) =
  inc value
  if value == 0:
    value = 1

proc makeRendersCursor(zlevel: ZLevel, index: FigIdx): RenderCursor =
  RenderCursor(zlevel: zlevel, index: index)

proc makeBaseCursor(
    fragments: RenderFragments, zlevel: ZLevel, index: FigIdx
): RenderCursor =
  RenderCursor(
    zlevel: zlevel,
    index: index,
    owner: fragments,
    treeGeneration: fragments.treeGeneration,
    layerGeneration: fragments.layerGeneration(zlevel),
    nodeGeneration: fragments.baseNodeGeneration(zlevel),
  )

proc makeFragmentCursor(
    fragments: RenderFragments, fragment: RenderFragment, index: FigIdx
): RenderCursor =
  RenderCursor(
    zlevel: fragment.zlevel,
    index: index,
    owner: fragments,
    treeGeneration: fragments.treeGeneration,
    layerGeneration: fragments.layerGeneration(fragment.zlevel),
    nodeGeneration: fragment.nodeGeneration,
    fragment: fragment,
  )

proc makeHandle(
    fragments: RenderFragments, fragment: RenderFragment
): RenderFragmentHandle =
  RenderFragmentHandle(
    owner: fragments,
    treeGeneration: fragments.treeGeneration,
    layerGeneration: fragments.layerGeneration(fragment.zlevel),
    fragmentGeneration: fragment.generation,
    fragment: fragment,
  )

proc handleStatus*(
    fragments: RenderFragments, handle: RenderFragmentHandle
): RenderFragmentStatus =
  if fragments.isNil or handle.owner != fragments:
    return rfsForeignTree
  if handle.treeGeneration != fragments.treeGeneration:
    return rfsStaleTree
  if handle.fragment.isNil:
    return rfsDetached
  if handle.layerGeneration != fragments.layerGeneration(handle.fragment.zlevel):
    return rfsStaleLayer
  if not handle.fragment.attached:
    return rfsDetached
  if handle.fragmentGeneration != handle.fragment.generation:
    return rfsStaleFragment
  rfsValid

proc isValid*(fragments: RenderFragments, handle: RenderFragmentHandle): bool =
  fragments.handleStatus(handle) == rfsValid

proc statusMessage(status: RenderFragmentStatus): string =
  case status
  of rfsValid: "valid fragment handle"
  of rfsForeignTree: "fragment handle belongs to another render tree"
  of rfsStaleTree: "fragment handle predates a render tree clear"
  of rfsStaleLayer: "fragment handle predates a layer replacement"
  of rfsDetached: "fragment handle is detached"
  of rfsStaleFragment: "fragment handle refers to an older fragment version"

proc requireHandle(fragments: RenderFragments, handle: RenderFragmentHandle) =
  let status = fragments.handleStatus(handle)
  if status != rfsValid:
    raise newException(RenderFragmentError, status.statusMessage())

proc requireCursor(fragments: RenderFragments, cursor: RenderCursor) =
  if fragments.isNil or cursor.owner != fragments:
    raise newException(RenderFragmentError, "render cursor belongs to another tree")
  if cursor.treeGeneration != fragments.treeGeneration:
    raise newException(RenderFragmentError, "render cursor predates a tree clear")
  if cursor.layerGeneration != fragments.layerGeneration(cursor.zlevel):
    raise
      newException(RenderFragmentError, "render cursor predates a layer replacement")

  if cursor.fragment.isNil:
    if cursor.nodeGeneration != fragments.baseNodeGeneration(cursor.zlevel):
      raise newException(RenderFragmentError, "render cursor has a stale node index")
    if cursor.zlevel notin fragments.base.layers or
        not fragments.base.layers[cursor.zlevel].validIdx(cursor.index):
      raise newException(RenderFragmentError, "render cursor has an invalid node index")
  else:
    if not cursor.fragment.attached:
      raise newException(
        RenderFragmentError, "render cursor belongs to a detached fragment"
      )
    if cursor.fragment.zlevel != cursor.zlevel or
        cursor.nodeGeneration != cursor.fragment.nodeGeneration:
      raise
        newException(RenderFragmentError, "render cursor has a stale fragment version")
    if not cursor.fragment.list.validIdx(cursor.index):
      raise newException(RenderFragmentError, "render cursor has an invalid node index")

proc fragmentHandle*(cursor: RenderCursor): RenderFragmentHandle =
  if cursor.owner.isNil or cursor.fragment.isNil:
    raise
      newException(RenderFragmentError, "render cursor does not identify a fragment")
  cursor.owner.requireCursor(cursor)
  cursor.owner.makeHandle(cursor.fragment)

proc fragmentId*(handle: RenderFragmentHandle): uint64 =
  if handle.fragment.isNil:
    return 0
  handle.fragment.id

proc expandedCount(fragments: RenderFragments, entries: openArray[RenderChild]): int =
  for entry in entries:
    case entry.kind
    of rckNode:
      inc result
    of rckFragment:
      if entry.fragment.attached:
        result += entry.fragment.entries.rootEntries.len

proc detachFragment(fragment: RenderFragment)

proc detachFragments(entries: RenderEntries) =
  for entry in entries.rootEntries:
    if entry.kind == rckFragment:
      entry.fragment.detachFragment()
  for _, children in entries.childEntries:
    for entry in children:
      if entry.kind == rckFragment:
        entry.fragment.detachFragment()

proc detachFragment(fragment: RenderFragment) =
  if fragment.isNil or not fragment.attached:
    return
  fragment.entries.detachFragments()
  fragment.attached = false
  fragment.generation.advance()
  fragment.nodeGeneration.advance()

proc newFragment(
    fragments: RenderFragments, lvl: ZLevel, contents: sink RenderList
): RenderFragment =
  contents.relevelList(lvl)
  contents.validateRootIds()
  var entries: RenderEntries
  contents.rebuildEntries(entries)
  result = RenderFragment(
    id: fragments.nextFragmentId,
    list: move contents,
    entries: move entries,
    zlevel: lvl,
    generation: 1,
    nodeGeneration: 1,
    attached: true,
  )
  fragments.nextFragmentId.advance()

proc newRenderFragments*(): RenderFragments =
  RenderFragments(
    base: newRenders(),
    layerEntries: initOrderedTable[ZLevel, RenderEntries](),
    layerGenerations: initTable[ZLevel, uint64](),
    baseNodeGenerations: initTable[ZLevel, uint64](),
    treeGeneration: 1,
    nextFragmentId: 1,
  )

proc newRenderFragments*(renders: Renders): RenderFragments =
  ## Copies an existing render tree so later external mutations cannot invalidate
  ## fragment traversal metadata.
  if renders.isNil:
    raise newException(RenderFragmentError, "cannot copy a nil Renders tree")
  result = newRenderFragments()
  result.base = renders.cloneRenders()
  for lvl, _ in result.base.pairs():
    result.ensureLayer(lvl)

proc clear*(fragments: RenderFragments) =
  for _, entries in fragments.layerEntries:
    entries.detachFragments()
  fragments.treeGeneration.advance()
  fragments.base.clear()
  fragments.layerEntries.clear()
  fragments.layerGenerations.clear()
  fragments.baseNodeGenerations.clear()

func len*(fragments: RenderFragments, lvl: ZLevel): int =
  fragments.base.len(lvl)

proc contains*(fragments: RenderFragments, lvl: ZLevel): bool =
  fragments.base.contains(lvl)

proc effectiveChildCount*(
    fragments: RenderFragments, lvl: ZLevel, parentIdx: FigIdx
): int =
  fragments.ensureLayer(lvl)
  if not fragments.base.layers[lvl].validIdx(parentIdx):
    raise newException(RenderFragmentError, "parent node index is out of range")
  let children =
    fragments.layerEntries[lvl].childEntries.getOrDefault(parentIdx.entryKey())
  fragments.expandedCount(children)

proc effectiveChildCount*(fragments: RenderFragments, parent: RenderCursor): int =
  fragments.requireCursor(parent)
  if parent.fragment.isNil:
    return fragments.effectiveChildCount(parent.zlevel, parent.index)
  parent.fragment.list.ensureEntries(parent.fragment.entries)
  let children =
    parent.fragment.entries.childEntries.getOrDefault(parent.index.entryKey())
  fragments.expandedCount(children)

template pairs*(fragments: RenderFragments): auto =
  fragments.base.layers.pairs()

proc `[]`*(fragments: RenderFragments, lvl: ZLevel): lent RenderList =
  if fragments.isNil or lvl notin fragments.base.layers:
    raise newException(KeyError, "render layer does not exist")
  fragments.base.layers[lvl]

proc setLayer*(fragments: RenderFragments, lvl: ZLevel, list: sink RenderList) =
  if lvl in fragments.layerEntries:
    fragments.layerEntries[lvl].detachFragments()

  list.relevelList(lvl)
  list.validateRootIds()
  fragments.base.setLayer(lvl, move list)
  fragments.layerEntries.mgetOrPut(lvl, RenderEntries()).reset()
  fragments.layerGenerations.mgetOrPut(lvl, 1).advance()
  fragments.baseNodeGenerations.mgetOrPut(lvl, 1).advance()
  fragments.ensureLayer(lvl)

proc `[]`*(renders: Renders, cursor: RenderCursor): lent Fig =
  if not cursor.owner.isNil or not cursor.fragment.isNil:
    raise newException(RenderFragmentError, "fragment cursor cannot index Renders")
  renders.layers[cursor.zlevel].nodes[cursor.index.int]

proc `[]`*(fragments: RenderFragments, cursor: RenderCursor): lent Fig =
  fragments.requireCursor(cursor)
  if cursor.fragment.isNil:
    return fragments.base.layers[cursor.zlevel].nodes[cursor.index.int]
  cursor.fragment.list.nodes[cursor.index.int]

proc nodeCursor*(fragments: RenderFragments, lvl: ZLevel, index: FigIdx): RenderCursor =
  fragments.ensureLayer(lvl)
  if not fragments.base.layers[lvl].validIdx(index):
    raise newException(RenderFragmentError, "node index is out of range")
  fragments.makeBaseCursor(lvl, index)

proc updateNode*(fragments: RenderFragments, cursor: RenderCursor, node: sink Fig) =
  ## Updates visual node data while retaining fragment topology fields.
  fragments.requireCursor(cursor)
  if cursor.fragment.isNil:
    let current = fragments.base.layers[cursor.zlevel].nodes[cursor.index.int]
    node.zlevel = current.zlevel
    node.parent = current.parent
    node.childCount = current.childCount
    fragments.base.layers[cursor.zlevel].nodes[cursor.index.int] = move node
  else:
    let current = cursor.fragment.list.nodes[cursor.index.int]
    node.zlevel = current.zlevel
    node.parent = current.parent
    node.childCount = current.childCount
    cursor.fragment.list.nodes[cursor.index.int] = move node

iterator expandEntry(
    fragments: RenderFragments,
    lvl: ZLevel,
    ownerFragment: RenderFragment,
    entry: RenderChild,
): RenderCursor =
  case entry.kind
  of rckNode:
    if ownerFragment.isNil:
      yield fragments.makeBaseCursor(lvl, entry.node)
    else:
      yield fragments.makeFragmentCursor(ownerFragment, entry.node)
  of rckFragment:
    if not entry.fragment.attached:
      raise
        newException(RenderFragmentError, "render tree contains a detached fragment")
    for root in entry.fragment.entries.rootEntries:
      if root.kind != rckNode:
        raise newException(RenderFragmentError, "fragment root metadata is invalid")
      yield fragments.makeFragmentCursor(entry.fragment, root.node)

iterator roots*(renders: Renders, lvl: ZLevel): RenderCursor =
  for rootIdx in renders[lvl].rootIds:
    yield makeRendersCursor(lvl, rootIdx)

iterator children*(renders: Renders, parent: RenderCursor): RenderCursor =
  if not parent.owner.isNil or not parent.fragment.isNil:
    raise newException(RenderFragmentError, "fragment cursor cannot traverse Renders")
  for childIdx in renders[parent.zlevel].nodes.childIndex(parent.index):
    yield makeRendersCursor(parent.zlevel, childIdx)

iterator roots*(fragments: RenderFragments, lvl: ZLevel): RenderCursor =
  fragments.ensureLayer(lvl)
  for entry in fragments.layerEntries[lvl].rootEntries:
    for cursor in fragments.expandEntry(lvl, nil, entry):
      yield cursor

iterator children*(fragments: RenderFragments, parent: RenderCursor): RenderCursor =
  fragments.requireCursor(parent)
  if parent.fragment.isNil:
    let entries = fragments.layerEntries[parent.zlevel]
    for entry in entries.childEntries.getOrDefault(parent.index.entryKey()):
      for cursor in fragments.expandEntry(parent.zlevel, nil, entry):
        yield cursor
  else:
    parent.fragment.list.ensureEntries(parent.fragment.entries)
    let entries = parent.fragment.entries
    for entry in entries.childEntries.getOrDefault(parent.index.entryKey()):
      for cursor in fragments.expandEntry(parent.zlevel, parent.fragment, entry):
        yield cursor

proc fragmentRoots*(
    fragments: RenderFragments, handle: RenderFragmentHandle
): seq[RenderCursor] =
  fragments.requireHandle(handle)
  for entry in handle.fragment.entries.rootEntries:
    if entry.kind != rckNode:
      raise newException(RenderFragmentError, "fragment root metadata is invalid")
    result.add fragments.makeFragmentCursor(handle.fragment, entry.node)

proc addRoot*(
    fragments: RenderFragments, lvl: ZLevel, root: Fig
): FigIdx {.discardable.} =
  var node = root
  node.zlevel = lvl
  fragments.ensureLayer(lvl)
  result = fragments.base.layers[lvl].addRoot(node)
  fragments.layerEntries[lvl].rootEntries.add result.nodeChild()

proc addRoot*(fragments: RenderFragments, root: Fig): FigIdx {.discardable.} =
  fragments.addRoot(root.zlevel, root)

proc insertRoot*(
    fragments: RenderFragments, lvl: ZLevel, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  fragments.ensureLayer(lvl)
  if rootPos.int > fragments.layerEntries[lvl].rootEntries.len:
    raise newException(RenderFragmentError, "root position is out of range")

  let physicalRootPos = min(rootPos.int, fragments.base.layers[lvl].rootIds.len)
  let insertIdx =
    if physicalRootPos == fragments.base.layers[lvl].rootIds.len:
      fragments.base.layers[lvl].nodes.len
    else:
      fragments.base.layers[lvl].rootIds[physicalRootPos].int
  fragments.layerEntries[lvl].shiftEntryIndexes(insertIdx, 1)

  var node = root
  node.zlevel = lvl
  result = fragments.base.layers[lvl].insertRoot(node, physicalRootPos.Natural)
  fragments.layerEntries[lvl].rootEntries.insert(result.nodeChild(), rootPos.int)
  fragments.baseNodeGenerations[lvl].advance()

proc insertRoot*(
    fragments: RenderFragments, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  fragments.insertRoot(root.zlevel, root, rootPos)

proc addChild*(
    fragments: RenderFragments, lvl: ZLevel, parentIdx: FigIdx, child: Fig
): FigIdx {.discardable.} =
  fragments.ensureLayer(lvl)
  if not fragments.base.layers[lvl].validIdx(parentIdx):
    raise newException(RenderFragmentError, "parent node index is out of range")

  var node = child
  node.zlevel = lvl
  result = fragments.base.layers[lvl].addChild(parentIdx, node)
  fragments.layerEntries[lvl].childEntries.mgetOrPut(parentIdx.entryKey(), @[]).add(
    result.nodeChild()
  )

proc addChild*(
    fragments: RenderFragments, parent: RenderCursor, child: Fig
): RenderCursor {.discardable.} =
  fragments.requireCursor(parent)
  var node = child
  node.zlevel = parent.zlevel
  if parent.fragment.isNil:
    let index = fragments.addChild(parent.zlevel, parent.index, node)
    return fragments.makeBaseCursor(parent.zlevel, index)

  let index = parent.fragment.list.addChild(parent.index, node)
  parent.fragment.entries.childEntries.mgetOrPut(parent.index.entryKey(), @[]).add(
    index.nodeChild()
  )
  fragments.makeFragmentCursor(parent.fragment, index)

proc insertChildInto(
    list: var RenderList,
    entries: var RenderEntries,
    parentIdx: FigIdx,
    child: Fig,
    childPos: Natural,
): FigIdx =
  list.ensureEntries(entries)
  let currentEntries = entries.childEntries.getOrDefault(parentIdx.entryKey())
  if childPos.int > currentEntries.len:
    raise newException(RenderFragmentError, "child slot position is out of range")

  let physicalChildCount = list.nodes[parentIdx.int].childCount.int
  let physicalChildPos = min(childPos.int, physicalChildCount)
  var insertIdx = list.nodes.len
  if physicalChildPos < physicalChildCount:
    var pos = 0
    for childIdx in list.nodes.childIndex(parentIdx):
      if pos == physicalChildPos:
        insertIdx = childIdx.int
      inc pos
  entries.shiftEntryIndexes(insertIdx, 1)
  result = list.insertChild(parentIdx, child, physicalChildPos.Natural)

  let shiftedParentIdx =
    if parentIdx.int >= insertIdx:
      (parentIdx.int + 1).FigIdx
    else:
      parentIdx
  entries.childEntries.mgetOrPut(shiftedParentIdx.entryKey(), @[]).insert(
    result.nodeChild(), childPos.int
  )

proc insertChild*(
    fragments: RenderFragments,
    lvl: ZLevel,
    parentIdx: FigIdx,
    child: Fig,
    childPos: Natural,
): FigIdx {.discardable.} =
  fragments.ensureLayer(lvl)
  if not fragments.base.layers[lvl].validIdx(parentIdx):
    raise newException(RenderFragmentError, "parent node index is out of range")
  var node = child
  node.zlevel = lvl
  result = fragments.base.layers[lvl].insertChildInto(
    fragments.layerEntries[lvl], parentIdx, node, childPos
  )
  fragments.baseNodeGenerations[lvl].advance()

proc insertChild*(
    fragments: RenderFragments, parent: RenderCursor, child: Fig, childPos: Natural
): RenderCursor {.discardable.} =
  fragments.requireCursor(parent)
  var node = child
  node.zlevel = parent.zlevel
  if parent.fragment.isNil:
    let index = fragments.insertChild(parent.zlevel, parent.index, node, childPos)
    return fragments.makeBaseCursor(parent.zlevel, index)

  let index = parent.fragment.list.insertChildInto(
    parent.fragment.entries, parent.index, node, childPos
  )
  parent.fragment.nodeGeneration.advance()
  fragments.makeFragmentCursor(parent.fragment, index)

proc appendChildren(
    list: var RenderList,
    entries: var RenderEntries,
    parentIdx: FigIdx,
    children: sink RenderList,
): seq[FigIdx] =
  list.ensureEntries(entries)
  if not list.validIdx(parentIdx):
    raise newException(RenderFragmentError, "parent node index is out of range")
  children.validateRootIds()
  if children.nodes.len == 0:
    return @[]
  if list.nodes.len + children.nodes.len > high(int16).int:
    raise newException(RenderFragmentError, "RenderList node capacity exceeded")

  let base = list.nodes.len
  for node in children.nodes:
    var newNode = node
    if node.parent.int < 0:
      newNode.parent = parentIdx
    else:
      newNode.parent = checkedFigIdx(base + node.parent.int)
    list.nodes.add newNode

  for root in children.rootIds:
    let appendedIdx = checkedFigIdx(base + root.int)
    entries.childEntries.mgetOrPut(parentIdx.entryKey(), @[]).add(
      appendedIdx.nodeChild()
    )
    if list.nodes[parentIdx.int].childCount ==
        high(typeof(list.nodes[parentIdx.int].childCount)):
      raise newException(RenderFragmentError, "RenderList parent childCount overflow")
    inc list.nodes[parentIdx.int].childCount
    result.add appendedIdx

  for sourceParentIdx, node in children.nodes:
    if node.childCount > 0:
      let destinationParent = checkedFigIdx(base + sourceParentIdx)
      var destinationEntries: seq[RenderChild]
      for childIdx in children.nodes.childIndex(sourceParentIdx.FigIdx):
        destinationEntries.add checkedFigIdx(base + childIdx.int).nodeChild()
      entries.childEntries[destinationParent.entryKey()] = move destinationEntries

proc addChildren*(
    fragments: RenderFragments,
    lvl: ZLevel,
    parentIdx: FigIdx,
    children: sink RenderList,
): seq[FigIdx] {.discardable.} =
  fragments.ensureLayer(lvl)
  children.relevelList(lvl)
  fragments.base.layers[lvl].appendChildren(
    fragments.layerEntries[lvl], parentIdx, move children
  )

proc addChildren*(
    fragments: RenderFragments, parent: RenderCursor, children: sink RenderList
): seq[RenderCursor] {.discardable.} =
  fragments.requireCursor(parent)
  children.relevelList(parent.zlevel)
  if parent.fragment.isNil:
    for index in fragments.addChildren(parent.zlevel, parent.index, move children):
      result.add fragments.makeBaseCursor(parent.zlevel, index)
  else:
    for index in parent.fragment.list.appendChildren(
      parent.fragment.entries, parent.index, move children
    ):
      result.add fragments.makeFragmentCursor(parent.fragment, index)

proc attachChildFragment*(
    fragments: RenderFragments,
    parent: RenderCursor,
    childPos: Natural,
    contents: sink RenderList,
): RenderFragmentHandle =
  ## Attaches one persistent fragment slot as a logical child of `parent`.
  ## `childPos` counts node and fragment slots, not expanded fragment roots.
  fragments.requireCursor(parent)

  let fragment = fragments.newFragment(parent.zlevel, move contents)
  if parent.fragment.isNil:
    let children = fragments.layerEntries[parent.zlevel].childEntries.mgetOrPut(
      parent.index.entryKey(), @[]
    )
    if childPos.int > children.len:
      fragment.attached = false
      raise newException(RenderFragmentError, "child fragment position is out of range")
    fragments.layerEntries[parent.zlevel].childEntries[parent.index.entryKey()].insert(
      fragment.fragmentChild(), childPos.int
    )
  else:
    let children =
      parent.fragment.entries.childEntries.mgetOrPut(parent.index.entryKey(), @[])
    if childPos.int > children.len:
      fragment.attached = false
      raise newException(RenderFragmentError, "child fragment position is out of range")
    parent.fragment.entries.childEntries[parent.index.entryKey()].insert(
      fragment.fragmentChild(), childPos.int
    )
  fragments.makeHandle(fragment)

proc attachChildFragment*(
    fragments: RenderFragments,
    lvl: ZLevel,
    parentIdx: FigIdx,
    childPos: Natural,
    contents: sink RenderList,
): RenderFragmentHandle =
  fragments.attachChildFragment(
    fragments.nodeCursor(lvl, parentIdx), childPos, move contents
  )

proc attachRootFragment*(
    fragments: RenderFragments, lvl: ZLevel, rootPos: Natural, contents: sink RenderList
): RenderFragmentHandle =
  ## Attaches one persistent fragment slot to a layer root sequence.
  fragments.ensureLayer(lvl)
  if rootPos.int > fragments.layerEntries[lvl].rootEntries.len:
    raise newException(RenderFragmentError, "root fragment position is out of range")

  let fragment = fragments.newFragment(lvl, move contents)
  fragments.layerEntries[lvl].rootEntries.insert(fragment.fragmentChild(), rootPos.int)
  fragments.makeHandle(fragment)

proc replaceFragment*(
    fragments: RenderFragments, handle: RenderFragmentHandle, contents: sink RenderList
): RenderFragmentHandle =
  ## Replaces fragment contents without changing the persistent attachment slot.
  fragments.requireHandle(handle)
  contents.relevelList(handle.fragment.zlevel)
  contents.validateRootIds()
  var entries: RenderEntries
  contents.rebuildEntries(entries)

  handle.fragment.entries.detachFragments()
  handle.fragment.list = move contents
  handle.fragment.entries = move entries
  handle.fragment.generation.advance()
  handle.fragment.nodeGeneration.advance()
  fragments.makeHandle(handle.fragment)

proc removeFragmentEdge(entries: var RenderEntries, target: RenderFragment): bool =
  for idx, entry in entries.rootEntries:
    if entry.kind == rckFragment and entry.fragment == target:
      entries.rootEntries.delete(idx)
      return true

  for _, children in entries.childEntries.mpairs:
    for idx, entry in children:
      if entry.kind == rckFragment and entry.fragment == target:
        children.delete(idx)
        return true

  for entry in entries.rootEntries:
    if entry.kind == rckFragment and entry.fragment.entries.removeFragmentEdge(target):
      return true
  for _, children in entries.childEntries.mpairs:
    for entry in children:
      if entry.kind == rckFragment and entry.fragment.entries.removeFragmentEdge(target):
        return true

proc removeFragment*(fragments: RenderFragments, handle: RenderFragmentHandle) =
  fragments.requireHandle(handle)
  var removed = false
  for _, entries in fragments.layerEntries.mpairs:
    if entries.removeFragmentEdge(handle.fragment):
      removed = true
      break
  if not removed:
    raise newException(RenderFragmentError, "fragment attachment is missing")
  handle.fragment.detachFragment()

proc insertChildren*(
    fragments: RenderFragments,
    lvl: ZLevel,
    parentIdx: FigIdx,
    children: sink RenderList,
    childPos: Natural,
): seq[RenderCursor] {.discardable.} =
  ## Compatibility wrapper. New code should retain `attachChildFragment`'s
  ## handle so an empty replacement can later become nonempty.
  if children.nodes.len == 0:
    return @[]
  let handle = fragments.attachChildFragment(lvl, parentIdx, childPos, move children)
  fragments.fragmentRoots(handle)

proc insertChildren*(
    fragments: RenderFragments,
    parent: RenderCursor,
    children: sink RenderList,
    childPos: Natural,
): seq[RenderCursor] {.discardable.} =
  ## Compatibility wrapper. New code should use `attachChildFragment`.
  if children.nodes.len == 0:
    return @[]
  let handle = fragments.attachChildFragment(parent, childPos, move children)
  fragments.fragmentRoots(handle)

proc updateFragment*(
    fragments: RenderFragments, cursor: RenderCursor, updated: sink RenderList
): seq[RenderCursor] {.discardable.} =
  ## Compatibility wrapper. New code should use `replaceFragment` and retain the
  ## returned handle.
  let handle = cursor.fragmentHandle()
  let replacement = fragments.replaceFragment(handle, move updated)
  fragments.fragmentRoots(replacement)

proc appendMaterialized(
    fragments: RenderFragments,
    list: var RenderList,
    cursor: RenderCursor,
    parent: FigIdx,
): FigIdx =
  var node = fragments[cursor]
  node.childCount = 0
  if parent.int < 0:
    result = list.addRoot(node)
  else:
    result = list.addChild(parent, node)
  for child in fragments.children(cursor):
    discard fragments.appendMaterialized(list, child, result)

proc materialize*(fragments: RenderFragments): Renders =
  ## Flattens the logical fragment graph into an independent monolithic tree.
  if fragments.isNil:
    raise newException(RenderFragmentError, "cannot materialize a nil fragment tree")
  result = newRenders()
  for lvl, _ in fragments.pairs():
    var list = RenderList()
    for root in fragments.roots(lvl):
      discard fragments.appendMaterialized(list, root, (-1).FigIdx)
    result.setLayer(lvl, move list)
