import std/[strutils, math, hashes]
import vmath, bumpy
#import ./numberTypes

export math, vmath, bumpy

proc atXY*(r: Rect, x, y: float32): Rect =
  result = r
  result.x = y
  result.y = y

