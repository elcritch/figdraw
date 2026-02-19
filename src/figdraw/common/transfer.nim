import std/[math, sequtils]
import ../fignodes

type RenderTree* = ref object
  id*: int
  children*: seq[RenderTree]

proc cornerToU16(v: uint16): uint16 {.inline.} =
  v

proc cornerToU16(v: SomeInteger): uint16 {.inline.} =
  if v <= 0:
    return 0'u16
  min(v.int, high(uint16).int).uint16

proc cornerToU16(v: SomeFloat): uint16 {.inline.} =
  if v <= 0.0:
    return 0'u16
  min(v.round().int, high(uint16).int).uint16

func `[]`*(a: RenderTree, idx: int): RenderTree =
  if a.children.len() == 0:
    return RenderTree()
  a.children[idx]

func `==`*(a, b: RenderTree): bool =
  if a.isNil and b.isNil:
    return true
  if a.isNil or b.isNil:
    return false
  `==`(a[], b[])

proc toTree*(nodes: seq[Fig], idx = 0.FigIdx, depth = 1): RenderTree =
  result = RenderTree(id: idx.int)
  for ci in nodes.childIndex(idx):
    result.children.add toTree(nodes, ci, depth + 1)

proc toTree*(list: RenderList): RenderTree =
  result = RenderTree()
  for rootIdx in list.rootIds:
    # echo "toTree:rootIdx: ", rootIdx.int
    result.children.add toTree(list.nodes, rootIdx)

proc toRenderFig*[N](current: N): Fig =
  result = Fig(kind: current.kind)

  result.screenBox = current.screenBox
  result.flags = current.flags

  result.zlevel = current.zlevel
  result.rotation = current.rotation
  when compiles(current.fill.rgba()):
    result.fill = current.fill.rgba()
  else:
    result.fill = current.fill
  when compiles(current.fillGradient):
    result.fillGradient = current.fillGradient

  case current.kind
  of nkRectangle:
    result.stroke.weight = current.stroke.weight
    result.stroke.color = current.stroke.color

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
      result.corners[corner] = cornerToU16(current.corners[corner])
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
    if NfInactive in child.flags:
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
