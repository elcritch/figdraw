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
  when compiles(current.corners):
    for corner in DirectionCorners:
      result.corners[corner] = cornerToU16(current.corners[corner])

  case current.kind
  of nkRectangle:
    result.stroke.weight = current.stroke.weight
    when compiles(current.stroke.fill):
      result.stroke.fill = current.stroke.fill
    elif compiles(current.stroke.color.rgba()):
      result.stroke.fill = current.stroke.color.rgba()
    elif compiles(current.stroke.color):
      result.stroke.fill = current.stroke.color
    else:
      result.stroke.fill = fill(rgba(0, 0, 0, 0))

    for i in 0 ..< min(result.shadows.len(), current.shadows.len()):
      var shadow: RenderShadow
      let orig = current.shadows[i]
      when compiles(orig.style):
        shadow.style = orig.style
      else:
        shadow.style = NoShadow
      shadow.blur = orig.blur
      shadow.x = orig.x
      shadow.y = orig.y
      shadow.spread = orig.spread
      when compiles(orig.fill):
        shadow.fill = orig.fill
      elif compiles(orig.color.rgba()):
        shadow.fill = orig.color.rgba()
      elif compiles(orig.color):
        shadow.fill = orig.color
      else:
        shadow.fill = fill(rgba(0, 0, 0, 0))
      result.shadows[i] = shadow
  of nkImage:
    result.image.id = current.image.id
    when compiles(current.image.fill):
      result.image.fill = current.image.fill
    elif compiles(current.image.color.rgba()):
      result.image.fill = current.image.color.rgba()
    elif compiles(current.image.color):
      result.image.fill = current.image.color
    else:
      result.image.fill = fill(rgba(255, 255, 255, 255))
  of nkMsdfImage:
    when compiles(current.msdfImage):
      result.msdfImage = current.msdfImage
      when not compiles(current.msdfImage.fill):
        when compiles(current.msdfImage.color.rgba()):
          result.msdfImage.fill = current.msdfImage.color.rgba()
        elif compiles(current.msdfImage.color):
          result.msdfImage.fill = current.msdfImage.color
        else:
          result.msdfImage.fill = fill(rgba(255, 255, 255, 255))
  of nkMtsdfImage:
    when compiles(current.mtsdfImage):
      result.mtsdfImage = current.mtsdfImage
      when not compiles(current.mtsdfImage.fill):
        when compiles(current.mtsdfImage.color.rgba()):
          result.mtsdfImage.fill = current.mtsdfImage.color.rgba()
        elif compiles(current.mtsdfImage.color):
          result.mtsdfImage.fill = current.mtsdfImage.color
        else:
          result.mtsdfImage.fill = fill(rgba(255, 255, 255, 255))
  of nkBackdropBlur:
    when compiles(current.backdropBlur):
      result.backdropBlur = current.backdropBlur
    elif compiles(current.blur):
      result.backdropBlur.blur = current.blur
    else:
      result.backdropBlur.blur = 0.0'f32
  of nkTransform:
    when compiles(current.transform):
      result.transform = current.transform
    else:
      when compiles(current.translation):
        result.transform.translation = current.translation
      when compiles(current.matrix):
        result.transform.matrix = current.matrix
        result.transform.useMatrix = true
      elif compiles(current.transformMatrix):
        result.transform.matrix = current.transformMatrix
        result.transform.useMatrix = true
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
