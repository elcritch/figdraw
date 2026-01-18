import std/[strutils, math, hashes]
import vmath, bumpy
import ./numberTypes

export math, vmath, numberTypes, bumpy

## Keep these aliases compatible with Figuro's coordinate system.
type
  Box* = UiBox
  Position* = UiPos
  Size* = UiSize

type
  PercKind* = enum
    relative
    absolute

  Percent* = distinct float32
  Percentages* = tuple[value: float32, kind: PercKind]

converter toUis*[F: float | int | float32](x: static[F]): UiScalar =
  UiScalar x

proc `'ui`*(n: string): UiScalar {.compileTime.} =
  ## numeric literal UI Coordinate unit
  result = UiScalar(parseFloat(n))

proc initBox*(x, y, w, h: UiScalar | SomeNumber): Box =
  uiBox(x.UiScalar, y.UiScalar, w.UiScalar, h.UiScalar).Box

proc initPosition*(x, y: UiScalar): Position =
  uiPos(x, y).Position

proc initPosition*(x, y: float32): Position =
  initPosition(x.UiScalar, y.UiScalar)

proc initSize*(w, h: UiScalar): Size =
  uiSize(w, h).Size

proc initSize*(w, h: float32): Size =
  initSize(w.UiScalar, h.UiScalar)

proc hash*(p: Position): Hash =
  result = Hash(0)
  result = result !& hash(p.x)
  result = result !& hash(p.y)
  result = !$result

proc atXY*[T: Box](rect: T, x, y: int | float32): T =
  result = rect
  result.x = UiScalar(x)
  result.y = UiScalar(y)

proc atXY*[T: Box](rect: T, x, y: UiScalar): T =
  result = rect
  result.x = x
  result.y = y

proc atXY*[T: Rect](rect: T, x, y: int | float32): T =
  result = rect
  result.x = x
  result.y = y

proc `~=`*(rect: Vec2, val: float32): bool =
  result = rect.x ~= val and rect.y ~= val

proc overlaps*(a, b: Position): bool =
  overlaps(a.toVec(), b.toVec())

proc overlaps*(a: Position, b: Box): bool =
  overlaps(a.toVec(), b.toRect())

proc overlaps*(a: Box, b: Position): bool =
  overlaps(a.toRect(), b.toVec())

proc overlaps*(a: Box, b: Box): bool =
  overlaps(a.toRect(), b.toRect())

proc sum*(rect: Position): UiScalar =
  result = rect.x + rect.y

proc sum*(rect: Rect): float32 =
  result = rect.x + rect.y + rect.w + rect.h

proc sum*(rect: (float32, float32, float32, float32)): float32 =
  result = rect[0] + rect[1] + rect[2] + rect[3]

proc sum*(rect: Box): UiScalar =
  result = rect.x + rect.y + rect.w + rect.h

proc sum*(rect: (UiScalar, UiScalar, UiScalar, UiScalar)): UiScalar =
  result = rect[0] + rect[1] + rect[2] + rect[3]
