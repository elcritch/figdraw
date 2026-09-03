import std/[sequtils, tables, unittest]

import figdraw/commons
import figdraw/figrender
import figdraw/fignodes
import figdraw/renderfragments

proc testFig(id: int, zlevel = 0.ZLevel): Fig =
  Fig(kind: nkRectangle, zlevel: zlevel, rotation: id.float32)

proc nodeId(node: Fig): int =
  node.rotation.int

proc childIds(fragments: RenderFragments, parent: RenderCursor): seq[int] =
  for child in fragments.children(parent):
    result.add fragments[child].nodeId()

proc rootCursors(fragments: RenderFragments, zlevel: ZLevel): seq[RenderCursor] =
  for root in fragments.roots(zlevel):
    result.add root

proc rootCursors(renders: Renders, zlevel: ZLevel): seq[RenderCursor] =
  for root in renders.roots(zlevel):
    result.add root

proc childIds(renders: Renders, parent: RenderCursor): seq[int] =
  for child in renders.children(parent):
    result.add renders[child].nodeId()

type RecordingBackend = ref object of BackendContext
  mat: Mat4
  mats: seq[Mat4]
  draws: seq[Rect]

method drawRoundedRectSdf*(
    ctx: RecordingBackend,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) =
  discard colors
  discard radii
  discard mode
  discard factor
  discard spread
  discard shapeSize
  let topLeft = (ctx.mat * vec3(rect.x, rect.y, 1.0'f32)).xy
  ctx.draws.add rect(topLeft.x, topLeft.y, rect.w, rect.h)

method translate*(ctx: RecordingBackend, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))

method applyTransform*(ctx: RecordingBackend, m: Mat4) =
  ctx.mat = ctx.mat * m

method saveTransform*(ctx: RecordingBackend) =
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: RecordingBackend) =
  if ctx.mats.len > 0:
    ctx.mat = ctx.mats.pop()

method supportsAtlasUsage*(ctx: RecordingBackend): bool =
  false

proc newRecordingBackend(): RecordingBackend =
  RecordingBackend(mat: mat4())

proc renderFragmentFrameCompiles(
    renderer: FigRenderer[NoRendererBackendState], fragments: var RenderFragments
) {.used.} =
  renderer.renderFrame(fragments, vec2(100.0'f32, 100.0'f32))

suite "RenderFragments APIs":
  test "inserts fragment roots without changing base physical indexes":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))
    discard fragments.addChild(0.ZLevel, root, testFig(40))

    var children = RenderList()
    let childRoot = children.addRoot(testFig(20))
    discard children.addChild(childRoot, testFig(21))
    discard children.addRoot(testFig(30))

    let inserted = fragments.insertChildren(0.ZLevel, root, children, 0)
    let roots = fragments.rootCursors(0.ZLevel)

    check fragments[0.ZLevel].nodes.mapIt(it.nodeId()) == @[10, 40]
    check inserted.len == 2
    check fragments[inserted[0]].nodeId() == 20
    check fragments[inserted[1]].nodeId() == 30
    check fragments.childIds(roots[0]) == @[20, 30, 40]
    check fragments.childIds(inserted[0]) == @[21]
    check fragments.effectiveChildCount(roots[0]) == 3
    check fragments[0.ZLevel].nodes[root.int].childCount == 1

  test "physical inserts keep fragment traversal metadata synchronized":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))
    discard fragments.addChild(0.ZLevel, root, testFig(11))
    discard fragments.addChild(0.ZLevel, root, testFig(13))

    var child = RenderList()
    discard child.addRoot(testFig(20))
    discard fragments.insertChildren(0.ZLevel, root, child, 1)
    discard fragments.insertChild(0.ZLevel, root, testFig(12), 2)
    discard fragments.insertRoot(0.ZLevel, testFig(5), 0)

    let roots = fragments.rootCursors(0.ZLevel)
    check roots.mapIt(fragments[it].nodeId()) == @[5, 10]
    check fragments.childIds(roots[1]) == @[11, 20, 12, 13]

  test "supports nested cursor insert and append overloads":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))

    var children = RenderList()
    let childRoot = children.addRoot(testFig(20))
    discard children.addChild(childRoot, testFig(21))
    let inserted = fragments.insertChildren(0.ZLevel, root, children, 0)

    var nested = RenderList()
    discard nested.addRoot(testFig(22))
    discard fragments.insertChildren(inserted[0], nested, 1)
    let appended = fragments.addChild(inserted[0], testFig(23))

    check fragments[appended].nodeId() == 23
    check fragments.childIds(inserted[0]) == @[21, 22, 23]

  test "replaces an inserted fragment while preserving its position":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(5.ZLevel, testFig(10))
    discard fragments.addChild(5.ZLevel, root, testFig(40))

    var initial = RenderList()
    discard initial.addRoot(testFig(20))
    discard initial.addRoot(testFig(30))
    let inserted = fragments.insertChildren(5.ZLevel, root, initial, 0)

    var updated = RenderList()
    let updatedRoot = updated.addRoot(testFig(50, 1.ZLevel))
    discard updated.addChild(updatedRoot, testFig(51, 1.ZLevel))
    discard updated.addRoot(testFig(60, 1.ZLevel))
    let replacement = fragments.updateFragment(inserted[0], updated)

    let roots = fragments.rootCursors(5.ZLevel)
    check replacement.len == 2
    check fragments.childIds(roots[0]) == @[50, 60, 40]
    check fragments.childIds(replacement[0]) == @[51]
    check fragments[replacement[0]].zlevel == 5.ZLevel
    check fragments[replacement[1]].zlevel == 5.ZLevel
    check fragments[5.ZLevel].nodes.mapIt(it.nodeId()) == @[10, 40]

  test "replaces a nested fragment through its cursor":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))

    var parentList = RenderList()
    discard parentList.addRoot(testFig(20))
    let parent = fragments.insertChildren(0.ZLevel, root, parentList, 0)[0]

    var nestedList = RenderList()
    discard nestedList.addRoot(testFig(30))
    let nested = fragments.insertChildren(parent, nestedList, 0)[0]

    var updated = RenderList()
    discard updated.addRoot(testFig(31))
    discard updated.addRoot(testFig(32))
    let replacement = fragments.updateFragment(nested, updated)

    check replacement.len == 2
    check fragments.childIds(parent) == @[31, 32]

  test "renderer union traverses transform fragments":
    var fragments = newRenderFragments()
    let root = fragments.addRoot(
      0.ZLevel,
      Fig(
        kind: nkTransform,
        transform: TransformStyle(translation: vec2(5.0'f32, -4.0'f32)),
      ),
    )

    var child = RenderList()
    discard child.addRoot(
      Fig(
        kind: nkRectangle,
        screenBox: rect(2.0'f32, 2.0'f32, 1.0'f32, 1.0'f32),
        fill: fill(rgba(255, 0, 0, 255)),
      )
    )
    discard fragments.insertChildren(0.ZLevel, root, child, 0)

    let ctx = newRecordingBackend()
    ctx.renderRoot(fragments)

    check ctx.draws.len == 1
    check abs(ctx.draws[0].x - 7.0'f32) < 0.0001'f32
    check abs(ctx.draws[0].y - (-2.0'f32)) < 0.0001'f32

  test "wraps an unchanged Renders value":
    let renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())
    let root = renders.addRoot(2.ZLevel, testFig(10))
    discard renders.addChild(2.ZLevel, root, testFig(11))

    let fragments = newRenderFragments(renders)
    let roots = fragments.rootCursors(2.ZLevel)

    check fragments.childIds(roots[0]) == @[11]
    check renders[2.ZLevel].nodes.mapIt(it.nodeId()) == @[10, 11]

  test "persistent child fragment survives empty replacement":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))
    discard fragments.addChild(0.ZLevel, root, testFig(40))

    var initial = RenderList()
    discard initial.addRoot(testFig(20))
    discard initial.addRoot(testFig(30))
    let handle = fragments.attachChildFragment(0.ZLevel, root, 0, move initial)

    let emptyHandle = fragments.replaceFragment(handle, RenderList())
    let roots = fragments.rootCursors(0.ZLevel)
    check fragments.fragmentRoots(emptyHandle).len == 0
    check fragments.childIds(roots[0]) == @[40]

    var restored = RenderList()
    discard restored.addRoot(testFig(50))
    discard restored.addRoot(testFig(60))
    let restoredHandle = fragments.replaceFragment(emptyHandle, move restored)

    check fragments.fragmentRoots(restoredHandle).len == 2
    check fragments.childIds(roots[0]) == @[50, 60, 40]

  test "persistent root fragment retains layer position":
    let fragments = newRenderFragments()
    discard fragments.addRoot(3.ZLevel, testFig(40))

    var initial = RenderList()
    discard initial.addRoot(testFig(10))
    discard initial.addRoot(testFig(20))
    let handle = fragments.attachRootFragment(3.ZLevel, 0, move initial)
    check fragments.rootCursors(3.ZLevel).mapIt(fragments[it].nodeId()) == @[10, 20, 40]

    let emptyHandle = fragments.replaceFragment(handle, RenderList())
    check fragments.rootCursors(3.ZLevel).mapIt(fragments[it].nodeId()) == @[40]

    var restored = RenderList()
    discard restored.addRoot(testFig(30))
    discard fragments.replaceFragment(emptyHandle, move restored)
    check fragments.rootCursors(3.ZLevel).mapIt(fragments[it].nodeId()) == @[30, 40]

  test "safe replacement rejects nested attachments":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))

    var outerContents = RenderList()
    discard outerContents.addRoot(testFig(20))
    let outer = fragments.attachChildFragment(0.ZLevel, root, 0, move outerContents)
    let outerRoot = fragments.fragmentRoots(outer)[0]

    var innerContents = RenderList()
    discard innerContents.addRoot(testFig(30))
    let inner = fragments.attachChildFragment(outerRoot, 0, move innerContents)

    check fragments.hasNestedFragments(outer)
    check not fragments.hasNestedFragments(inner)
    expect RenderFragmentError:
      discard fragments.replaceFragment(outer, RenderList())
    check fragments.isValid(outer)
    check fragments.isValid(inner)
    check fragments.childIds(outerRoot) == @[30]

    var replacement = RenderList()
    discard replacement.addRoot(testFig(40))
    let replaced = fragments.replaceFragmentSubtree(outer, move replacement)
    check replaced.fragmentId() == outer.fragmentId()
    check fragments.handleStatus(outer) == rfsStaleFragment
    check fragments.handleStatus(inner) == rfsDetached
    check fragments.fragmentRoots(replaced).mapIt(fragments[it].nodeId()) == @[40]

  test "leaf replacement preserves ancestor and sibling generations":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))

    var ancestorContents = RenderList()
    discard ancestorContents.addRoot(testFig(20))
    let ancestor =
      fragments.attachChildFragment(0.ZLevel, root, 0, move ancestorContents)
    let ancestorRoot = fragments.fragmentRoots(ancestor)[0]

    var leafContents = RenderList()
    discard leafContents.addRoot(testFig(30))
    let leaf = fragments.attachChildFragment(ancestorRoot, 0, move leafContents)

    var siblingContents = RenderList()
    discard siblingContents.addRoot(testFig(40))
    let sibling = fragments.attachChildFragment(ancestorRoot, 1, move siblingContents)
    let siblingRoot = fragments.fragmentRoots(sibling)[0]

    var replacement = RenderList()
    discard replacement.addRoot(testFig(31))
    let updatedLeaf = fragments.replaceFragment(leaf, move replacement)

    check fragments.handleStatus(leaf) == rfsStaleFragment
    check fragments.isValid(updatedLeaf)
    check fragments.isValid(ancestor)
    check fragments.isValid(sibling)
    check fragments[ancestorRoot].nodeId() == 20
    check fragments[siblingRoot].nodeId() == 40
    check fragments.childIds(ancestorRoot) == @[31, 40]

  test "moves and reorders fragments without changing their generations":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))

    var firstContents = RenderList()
    discard firstContents.addRoot(testFig(20))
    let first = fragments.attachChildFragment(0.ZLevel, root, 0, move firstContents)
    let firstRoot = fragments.fragmentRoots(first)[0]

    var nestedContents = RenderList()
    discard nestedContents.addRoot(testFig(21))
    let nested = fragments.attachChildFragment(firstRoot, 0, move nestedContents)
    let nestedRoot = fragments.fragmentRoots(nested)[0]

    var secondContents = RenderList()
    discard secondContents.addRoot(testFig(30))
    let second = fragments.attachChildFragment(0.ZLevel, root, 1, move secondContents)
    let secondRoot = fragments.fragmentRoots(second)[0]

    var thirdContents = RenderList()
    discard thirdContents.addRoot(testFig(40))
    let third = fragments.attachChildFragment(0.ZLevel, root, 2, move thirdContents)
    let thirdRoot = fragments.fragmentRoots(third)[0]

    let reordered =
      fragments.moveFragment(third, fragments.nodeCursor(0.ZLevel, root), 0)
    check reordered == third
    check fragments.childIds(fragments.nodeCursor(0.ZLevel, root)) == @[40, 20, 30]
    check fragments[firstRoot].nodeId() == 20
    check fragments[nestedRoot].nodeId() == 21

    let reparented = fragments.moveFragment(first, secondRoot, 0)
    check reparented == first
    check fragments.childIds(fragments.nodeCursor(0.ZLevel, root)) == @[40, 30]
    check fragments.childIds(secondRoot) == @[20]
    check fragments.childIds(firstRoot) == @[21]
    check fragments.isValid(nested)

    let rooted = fragments.moveFragmentToRoot(first, 0.ZLevel, 0)
    check rooted == first
    check fragments.rootCursors(0.ZLevel).mapIt(fragments[it].nodeId()) == @[20, 10]
    check fragments.childIds(firstRoot) == @[21]
    check fragments[thirdRoot].nodeId() == 40

    let reorderedRoot = fragments.moveFragmentToRoot(first, 0.ZLevel, 1)
    check reorderedRoot == first
    check fragments.rootCursors(0.ZLevel).mapIt(fragments[it].nodeId()) == @[10, 20]

  test "moves an empty fragment slot before restoring its contents":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))

    var visibleContents = RenderList()
    discard visibleContents.addRoot(testFig(20))
    discard fragments.attachChildFragment(0.ZLevel, root, 0, move visibleContents)
    let empty = fragments.attachChildFragment(0.ZLevel, root, 1, RenderList())

    let moved = fragments.moveFragment(empty, fragments.nodeCursor(0.ZLevel, root), 0)
    check moved == empty
    check fragments.fragmentRoots(moved).len == 0

    var restoredContents = RenderList()
    discard restoredContents.addRoot(testFig(30))
    let restored = fragments.replaceFragment(moved, move restoredContents)
    check restored.fragmentId() == empty.fragmentId()
    check fragments.childIds(fragments.nodeCursor(0.ZLevel, root)) == @[30, 20]

  test "invalid fragment moves leave the graph unchanged":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))

    var outerContents = RenderList()
    discard outerContents.addRoot(testFig(20))
    let outer = fragments.attachChildFragment(0.ZLevel, root, 0, move outerContents)
    let outerRoot = fragments.fragmentRoots(outer)[0]

    var innerContents = RenderList()
    discard innerContents.addRoot(testFig(30))
    let inner = fragments.attachChildFragment(outerRoot, 0, move innerContents)
    let innerRoot = fragments.fragmentRoots(inner)[0]

    expect RenderFragmentError:
      discard fragments.moveFragment(outer, innerRoot, 0)
    expect RenderFragmentError:
      discard fragments.moveFragmentToRoot(outer, 1.ZLevel, 0)
    expect RenderFragmentError:
      discard fragments.moveFragment(inner, outerRoot, 2)

    check fragments.isValid(outer)
    check fragments.isValid(inner)
    check fragments.childIds(fragments.nodeCursor(0.ZLevel, root)) == @[20]
    check fragments.childIds(outerRoot) == @[30]

  test "rejects foreign stale and detached handles":
    let first = newRenderFragments()
    let firstRoot = first.addRoot(0.ZLevel, testFig(10))
    var child = RenderList()
    discard child.addRoot(testFig(20))
    let handle = first.attachChildFragment(0.ZLevel, firstRoot, 0, move child)

    let second = newRenderFragments()
    check second.handleStatus(handle) == rfsForeignTree
    expect RenderFragmentError:
      discard second.replaceFragment(handle, RenderList())
    check first.fragmentRoots(handle).mapIt(first[it].nodeId()) == @[20]

    var replacement = RenderList()
    discard replacement.addRoot(testFig(30))
    let current = first.replaceFragment(handle, move replacement)
    check first.handleStatus(handle) == rfsStaleFragment
    check first.handleStatus(current) == rfsValid
    expect RenderFragmentError:
      discard first.replaceFragment(handle, RenderList())

    first.removeFragment(current)
    check first.handleStatus(current) == rfsDetached
    expect RenderFragmentError:
      discard first.fragmentRoots(current)

  test "invalidates handles after clear and layer replacement":
    let cleared = newRenderFragments()
    let clearedRoot = cleared.addRoot(0.ZLevel, testFig(10))
    let clearHandle =
      cleared.attachChildFragment(0.ZLevel, clearedRoot, 0, RenderList())
    cleared.clear()
    check cleared.handleStatus(clearHandle) == rfsStaleTree

    let replaced = newRenderFragments()
    let replacedRoot = replaced.addRoot(2.ZLevel, testFig(10))
    let layerHandle =
      replaced.attachChildFragment(2.ZLevel, replacedRoot, 0, RenderList())
    replaced.setLayer(2.ZLevel, RenderList())
    check replaced.handleStatus(layerHandle) == rfsStaleLayer

  test "rejects cursors from replaced fragments":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))
    var initial = RenderList()
    discard initial.addRoot(testFig(20))
    let handle = fragments.attachChildFragment(0.ZLevel, root, 0, move initial)
    let staleCursor = fragments.fragmentRoots(handle)[0]

    var replacement = RenderList()
    discard replacement.addRoot(testFig(30))
    discard fragments.replaceFragment(handle, move replacement)
    expect RenderFragmentError:
      discard fragments[staleCursor]

  test "wrapping copies source topology":
    let renders = newRenders()
    let root = renders.addRoot(0.ZLevel, testFig(10))
    discard renders.addChild(0.ZLevel, root, testFig(20))
    let fragments = newRenderFragments(renders)

    renders[0.ZLevel].clear()
    let roots = fragments.rootCursors(0.ZLevel)
    check roots.mapIt(fragments[it].nodeId()) == @[10]
    check fragments.childIds(roots[0]) == @[20]

  test "layer reads cannot mutate fragment topology":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))
    discard fragments.addChild(0.ZLevel, root, testFig(20))

    var layerCopy = fragments[0.ZLevel]
    layerCopy.nodes[0].childCount = 0
    layerCopy.rootIds.setLen(0)
    for _, list in fragments.pairs():
      var pairCopy = list
      pairCopy.nodes.setLen(0)

    let roots = fragments.rootCursors(0.ZLevel)
    check roots.mapIt(fragments[it].nodeId()) == @[10]
    check fragments.childIds(roots[0]) == @[20]

  test "controlled node update preserves topology":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(4.ZLevel, testFig(10))
    discard fragments.addChild(4.ZLevel, root, testFig(20))
    let cursor = fragments.nodeCursor(4.ZLevel, root)

    var replacement = testFig(11, 9.ZLevel)
    replacement.parent = 99.FigIdx
    replacement.childCount = 99
    fragments.updateNode(cursor, replacement)

    check fragments[cursor].nodeId() == 11
    check fragments[cursor].zlevel == 4.ZLevel
    check fragments[cursor].parent == (-1).FigIdx
    check fragments[cursor].childCount == 1
    check fragments.childIds(cursor) == @[20]

  test "materializes nested fragments in logical order":
    let fragments = newRenderFragments()
    let root = fragments.addRoot(0.ZLevel, testFig(10))
    discard fragments.addChild(0.ZLevel, root, testFig(40))

    var child = RenderList()
    let childRoot = child.addRoot(testFig(20))
    discard child.addChild(childRoot, testFig(21))
    discard child.addRoot(testFig(30))
    let childHandle = fragments.attachChildFragment(0.ZLevel, root, 0, move child)

    var nested = RenderList()
    discard nested.addRoot(testFig(22))
    discard fragments.attachChildFragment(
      fragments.fragmentRoots(childHandle)[0], 1, move nested
    )

    let renders = fragments.materialize()
    let roots = renders.rootCursors(0.ZLevel)
    check renders[0.ZLevel].nodes.mapIt(it.nodeId()) == @[10, 20, 21, 22, 30, 40]
    check roots.mapIt(renders[it].nodeId()) == @[10]
    check renders.childIds(roots[0]) == @[20, 30, 40]
    let firstChild = toSeq(renders.children(roots[0]))[0]
    check renders.childIds(firstChild) == @[21, 22]
