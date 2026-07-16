import std/[math, unittest]

import figdraw/drawablepaths
import figdraw/fignodes

proc triangleArea(triangle: DrawableTriangle): float32 =
  abs(
    (triangle[1].x - triangle[0].x) * (triangle[2].y - triangle[0].y) -
      (triangle[1].y - triangle[0].y) * (triangle[2].x - triangle[0].x)
  ) * 0.5'f32

proc totalArea(triangles: openArray[DrawableTriangle]): float32 =
  for triangle in triangles:
    result += triangle.triangleArea()

proc rectangleContour(x, y, w, h: float32, reverse = false): DrawableContour =
  let
    topLeft = vec2(x, y)
    topRight = vec2(x + w, y)
    bottomRight = vec2(x + w, y + h)
    bottomLeft = vec2(x, y + h)
    points =
      if reverse:
        [topLeft, bottomLeft, bottomRight, topRight]
      else:
        [topLeft, topRight, bottomRight, bottomLeft]
  initDrawableContour(
    [
      drawablePathLine(points[0], points[1]),
      drawablePathLine(points[1], points[2]),
      drawablePathLine(points[2], points[3]),
      drawablePathLine(points[3], points[0]),
    ]
  )

suite "drawable path triangulation":
  test "triangulates a closed rectangle":
    let
      path = initDrawablePath([rectangleContour(0, 0, 10, 10)])
      triangles = triangulateDrawablePath(path)

    check triangles.len == 2
    check abs(triangles.totalArea() - 100.0'f32) < 0.001'f32

  test "triangulates a concave contour":
    let contour = initDrawableContour(
      [
        drawablePathLine(0, 0, 10, 0),
        drawablePathLine(10, 0, 10, 10),
        drawablePathLine(10, 10, 5, 5),
        drawablePathLine(5, 5, 0, 10),
        drawablePathLine(0, 10, 0, 0),
      ]
    )
    let triangles = triangulateDrawablePath(initDrawablePath([contour]))

    check triangles.len > 0
    check abs(triangles.totalArea() - 75.0'f32) < 0.001'f32

  test "even odd fill removes an inner contour":
    let path = initDrawablePath(
      [rectangleContour(0, 0, 10, 10), rectangleContour(3, 3, 4, 4)], dfrEvenOdd
    )
    let triangles = triangulateDrawablePath(path)

    check abs(triangles.totalArea() - 84.0'f32) < 0.001'f32

  test "non zero fill follows contour winding":
    let
      filledPath = initDrawablePath(
        [rectangleContour(0, 0, 10, 10), rectangleContour(3, 3, 4, 4)], dfrNonZero
      )
      holePath = initDrawablePath(
        [rectangleContour(0, 0, 10, 10), rectangleContour(3, 3, 4, 4, reverse = true)],
        dfrNonZero,
      )

    check abs(triangulateDrawablePath(filledPath).totalArea() - 100.0'f32) < 0.001'f32
    check abs(triangulateDrawablePath(holePath).totalArea() - 84.0'f32) < 0.001'f32

  test "adaptively flattens quadratic bezier contours":
    let contour = initDrawableContour(
      [
        drawablePathBezier(
          vec2(0.0'f32, 0.0'f32), vec2(5.0'f32, 10.0'f32), vec2(10.0'f32, 0.0'f32)
        ),
        drawablePathLine(10, 0, 0, 0),
      ]
    )
    let
      points = flattenDrawableContour(contour)
      triangles = triangulateDrawablePath(initDrawablePath([contour]))

    check points.len > 3
    check triangles.len > 0
    check triangles.totalArea() > 30.0'f32
    check triangles.totalArea() < 34.0'f32

  test "quadratic boundaries match adaptive contour segments":
    let
      contour = initDrawableContour(
        [
          drawablePathBezier(
            vec2(0.0'f32, 0.0'f32), vec2(5.0'f32, 10.0'f32), vec2(10.0'f32, 0.0'f32)
          ),
          drawablePathLine(10, 0, 0, 0),
        ]
      )
      path = initDrawablePath([contour])
      points = flattenDrawableContour(contour)
      boundaries = drawablePathQuadraticBoundaries(path)

    check boundaries.len > 1
    check boundaries.len == points.len - 1
    for idx, boundary in boundaries:
      check boundary.p0 == points[idx]
      check boundary.p2 == points[idx + 1]
      check boundary.insideSign < 0.0'f32

  test "even odd holes reverse the quadratic filled side":
    let
      outer = initDrawableContour(
        [
          drawablePathBezier(
            vec2(0.0'f32, 0.0'f32), vec2(10.0'f32, 20.0'f32), vec2(20.0'f32, 0.0'f32)
          ),
          drawablePathLine(20, 0, 0, 0),
        ]
      )
      hole = initDrawableContour(
        [
          drawablePathBezier(
            vec2(6.0'f32, 4.0'f32), vec2(10.0'f32, 10.0'f32), vec2(14.0'f32, 4.0'f32)
          ),
          drawablePathLine(14, 4, 6, 4),
        ]
      )
      boundaries =
        drawablePathQuadraticBoundaries(initDrawablePath([outer, hole], dfrEvenOdd))
    var
      hasOuterSide = false
      hasHoleSide = false
    for boundary in boundaries:
      if boundary.insideSign < 0.0'f32:
        hasOuterSide = true
      elif boundary.insideSign > 0.0'f32:
        hasHoleSide = true

    check hasOuterSide
    check hasHoleSide

  test "non zero fill skips a same winding internal boundary":
    let
      outer = initDrawableContour(
        [
          drawablePathBezier(
            vec2(0.0'f32, 0.0'f32), vec2(10.0'f32, 20.0'f32), vec2(20.0'f32, 0.0'f32)
          ),
          drawablePathLine(20, 0, 0, 0),
        ]
      )
      inner = initDrawableContour(
        [
          drawablePathBezier(
            vec2(6.0'f32, 4.0'f32), vec2(10.0'f32, 10.0'f32), vec2(14.0'f32, 4.0'f32)
          ),
          drawablePathLine(14, 4, 6, 4),
        ]
      )
      boundaries =
        drawablePathQuadraticBoundaries(initDrawablePath([outer, inner], dfrNonZero))

    check boundaries.len > 0
    for boundary in boundaries:
      check boundary.insideSign < 0.0'f32

  test "flattens and fills a complete circular arc":
    let contour = initDrawableContour(
      [
        drawablePathArc(
          vec2(20.0'f32, 20.0'f32),
          20.0'f32,
          0.0'f32,
          PI.float32 * 2.0'f32,
          steps = 64'u16,
        )
      ]
    )
    let triangles = triangulateDrawablePath(initDrawablePath([contour]))

    check triangles.len > 0
    check abs(triangles.totalArea() - PI.float32 * 400.0'f32) < 6.0'f32
