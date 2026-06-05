import std/[sequtils, unittest]

import figdraw/fignodes

proc testFig(id: int, zlevel = 0.ZLevel): Fig =
  Fig(kind: nkRectangle, zlevel: zlevel, rotation: id.float32)

proc nodeId(node: Fig): int =
  node.rotation.int

proc childIds(list: RenderList, parentIdx: FigIdx): seq[int] =
  for childIdx in list.nodes.childIndex(parentIdx):
    result.add list.nodes[childIdx.int].nodeId()

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

  test "insertChildren remaps incoming roots and internal parents":
    var list = RenderList()
    let root = list.addRoot(testFig(10))
    discard list.addChild(root, testFig(40))

    var children = RenderList()
    let childRoot = children.addRoot(testFig(20))
    discard children.addChild(childRoot, testFig(21))
    discard children.addRoot(testFig(30))

    let inserted = list.insertChildren(root, children, 0)

    check inserted == @[1.FigIdx, 3.FigIdx]
    check list.nodes.mapIt(it.nodeId()) == @[10, 20, 21, 30, 40]
    check list.childIds(root) == @[20, 30, 40]
    check list.nodes[1].parent == root
    check list.nodes[2].parent == 1.FigIdx
    check list.nodes[3].parent == root
    check list.nodes[4].parent == root
    check list.nodes[0].childCount == 3
    check list.nodes[1].childCount == 1

  test "Renders addChildren forces layer zlevel":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())
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
