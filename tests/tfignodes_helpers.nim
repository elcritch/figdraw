import std/[sequtils, unittest]

import figdraw/fignodes

proc testFig(id: int, zlevel = 0.ZLevel): Fig =
  Fig(kind: nkRectangle, zlevel: zlevel, rotation: id.float32)

proc nodeId(node: Fig): int =
  node.rotation.int

proc childIds(list: RenderList, parentIdx: FigIdx): seq[int] =
  for childIdx in list.nodes.childIndex(parentIdx):
    result.add list.nodes[childIdx.int].nodeId()

proc childIds(renders: Renders, parent: RenderCursor): seq[int] =
  for child in renders.children(parent):
    result.add renders[child].nodeId()

proc rootIds(renders: Renders, zlevel: ZLevel): seq[int] =
  for root in renders.roots(zlevel):
    result.add renders[root].nodeId()

suite "RenderList helper APIs":
  test "insertRoot shifts existing root and parent indexes":
    var list = RenderList()
    let rootA = list.addRoot(testFig(10))
    discard list.addChild(rootA, testFig(11))
    discard list.addRoot(testFig(20))

    let inserted = list.insertRoot(testFig(15), 1)

    check inserted == 2.FigIdx
    check list.rootIds == @[0.FigIdx, 2.FigIdx, 3.FigIdx]
    check list.nodes.mapIt(it.nodeId()) == @[10, 11, 15, 20]
    check list.nodes[1].parent == 0.FigIdx
    check list.nodes[2].parent == (-1).FigIdx
    check list.nodes[3].parent == (-1).FigIdx
    check list.nodes[0].childCount == 1
    check list.nodes[2].childCount == 0

    let renders = newRenders()
    renders.setLayer(0.ZLevel, list)
    check renders.rootIds(0.ZLevel) == @[10, 15, 20]

  test "insertChild inserts at child position and shifts subtree parents":
    var list = RenderList()
    let root = list.addRoot(testFig(10))
    discard list.addChild(root, testFig(11))
    let oldSecond = list.addChild(root, testFig(13))
    discard list.addChild(oldSecond, testFig(14))

    let inserted = list.insertChild(root, testFig(12), 1)

    check inserted == 2.FigIdx
    check list.nodes.mapIt(it.nodeId()) == @[10, 11, 12, 13, 14]
    check list.childIds(root) == @[11, 12, 13]
    check list.nodes[3].parent == root
    check list.nodes[4].parent == 3.FigIdx
    check list.nodes[0].childCount == 3
    check list.nodes[2].childCount == 0
    check list.nodes[3].childCount == 1

    let renders = newRenders()
    renders.setLayer(0.ZLevel, list)
    var roots: seq[RenderCursor]
    for rootCursor in renders.roots(0.ZLevel):
      roots.add rootCursor
    check renders.childIds(roots[0]) == @[11, 12, 13]

  test "insertChildren keeps physical indexes and traverses fragment roots in place":
    let renders = newRenders()
    let root = renders.addRoot(0.ZLevel, testFig(10))
    discard renders.addChild(0.ZLevel, root, testFig(40))

    var children = RenderList()
    let childRoot = children.addRoot(testFig(20))
    discard children.addChild(childRoot, testFig(21))
    discard children.addRoot(testFig(30))

    let inserted = renders.insertChildren(0.ZLevel, root, children, 0)

    check renders[0.ZLevel].nodes.mapIt(it.nodeId()) == @[10, 40]
    check inserted.len == 2
    check renders[inserted[0]].nodeId() == 20
    check renders[inserted[1]].nodeId() == 30
    check renders.childIds(RenderCursor(zlevel: 0.ZLevel, index: root)) == @[20, 30, 40]
    check renders.childIds(inserted[0]) == @[21]
    check renders[0.ZLevel].nodes[root.int].childCount == 1
    check renders[0.ZLevel].effectiveChildCount(root) == 3

  test "fragment roots can receive nested fragments through their cursors":
    let renders = newRenders()
    let root = renders.addRoot(0.ZLevel, testFig(10))

    var children = RenderList()
    let fragmentRoot = children.addRoot(testFig(20))
    discard children.addChild(fragmentRoot, testFig(21))
    let inserted = renders.insertChildren(0.ZLevel, root, children, 0)

    var nested = RenderList()
    discard nested.addRoot(testFig(22))
    discard renders.insertChildren(inserted[0], nested, 1)

    let appended = renders.addChild(inserted[0], testFig(23))

    check renders[appended].nodeId() == 23
    check renders.childIds(inserted[0]) == @[21, 22, 23]

  test "Renders addChildren forces layer zlevel":
    var renders = newRenders()
    let root = renders.addRoot(5.ZLevel, testFig(10, 1.ZLevel))

    var children = RenderList()
    let childRoot = children.addRoot(testFig(20, 9.ZLevel))
    discard children.addChild(childRoot, testFig(21, 9.ZLevel))

    let inserted = renders.addChildren(5.ZLevel, root, children)

    check inserted == @[1.FigIdx]
    check renders[5.ZLevel].nodes[0].zlevel == 5.ZLevel
    check renders[5.ZLevel].nodes[1].zlevel == 5.ZLevel
    check renders[5.ZLevel].nodes[2].zlevel == 5.ZLevel
    check renders[5.ZLevel].nodes[0].childCount == 1
    check renders[5.ZLevel].nodes[1].childCount == 1

  test "Renders accessor creates a mutable layer":
    let renders = newRenders()

    discard renders[4.ZLevel].addRoot(testFig(10, 4.ZLevel))

    check renders.len(4.ZLevel) == 1
    check renders[4.ZLevel].nodes[0].nodeId() == 10

  test "setLayer installs a complete render list":
    var list = RenderList()
    discard list.addRoot(testFig(10, 3.ZLevel))

    let renders = newRenders()
    renders.setLayer(3.ZLevel, list)

    check renders.len(3.ZLevel) == 1
    check renders[3.ZLevel].nodes[0].nodeId() == 10
