import std/sequtils
import stack_strings
import ../fignodes

type RenderTree* = ref object
  id*: int
  name*: string
  children*: seq[RenderTree]

func `[]`*(a: RenderTree, idx: int): RenderTree =
  if a.children.len() == 0:
    return RenderTree(name: "Missing")
  a.children[idx]

func `==`*(a, b: RenderTree): bool =
  if a.isNil and b.isNil:
    return true
  if a.isNil or b.isNil:
    return false
  `==`(a[], b[])

proc toTree*(nodes: seq[Fig], idx = 0.FigIdx, depth = 1): RenderTree =
  let n = nodes[idx.int]
  result = RenderTree(id: n.uid, name: $n.name)
  for ci in nodes.childIndex(idx):
    result.children.add toTree(nodes, ci, depth + 1)

proc toTree*(list: RenderList): RenderTree =
  result = RenderTree(name: "pseudoRoot")
  for rootIdx in list.rootIds:
    # echo "toTree:rootIdx: ", rootIdx.int
    result.children.add toTree(list.nodes, rootIdx)

proc findRoot*(list: RenderList, node: Fig): Fig =
  result = node
  var cnt = 0
  var curr = result
  while result.parent != -1.FigID and result.uid != result.parent:
    var curr = result
    for n in list.nodes:
      if n.uid == result.parent:
        result = n
        break

    if curr.uid == result.uid:
      return

    cnt.inc
    if cnt > 1_00:
      raise newException(IndexDefect, "error finding root")

proc add*(list: var RenderList, node: Fig) =
  ## Adds a Fig to the RenderList and possibly
  ## to the roots seq if it's a root node.
  ##
  ## New roots occur when nodes have different
  ## zlevels and end up in a the RenderList
  ## for that ZLevel without their logical parent. 
  ##
  if list.rootIds.len() == 0:
    list.rootIds.add(list.nodes.len().FigIdx)
  elif node.parent == -1:
    list.rootIds.add(list.nodes.len().FigIdx)
  else:
    let lastRoot = list.nodes[list.rootIds[^1].int]
    let nr = findRoot(list, node)
    if nr.uid != lastRoot.uid and node.uid != list.nodes[^1].uid:
      list.rootIds.add(list.nodes.len().FigIdx)
  list.nodes.add(node)

proc toRenderFig*[N](current: N): Fig =
  result = Fig(kind: current.kind)

  result.uid = current.uid
  result.name = current.name.toFigName()

  result.screenBox = current.screenBox.scaled
  result.offset = current.offset.scaled
  result.scroll = current.scroll.scaled
  result.flags = current.flags

  result.zlevel = current.zlevel
  result.rotation = current.rotation
  result.fill = current.fill
  result.highlight = current.highlight

  result.stroke.weight = current.stroke.weight.scaled
  result.stroke.color = current.stroke.color


  case current.kind
  of nkRectangle:
    for i in 0..<min(result.shadows.len(), current.shadows.len()):
      var shadow: RenderShadow
      let orig = current.shadows[i]
      shadow.blur = orig.blur.scaled
      shadow.x = orig.x.scaled
      shadow.y = orig.y.scaled
      shadow.color = orig.color
      shadow.spread = orig.spread.scaled
      result.shadows[i] = shadow

    for corner in DirectionCorners:
      result.corners[corner] = current.corners[corner].scaled

  of nkImage:
    result.image = current.image
  of nkText:
    result.textLayout = current.textLayout
  of nkDrawable:
    result.points = current.points.mapIt(it)
  else:
    discard

proc convert*[N](
    renders: var Renders, current: N, parent: FigID, maxzlvl: ZLevel
) =
  # echo "convert:node: ", current.uid, " parent: ", parent
  var render = current.toRenderFig()
  render.parent = parent
  render.childCount = current.children.len().int8
  let zlvl = current.zlevel

  for child in current.children:
    let chlvl = child.zlevel
    if chlvl != zlvl or
      NfInactive in child.flags or
      NfDead in child.flags or
      Hidden in child.userAttrs:
      render.childCount.dec()

  renders.layers.mgetOrPut(zlvl, RenderList()).add(render)
  for child in current.children:
    let chlvl = child.zlevel
    if NfInactive notin child.flags and
        NfDead notin child.flags and
        Hidden notin child.userAttrs:
      renders.convert(child, current.uid, chlvl)

proc copyInto*[N](uis: N): Renders =
  result = Renders()
  result.layers = initOrderedTable[ZLevel, RenderList]()
  result.convert(uis, -1.FigID, 0.ZLevel)

  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )
  # echo "nodes:len: ", result.len()
  # printRenders(result)
