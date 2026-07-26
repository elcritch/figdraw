import std/tables

import ./fignodes

type
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

  RenderEntries = object
    childEntries: Table[int16, seq[RenderChild]]
    rootEntries: seq[RenderChild]
    ready: bool

  RenderFragment* = ref object ## An independently replaceable render subtree.
    list: RenderList
    entries: RenderEntries

  RenderFragments* = ref object
    ## A render tree whose base `Renders` remains physically unchanged when
    ## fragment subtrees are inserted or replaced.
    base: Renders
    layerEntries: Table[ZLevel, RenderEntries]

  RenderCursor* = object ## Identifies a Fig in a base layer or an inserted fragment.
    zlevel*: ZLevel
    index*: FigIdx
    fragment: RenderFragment

  RenderInput* = Renders | RenderFragments

proc `==`*(a, b: RenderCursor): bool =
  a.zlevel == b.zlevel and a.index == b.index and a.fragment == b.fragment

func entryKey(idx: FigIdx): int16 =
  idx.int.int16

proc nodeChild(idx: FigIdx): RenderChild =
  RenderChild(kind: rckNode, node: idx)

proc fragmentChild(fragment: RenderFragment, root: FigIdx): RenderChild =
  RenderChild(kind: rckFragment, fragment: fragment, root: root)

proc makeCursor(
    zlevel: ZLevel, index: FigIdx, fragment: RenderFragment = nil
): RenderCursor =
  RenderCursor(zlevel: zlevel, index: index, fragment: fragment)

proc validIdx(list: RenderList, idx: FigIdx): bool =
  idx.int >= 0 and idx.int < list.nodes.len

proc checkedFigIdx(idx: int): FigIdx =
  assert idx >= 0 and idx <= high(int16).int
  idx.FigIdx

proc validateRootIds(list: RenderList) =
  for rootIdx in list.rootIds:
    assert list.validIdx(rootIdx)
    assert list.nodes[rootIdx.int].parent.int < 0

  for idx, node in list.nodes:
    if node.parent.int < 0:
      var found = false
      for rootIdx in list.rootIds:
        if rootIdx.int == idx:
          found = true
          break
      assert found

proc reset(entries: var RenderEntries) =
  entries.childEntries.clear()
  entries.rootEntries.setLen(0)
  entries.ready = false

proc rebuildEntries(list: RenderList, entries: var RenderEntries) =
  entries.childEntries.clear()
  entries.rootEntries.setLen(0)
  for idx, node in list.nodes:
    let child = idx.FigIdx.nodeChild()
    if node.parent.int < 0:
      entries.rootEntries.add child
    else:
      assert node.parent.int < list.nodes.len
      entries.childEntries.mgetOrPut(node.parent.entryKey(), @[]).add child
  entries.ready = true

proc ensureEntries(list: RenderList, entries: var RenderEntries) =
  if not entries.ready:
    list.rebuildEntries(entries)

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

proc effectiveChildCount(
    list: RenderList, entries: var RenderEntries, parentIdx: FigIdx
): int =
  assert list.validIdx(parentIdx)
  list.ensureEntries(entries)
  entries.childEntries.getOrDefault(parentIdx.entryKey()).len

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

proc relevelList(list: var RenderList, lvl: ZLevel) =
  for node in list.nodes.mitems:
    node.zlevel = lvl

proc insertFragment(
    list: RenderList,
    entries: var RenderEntries,
    parentIdx: FigIdx,
    children: sink RenderList,
    childPos: Natural,
): RenderFragment =
  list.ensureEntries(entries)
  assert list.validIdx(parentIdx)
  assert childPos.int <= list.effectiveChildCount(entries, parentIdx)

  children.validateRootIds()
  var fragmentEntries: RenderEntries
  children.rebuildEntries(fragmentEntries)
  if fragmentEntries.rootEntries.len == 0:
    return nil

  result = RenderFragment(list: move children, entries: move fragmentEntries)
  for offset, root in result.entries.rootEntries:
    assert root.kind == rckNode
    entries.childEntries.mgetOrPut(parentIdx.entryKey(), @[]).insert(
      result.fragmentChild(root.node), childPos.int + offset
    )

proc appendChildren(
    list: var RenderList,
    entries: var RenderEntries,
    parentIdx: FigIdx,
    children: sink RenderList,
): seq[FigIdx] =
  list.ensureEntries(entries)
  assert list.validIdx(parentIdx)
  children.validateRootIds()
  if children.nodes.len == 0:
    return @[]

  assert list.nodes.len + children.nodes.len <= high(int16).int
  let base = list.nodes.len
  for node in children.nodes:
    var newNode = node
    if node.parent.int < 0:
      newNode.parent = parentIdx
    else:
      assert node.parent.int < children.nodes.len
      newNode.parent = checkedFigIdx(base + node.parent.int)
    list.nodes.add newNode

  for root in children.rootIds:
    let appendedIdx = checkedFigIdx(base + root.int)
    entries.childEntries.mgetOrPut(parentIdx.entryKey(), @[]).add(
      appendedIdx.nodeChild()
    )
    if list.nodes[parentIdx.int].childCount ==
        high(typeof(list.nodes[parentIdx.int].childCount)):
      raise newException(ValueError, "RenderList parent childCount overflow")
    inc list.nodes[parentIdx.int].childCount
    result.add appendedIdx

  for sourceParentIdx, node in children.nodes:
    if node.childCount > 0:
      let destinationParent = checkedFigIdx(base + sourceParentIdx)
      var destinationEntries: seq[RenderChild]
      for childIdx in children.nodes.childIndex(sourceParentIdx.FigIdx):
        destinationEntries.add checkedFigIdx(base + childIdx.int).nodeChild()
      entries.childEntries[destinationParent.entryKey()] = move destinationEntries

proc layerState(fragments: RenderFragments, lvl: ZLevel): var RenderEntries =
  if lvl notin fragments.base.layers:
    fragments.base.layers[lvl] = RenderList()
  result = fragments.layerEntries.mgetOrPut(lvl, RenderEntries())
  fragments.base.layers[lvl].ensureEntries(result)

proc newRenderFragments*(): RenderFragments =
  RenderFragments(base: newRenders(), layerEntries: initTable[ZLevel, RenderEntries]())

proc newRenderFragments*(renders: Renders): RenderFragments =
  ## Wraps an existing render tree. Fragment-aware mutations should subsequently
  ## use this wrapper so its logical traversal metadata stays synchronized.
  assert not renders.isNil
  RenderFragments(base: renders, layerEntries: initTable[ZLevel, RenderEntries]())

proc clear*(fragments: RenderFragments) =
  fragments.base.clear()
  fragments.layerEntries.clear()

func len*(fragments: RenderFragments, lvl: ZLevel): int =
  fragments.base.len(lvl)

proc contains*(fragments: RenderFragments, lvl: ZLevel): bool =
  fragments.base.contains(lvl)

proc effectiveChildCount*(
    fragments: RenderFragments, lvl: ZLevel, parentIdx: FigIdx
): int =
  discard fragments.layerState(lvl)
  fragments.base.layers[lvl].effectiveChildCount(fragments.layerEntries[lvl], parentIdx)

proc effectiveChildCount*(fragments: RenderFragments, parent: RenderCursor): int =
  if parent.fragment.isNil:
    return fragments.effectiveChildCount(parent.zlevel, parent.index)
  parent.fragment.list.effectiveChildCount(parent.fragment.entries, parent.index)

template pairs*(fragments: RenderFragments): auto =
  fragments.base.layers.pairs()

proc `[]`*(fragments: RenderFragments, lvl: ZLevel): var RenderList =
  discard fragments.layerState(lvl)
  fragments.base.layers[lvl]

proc setLayer*(fragments: RenderFragments, lvl: ZLevel, list: RenderList) =
  fragments.base.setLayer(lvl, list)
  fragments.layerEntries.mgetOrPut(lvl, RenderEntries()).reset()

template `[]`*(renders: Renders, cursor: RenderCursor): untyped =
  assert cursor.fragment.isNil
  renders.layers[cursor.zlevel].nodes[cursor.index.int]

template `[]`*(fragments: RenderFragments, cursor: RenderCursor): untyped =
  if cursor.fragment.isNil:
    fragments.base.layers[cursor.zlevel].nodes[cursor.index.int]
  else:
    cursor.fragment.list.nodes[cursor.index.int]

iterator roots*(renders: Renders, lvl: ZLevel): RenderCursor =
  for rootIdx in renders[lvl].rootIds:
    yield makeCursor(lvl, rootIdx)

iterator children*(renders: Renders, parent: RenderCursor): RenderCursor =
  assert parent.fragment.isNil
  for childIdx in renders[parent.zlevel].nodes.childIndex(parent.index):
    yield makeCursor(parent.zlevel, childIdx)

iterator roots*(fragments: RenderFragments, lvl: ZLevel): RenderCursor =
  let entries = fragments.layerState(lvl)
  for entry in entries.rootEntries:
    case entry.kind
    of rckNode:
      yield makeCursor(lvl, entry.node)
    of rckFragment:
      yield makeCursor(lvl, entry.root, entry.fragment)

iterator children*(fragments: RenderFragments, parent: RenderCursor): RenderCursor =
  if parent.fragment.isNil:
    let entries = fragments.layerState(parent.zlevel)
    for entry in entries.childEntries.getOrDefault(parent.index.entryKey()):
      case entry.kind
      of rckNode:
        yield makeCursor(parent.zlevel, entry.node)
      of rckFragment:
        yield makeCursor(parent.zlevel, entry.root, entry.fragment)
  else:
    parent.fragment.list.ensureEntries(parent.fragment.entries)
    for entry in parent.fragment.entries.childEntries.getOrDefault(
      parent.index.entryKey()
    ):
      case entry.kind
      of rckNode:
        yield makeCursor(parent.zlevel, entry.node, parent.fragment)
      of rckFragment:
        yield makeCursor(parent.zlevel, entry.root, entry.fragment)

proc addRoot*(
    fragments: RenderFragments, lvl: ZLevel, root: Fig
): FigIdx {.discardable.} =
  var node = root
  node.zlevel = lvl
  discard fragments.layerState(lvl)
  result = fragments.base.layers[lvl].addRoot(node)
  fragments.layerEntries[lvl].rootEntries.add result.nodeChild()

proc addRoot*(fragments: RenderFragments, root: Fig): FigIdx {.discardable.} =
  fragments.addRoot(root.zlevel, root)

proc insertRoot*(
    fragments: RenderFragments, lvl: ZLevel, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  discard fragments.layerState(lvl)
  let insertIdx = fragments.base.layers[lvl].rootInsertIndex(rootPos)
  fragments.layerEntries[lvl].shiftEntryIndexes(insertIdx, 1)

  var node = root
  node.zlevel = lvl
  result = fragments.base.layers[lvl].insertRoot(node, rootPos)
  fragments.layerEntries[lvl].rootEntries.insert(result.nodeChild(), rootPos.int)

proc insertRoot*(
    fragments: RenderFragments, root: Fig, rootPos: Natural
): FigIdx {.discardable.} =
  fragments.insertRoot(root.zlevel, root, rootPos)

proc addChild*(
    fragments: RenderFragments, lvl: ZLevel, parentIdx: FigIdx, child: Fig
): FigIdx {.discardable.} =
  var node = child
  node.zlevel = lvl
  discard fragments.layerState(lvl)
  result = fragments.base.layers[lvl].addChild(parentIdx, node)

  fragments.layerEntries[lvl].childEntries.mgetOrPut(parentIdx.entryKey(), @[]).add result.nodeChild()

proc addChild*(
    fragments: RenderFragments, parent: RenderCursor, child: Fig
): RenderCursor {.discardable.} =
  var node = child
  node.zlevel = parent.zlevel
  if parent.fragment.isNil:
    let index = fragments.addChild(parent.zlevel, parent.index, node)
    return makeCursor(parent.zlevel, index)

  parent.fragment.list.ensureEntries(parent.fragment.entries)
  let index = parent.fragment.list.addChild(parent.index, node)
  parent.fragment.entries.childEntries.mgetOrPut(parent.index.entryKey(), @[]).add(
    index.nodeChild()
  )
  makeCursor(parent.zlevel, index, parent.fragment)

proc insertChildInto(
    list: var RenderList,
    entries: var RenderEntries,
    parentIdx: FigIdx,
    child: Fig,
    childPos: Natural,
): FigIdx =
  list.ensureEntries(entries)
  assert childPos.int <= list.effectiveChildCount(entries, parentIdx)
  let physicalChildCount = list.nodes[parentIdx.int].childCount.int
  let insertIdx =
    if childPos.int <= physicalChildCount:
      list.childInsertIndex(parentIdx, childPos)
    else:
      list.nodes.len
  entries.shiftEntryIndexes(insertIdx, 1)
  result =
    list.insertChild(parentIdx, child, min(childPos.int, physicalChildCount).Natural)

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
  var node = child
  node.zlevel = lvl
  discard fragments.layerState(lvl)
  fragments.base.layers[lvl].insertChildInto(
    fragments.layerEntries[lvl], parentIdx, node, childPos
  )

proc insertChild*(
    fragments: RenderFragments, parent: RenderCursor, child: Fig, childPos: Natural
): RenderCursor {.discardable.} =
  var node = child
  node.zlevel = parent.zlevel
  if parent.fragment.isNil:
    let index = fragments.insertChild(parent.zlevel, parent.index, node, childPos)
    return makeCursor(parent.zlevel, index)

  let index = parent.fragment.list.insertChildInto(
    parent.fragment.entries, parent.index, node, childPos
  )
  makeCursor(parent.zlevel, index, parent.fragment)

proc insertChildren*(
    fragments: RenderFragments,
    lvl: ZLevel,
    parentIdx: FigIdx,
    children: sink RenderList,
    childPos: Natural,
): seq[RenderCursor] {.discardable.} =
  children.relevelList(lvl)
  discard fragments.layerState(lvl)
  let fragment = fragments.base.layers[lvl].insertFragment(
    fragments.layerEntries[lvl], parentIdx, move children, childPos
  )
  if fragment.isNil:
    return @[]
  for root in fragment.entries.rootEntries:
    result.add makeCursor(lvl, root.node, fragment)

proc insertChildren*(
    fragments: RenderFragments,
    parent: RenderCursor,
    children: sink RenderList,
    childPos: Natural,
): seq[RenderCursor] {.discardable.} =
  children.relevelList(parent.zlevel)
  if parent.fragment.isNil:
    return
      fragments.insertChildren(parent.zlevel, parent.index, move children, childPos)

  let fragment = parent.fragment.list.insertFragment(
    parent.fragment.entries, parent.index, move children, childPos
  )
  if fragment.isNil:
    return @[]
  for root in fragment.entries.rootEntries:
    result.add makeCursor(parent.zlevel, root.node, fragment)

proc addChildren*(
    fragments: RenderFragments,
    lvl: ZLevel,
    parentIdx: FigIdx,
    children: sink RenderList,
): seq[FigIdx] {.discardable.} =
  children.relevelList(lvl)
  discard fragments.layerState(lvl)
  fragments.base.layers[lvl].appendChildren(
    fragments.layerEntries[lvl], parentIdx, move children
  )

proc addChildren*(
    fragments: RenderFragments, parent: RenderCursor, children: sink RenderList
): seq[RenderCursor] {.discardable.} =
  children.relevelList(parent.zlevel)
  if parent.fragment.isNil:
    for index in fragments.addChildren(parent.zlevel, parent.index, move children):
      result.add makeCursor(parent.zlevel, index)
  else:
    for index in parent.fragment.list.appendChildren(
      parent.fragment.entries, parent.index, move children
    ):
      result.add makeCursor(parent.zlevel, index, parent.fragment)

proc replaceFragmentChildren(
    children: var seq[RenderChild],
    target: RenderFragment,
    replacementRoots: openArray[FigIdx],
) =
  var updated = newSeqOfCap[RenderChild](children.len + replacementRoots.len)
  var replaced = false
  for entry in children:
    if entry.kind == rckFragment and entry.fragment == target:
      if not replaced:
        for root in replacementRoots:
          updated.add target.fragmentChild(root)
        replaced = true
    else:
      updated.add entry
  children = move updated

proc replaceFragmentReferences(
    entries: var RenderEntries,
    target: RenderFragment,
    replacementRoots: openArray[FigIdx],
) =
  for _, children in entries.childEntries.mpairs:
    children.replaceFragmentChildren(target, replacementRoots)

proc updateNestedReferences(
    entries: var RenderEntries,
    target: RenderFragment,
    replacementRoots: openArray[FigIdx],
) =
  entries.replaceFragmentReferences(target, replacementRoots)
  for _, children in entries.childEntries.mpairs:
    for entry in children:
      if entry.kind == rckFragment and entry.fragment != target:
        entry.fragment.entries.updateNestedReferences(target, replacementRoots)

proc updateFragment*(
    fragments: RenderFragments, cursor: RenderCursor, updated: sink RenderList
): seq[RenderCursor] {.discardable.} =
  ## Replaces the fragment identified by `cursor` while preserving its identity
  ## and position in the surrounding render tree.
  assert not cursor.fragment.isNil
  updated.relevelList(cursor.zlevel)
  updated.validateRootIds()

  var updatedEntries: RenderEntries
  updated.rebuildEntries(updatedEntries)
  var replacementRoots: seq[FigIdx]
  for root in updatedEntries.rootEntries:
    replacementRoots.add root.node

  for _, entries in fragments.layerEntries.mpairs:
    entries.updateNestedReferences(cursor.fragment, replacementRoots)

  cursor.fragment.list = move updated
  cursor.fragment.entries = move updatedEntries
  for root in replacementRoots:
    result.add makeCursor(cursor.zlevel, root, cursor.fragment)
