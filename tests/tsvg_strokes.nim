import std/unittest
import pixie/paths
import vmath
import figdraw/svgs/svgstrokes

suite "SVG stroke outlines":
  test "joins and miter limit":
    let path = parsePath("M10 40 L30 40 L30 10")
    let miter = strokeOutline(path, 10, ButtCap, MiterJoin, 4, @[], 0)
    let bevel = strokeOutline(path, 10, ButtCap, BevelJoin, 4, @[], 0)
    let limited = strokeOutline(path, 10, ButtCap, MiterJoin, 1, @[], 0)
    check miter.fillOverlaps(vec2(33, 43))
    check not bevel.fillOverlaps(vec2(33, 43))
    check not limited.fillOverlaps(vec2(33, 43))

  test "dash phase continues through segment boundaries":
    let path = parsePath("M8 32 L18 32 L56 32")
    let outline = strokeOutline(path, 4, ButtCap, MiterJoin, 4, @[8'f32, 8], 0)
    check outline.fillOverlaps(vec2(12, 32))
    check not outline.fillOverlaps(vec2(20, 32))
    check outline.fillOverlaps(vec2(28, 32))
    let shifted = strokeOutline(path, 4, ButtCap, MiterJoin, 4, @[8'f32, 8], 4)
    check shifted.fillOverlaps(vec2(10, 32))
    check not shifted.fillOverlaps(vec2(14, 32))

  test "caps and closed subpaths":
    let path = parsePath("M10 10 L20 10")
    let butt = strokeOutline(path, 4, ButtCap, MiterJoin, 4, @[], 0)
    let round = strokeOutline(path, 4, RoundCap, MiterJoin, 4, @[], 0)
    check not butt.fillOverlaps(vec2(9, 10))
    check round.fillOverlaps(vec2(9, 10))
    let closed = strokeOutline(
      parsePath("M10 10 L20 10 L20 20 Z"), 4, ButtCap, MiterJoin, 4, @[], 0
    )
    check closed.fillOverlaps(vec2(10, 10))

  test "zero length subpaths and dash dots":
    let point = parsePath("M10 10 L10 10 M20 20 L20 20")
    let round = strokeOutline(point, 4, RoundCap, MiterJoin, 4, @[], 0)
    let square = strokeOutline(point, 4, SquareCap, MiterJoin, 4, @[], 0)
    let butt = strokeOutline(point, 4, ButtCap, MiterJoin, 4, @[], 0)
    check round.fillOverlaps(vec2(10, 10))
    check square.fillOverlaps(vec2(20, 20))
    check not butt.fillOverlaps(vec2(10, 10))
    let dots = strokeOutline(
      parsePath("M10 10 L30 10"), 4, RoundCap, MiterJoin, 4, @[0'f32, 8], 0
    )
    check dots.fillOverlaps(vec2(10, 10))
    check dots.fillOverlaps(vec2(18, 10))
    check not dots.fillOverlaps(vec2(14, 10))
