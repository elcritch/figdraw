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
  result = RenderTree(id: idx.int)
  when FigDrawNames:
    result.name = $n.name
  for ci in nodes.childIndex(idx):
    result.children.add toTree(nodes, ci, depth + 1)

proc toTree*(list: RenderList): RenderTree =
  result = RenderTree(name: "pseudoRoot")
  for rootIdx in list.rootIds:
    # echo "toTree:rootIdx: ", rootIdx.int
    result.children.add toTree(list.nodes, rootIdx)

proc toRenderFig*[N](current: N): Fig =
  result = Fig(kind: current.kind)

  when FigDrawNames:
    result.name = current.name.toFigName()

  result.screenBox = current.screenBox
  result.flags = current.flags

  result.zlevel = current.zlevel
  result.rotation = current.rotation
  result.fill = current.fill

  result.stroke.weight = current.stroke.weight
  result.stroke.color = current.stroke.color

  case current.kind
  of nkRectangle:
    for i in 0 ..< min(result.shadows.len(), current.shadows.len()):
      var shadow: RenderShadow
      let orig = current.shadows[i]
      shadow.blur = orig.blur
      shadow.x = orig.x
      shadow.y = orig.y
      shadow.color = orig.color
      shadow.spread = orig.spread
      result.shadows[i] = shadow

    for corner in DirectionCorners:
      result.corners[corner] = current.corners[corner]
  of nkImage:
    result.image = current.image
  of nkMsdfImage:
    when compiles(current.msdfImage):
      result.msdfImage = current.msdfImage
  of nkMtsdfImage:
    when compiles(current.mtsdfImage):
      result.mtsdfImage = current.mtsdfImage
  of nkText:
    result.textLayout = current.textLayout
    result.selectionRange = current.selectionRange
    result.selectionColor = current.selectionColor
    result.selectionEnabled = current.selectionEnabled
  of nkDrawable:
    result.points = current.points.mapIt(it)
  else:
    discard

proc convert*[N](
    renders: var Renders, current: N, parentIdx: FigIdx, parentZLevel: ZLevel
) =
  var render = current.toRenderFig()
  let zlvl = current.zlevel

  if zlvl notin renders.layers:
    renders.layers[zlvl] = RenderList()

  let currentIdx =
    if parentIdx.int < 0 or parentZLevel != zlvl:
      renders.layers[zlvl].addRoot(render)
    else:
      renders.layers[zlvl].addChild(parentIdx, render)

  for child in current.children:
    if NfInactive in child.flags or NfDead in child.flags:
      continue

    let childParentIdx =
      if child.zlevel == zlvl:
        currentIdx
      else:
        (-1).FigIdx
    renders.convert(child, childParentIdx, zlvl)

proc copyInto*[N](uis: N): Renders =
  result = Renders()
  result.layers = initOrderedTable[ZLevel, RenderList]()
  result.convert(uis, (-1).FigIdx, uis.zlevel)

  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )
  # echo "nodes:len: ", result.len()
  # printRenders(result)
