import std/unicode
import std/monotimes
import std/hashes
import std/tables

import figdraw/commons
import figdraw/figbasics

type
  Shadow* = object
    kind*: ShadowStyle
    blur*: float32
    spread*: float32
    x*: float32
    y*: float32
    color*: Color

  AppFrame* = ref object
    root: FigTest
    size: Vec2

  FigTest* = ref object of RootObj #parent*: ptr Figuro
    uid*: FigID
    name*: string
    children*: seq[FigTest]

    box*, bpad*: Rect
    bmin*, bmax*: Vec2
    screenBox*: Rect
    offset*: Vec2
    scroll*: Vec2
    prevSize*: Vec2

    flags*: set[FigFlags]

    zlevel*: ZLevel
    rotation*: float32
    fill*: Color
    highlight*: Color
    stroke*: RenderStroke

    kind*: FigKind
    shadows*: array[2, Shadow]
    corners*: array[DirectionCorners, float32]
    image*: ImageStyle
    textLayout*: GlyphArrangement
    points*: seq[Vec2]

    selectionRange*: Slice[int16]
    selectionColor*: Color

  Rectangle* = ref object of FigTest
  TestBasic* = ref object of FigTest

var nextUid: FigID = 0

template atom*(s: untyped): string =
  s

proc initRoot*(root: FigTest) =
  nextUid = 0
  root.children.setLen(0)
  root.uid = nextUid
  nextUid.inc

proc initChild(parent: FigTest, child: FigTest, name: string, kind: FigKind) =
  child.uid = nextUid
  nextUid.inc
  child.name = name
  child.kind = kind
  child.zlevel = parent.zlevel
  child.children.setLen(0)
  parent.children.add(child)

template withWidget*(root: FigTest, body: untyped) =
  block:
    initRoot(root)
    var this {.inject.} = root
    body

template new*(t: typedesc[Rectangle], name: string, body: untyped) =
  block:
    let parent = this
    var node = Rectangle()
    initChild(parent, node, name, nkRectangle)
    var this {.inject.} = node
    body

template new*(t: typedesc[Rectangle], name: string) =
  t.new(name):
    discard

proc newAppFrame*(root: FigTest, size: (float32, float32)): AppFrame =
  result = AppFrame()
  result.root = root
  result.size.x = size[0]
  result.size.y = size[1]
