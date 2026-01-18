import std/[tables, hashes]
export tables, hashes

import ./figbasics
export figbasics

type

  RenderList* = object
    nodes*: seq[Fig]
    rootIds*: seq[FigIdx]

  Renders* = ref object
    layers*: OrderedTable[ZLevel, RenderList]

  FigIdx* = distinct int16

  Fig* = object
    zlevel*: ZLevel
    childCount*: int8
    uid*: FigID
    parent*: FigID
    flags*: set[FigFlags]

    offset*: Vec2
    scroll*: Vec2

    screenBox*: Rect

    rotation*: float32
    fill*: Color
    highlight*: Color
    stroke*: RenderStroke
    image*: ImageStyle

    case kind*: FigKind
    of nkRectangle:
      shadows*: array[ShadowCount, RenderShadow]
      corners*: array[DirectionCorners, float32]
    of nkText:
      textLayout*: GlyphArrangement
    of nkDrawable:
      points*: seq[Vec2]
    of nkImage:
      discard
    else:
      discard

    name*: FigName

proc `$`*(id: FigIdx): string =
  "FigIdx(" & $(int(id)) & ")"

proc toFigName*(s: string): FigName =
  toStackString(s[0..<min(s.len(), s.len())], FigStringCap)
proc toFigName*(s: FigName): FigName = s

proc `+`*(a, b: FigIdx): FigIdx {.borrow.}
proc `<=`*(a, b: FigIdx): bool {.borrow.}
proc `==`*(a, b: FigIdx): bool {.borrow.}

proc `[]`*(r: Renders, lvl: ZLevel): RenderList =
  r.layers[lvl]

proc addChild*(list: var RenderList, parentIdx: FigIdx, child: Fig): FigIdx {.discardable.} =
  ## Appends `child` to `list.nodes`, sets `child.parent` from `parentIdx`,
  ## and increments the parent's `childCount`.
  ##
  ## Returns the child's index within `list.nodes`.
  let pidx = parentIdx.int
  assert pidx >= 0 and pidx < list.nodes.len

  let newIdx = list.nodes.len
  assert newIdx <= high(int16).int

  if list.nodes[pidx].childCount == high(int8):
    raise newException(ValueError, "RenderList parent childCount overflow")
  inc list.nodes[pidx].childCount

  var childNode = child
  childNode.parent = list.nodes[pidx].uid
  list.nodes.add childNode
  result = newIdx.FigIdx

template pairs*(r: Renders): auto =
  r.layers.pairs()
template contains*(r: Renders, lvl: ZLevel): bool =
  r.layers.contains(lvl)

iterator childIndex*(nodes: seq[Fig], current: FigIdx): FigIdx =
  let id = nodes[current.int].uid
  let childCnt = nodes[current.int].childCount

  var idx = current.int
  var cnt = 0
  while cnt < childCnt:
    if idx >= nodes.len:
      raise newException(IndexDefect, "child indexes incorrect!")
    if nodes[idx.int].parent == id:
      cnt.inc()
      yield idx.FigIdx
    idx.inc()
