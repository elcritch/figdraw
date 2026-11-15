import std/unittest
import figdraw/fignodes
import figdraw/utils/drawpaths

suite "drawable line helpers":
  test "dash offset and odd patterns":
    let ops = drawableDashedLineOps(vec2(0, 0), vec2(30, 0), @[4'f32, 2], 2)
    check ops.len == 6
    check ops[0].a == vec2(0, 0)
    check ops[0].b == vec2(2, 0)
    check ops[1].a == vec2(4, 0)
    let odd = drawableDashedLineOps(vec2(0, 0), vec2(20, 0), @[4'f32], 0)
    check odd.len == 3
  test "fig line uses supplied stroke":
    let stroke = RenderStroke(weight: 3, cap: scButt)
    let fig = figLine(vec2(2, 3), vec2(12, 3), stroke)
    check fig.kind == nkDrawable
    check fig.drawStroke.weight == 3
    check fig.drawOps.len == 1
