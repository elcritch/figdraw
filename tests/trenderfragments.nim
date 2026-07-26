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

type RecordingBackend = ref object of BackendContext
  mat: Mat4
  mats: seq[Mat4]
  draws: seq[Rect]

method drawRoundedRectSdf*(
    ctx: RecordingBackend,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: array[DirectionCorners, float32],
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
