import std/[math, unittest]

import figdraw/fignodes
import figdraw/utils/drawutils

proc approxEq(a, b: float32, eps = 0.001'f32): bool =
  abs(a - b) <= eps

proc checkVec(p: Vec2, x, y: float32) =
  check p.x.approxEq(x)
  check p.y.approxEq(y)

proc testCorners(
    topLeft, topRight, bottomLeft, bottomRight: uint16
): array[DirectionCorners, uint16] =
  result[dcTopLeft] = topLeft
  result[dcTopRight] = topRight
  result[dcBottomLeft] = bottomLeft
  result[dcBottomRight] = bottomRight

suite "drawable rounded rectangle border helpers":
  test "solid square border emits four line ops":
    let ops = drawableRoundedRectBorderOps(
      rect(0.0'f32, 0.0'f32, 20.0'f32, 10.0'f32), testCorners(0, 0, 0, 0)
    )

    check ops.len == 4
    check ops[0].kind == dkLine
    checkVec(ops[0].a, 0.0'f32, 0.0'f32)
    checkVec(ops[0].b, 20.0'f32, 0.0'f32)
    check ops[1].kind == dkLine
    checkVec(ops[1].a, 20.0'f32, 0.0'f32)
    checkVec(ops[1].b, 20.0'f32, 10.0'f32)

  test "solid rounded border emits lines and corner arcs":
    let ops = drawableRoundedRectBorderOps(
      rect(0.0'f32, 0.0'f32, 100.0'f32, 50.0'f32), testCorners(10, 10, 10, 10)
    )

    check ops.len == 8
    check ops[0].kind == dkLine
    checkVec(ops[0].a, 10.0'f32, 0.0'f32)
    checkVec(ops[0].b, 90.0'f32, 0.0'f32)
    check ops[1].kind == dkArc
    checkVec(ops[1].arcCenter, 90.0'f32, 10.0'f32)
    check ops[1].arcRadius.approxEq(10.0'f32)
    check ops[1].startAngle.approxEq(-PI.float32 * 0.5'f32)
    check ops[1].sweepAngle.approxEq(PI.float32 * 0.5'f32)

  test "dashed square border follows one continuous phase":
    let ops = drawableDashedRoundedRectBorderOps(
      rect(0.0'f32, 0.0'f32, 20.0'f32, 10.0'f32),
      testCorners(0, 0, 0, 0),
      dashLength = 5.0'f32,
      gapLength = 5.0'f32,
    )

    check ops.len == 6
    check ops[0].kind == dkLine
    checkVec(ops[0].a, 0.0'f32, 0.0'f32)
    checkVec(ops[0].b, 5.0'f32, 0.0'f32)
    check ops[2].kind == dkLine
    checkVec(ops[2].a, 20.0'f32, 0.0'f32)
    checkVec(ops[2].b, 20.0'f32, 5.0'f32)

  test "dashed rounded border splits a dash across line and arc primitives":
    let ops = drawableDashedRoundedRectBorderOps(
      rect(0.0'f32, 0.0'f32, 40.0'f32, 40.0'f32),
      testCorners(10, 10, 10, 10),
      dashLength = 25.0'f32,
      gapLength = 1000.0'f32,
    )

    check ops.len == 2
    check ops[0].kind == dkLine
    checkVec(ops[0].a, 10.0'f32, 0.0'f32)
    checkVec(ops[0].b, 30.0'f32, 0.0'f32)
    check ops[1].kind == dkArc
    checkVec(ops[1].arcCenter, 30.0'f32, 10.0'f32)
    check ops[1].arcRadius.approxEq(10.0'f32)
    check ops[1].startAngle.approxEq(-PI.float32 * 0.5'f32)
    check ops[1].sweepAngle.approxEq(0.5'f32)

  test "dotted square border emits circle ops at edge-spaced centers":
    let ops = drawableDottedRoundedRectBorderOps(
      rect(0.0'f32, 0.0'f32, 20.0'f32, 10.0'f32),
      testCorners(0, 0, 0, 0),
      dotRadius = 1.0'f32,
      gapLength = 3.0'f32,
    )

    check ops.len == 12
    check ops[0].kind == dkCircle
    checkVec(ops[0].center, 0.0'f32, 0.0'f32)
    check ops[0].radius.approxEq(1.0'f32)
    check ops[4].kind == dkCircle
    checkVec(ops[4].center, 20.0'f32, 0.0'f32)

  test "dashed fig helper inflates bounds and localizes ops":
    let node = figDashedRoundedRectBorder(
      rect(10.0'f32, 20.0'f32, 20.0'f32, 10.0'f32),
      testCorners(0, 0, 0, 0),
      rgba(20, 30, 40, 255),
      weight = 4.0'f32,
      dashLength = 5.0'f32,
      gapLength = 5.0'f32,
    )

    check node.kind == nkDrawable
    check node.screenBox.x.approxEq(8.0'f32)
    check node.screenBox.y.approxEq(18.0'f32)
    check node.screenBox.w.approxEq(24.0'f32)
    check node.screenBox.h.approxEq(14.0'f32)
    check node.fill.color == rgba(0, 0, 0, 0)
    check node.drawStroke.weight.approxEq(4.0'f32)
    check node.drawStroke.fill.color == rgba(20, 30, 40, 255)
    check node.drawStroke.cap == scButt
    check node.drawOps[0].kind == dkLine
    checkVec(node.drawOps[0].a, 2.0'f32, 2.0'f32)
    checkVec(node.drawOps[0].b, 7.0'f32, 2.0'f32)

  test "solid fig helper inflates bounds and localizes ops":
    let node = figRoundedRectBorder(
      rect(10.0'f32, 20.0'f32, 20.0'f32, 10.0'f32),
      testCorners(0, 0, 0, 0),
      rgba(90, 100, 110, 255),
      weight = 4.0'f32,
    )

    check node.kind == nkDrawable
    check node.screenBox.x.approxEq(8.0'f32)
    check node.screenBox.y.approxEq(18.0'f32)
    check node.drawStroke.weight.approxEq(4.0'f32)
    check node.drawStroke.fill.color == rgba(90, 100, 110, 255)
    check node.drawStroke.cap == scButt
    check node.drawOps.len == 4
    check node.drawOps[0].kind == dkLine
    checkVec(node.drawOps[0].a, 2.0'f32, 2.0'f32)
    checkVec(node.drawOps[0].b, 22.0'f32, 2.0'f32)

  test "dotted fig helper uses fill circles without stroke":
    let node = figDottedRoundedRectBorder(
      rect(10.0'f32, 20.0'f32, 20.0'f32, 10.0'f32),
      testCorners(0, 0, 0, 0),
      rgba(60, 70, 80, 255),
      weight = 4.0'f32,
      gapLength = 3.0'f32,
    )

    check node.kind == nkDrawable
    check node.screenBox.x.approxEq(8.0'f32)
    check node.screenBox.y.approxEq(18.0'f32)
    check node.fill.color == rgba(60, 70, 80, 255)
    check node.drawStroke.weight.approxEq(0.0'f32)
    check node.drawOps[0].kind == dkCircle
    checkVec(node.drawOps[0].center, 2.0'f32, 2.0'f32)
    check node.drawOps[0].radius.approxEq(2.0'f32)
