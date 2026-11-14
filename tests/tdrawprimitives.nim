import std/unittest
import figdraw/fignodes
import figdraw/utils/drawprimitives

suite "Drawable primitive nodes":
  test "ellipse and circle retain their geometry and paint":
    let
      bounds = rect(3, 4, 20, 10)
      paint = fill(rgba(255, 0, 0, 255))
      stroke = RenderStroke(weight: 2, fill: paint)
      ellipse = figEllipse(bounds, paint, stroke)
      circle = figCircle(bounds, paint, stroke)
    check ellipse.screenBox == bounds
    check ellipse.fill == paint
    check ellipse.drawStroke.weight == 2
    check ellipse.drawOps[0].ellipseCenter == vec2(10, 5)
    check ellipse.drawOps[0].ellipseRadii == vec2(10, 5)
    check circle.drawOps[0].center == vec2(10, 5)
    check circle.drawOps[0].radius == 5
    check ellipse.drawOps[0].strokeBounds == rect(-1, -1, 22, 12)
    check circle.drawOps[0].strokeBounds == rect(4, -1, 12, 12)

  test "stroke bounds reject other drawable kinds":
    var line = drawableLine(vec2(0), vec2(1))
    expect ValueError:
      discard line.strokeBounds
    expect ValueError:
      line.strokeBounds = rect(0, 0, 1, 1)

  test "refresh bounds after changing stroke or geometry":
    var node = figEllipse(rect(3, 4, 20, 10), fill(rgba(0, 0, 0, 0)))
    node.drawStroke.weight = 6
    node.drawOps[0].ellipseRadii = vec2(8, 3)
    node.prepareDrawableStroke()
    check node.drawOps[0].strokeBounds == rect(-1, -1, 22, 12)

import pkg/pixie
import figdraw/figrender
import figdraw/software/context

suite "Centered primitive strokes":
  test "eccentric ellipse follows a Pixie stroke along the diagonal":
    let
      bounds = rect(12, 28, 104, 40)
      stroke = RenderStroke(weight: 10, fill: fill(rgba(255, 0, 0, 255)))
    var list: RenderList
    discard list.addRoot(figEllipse(bounds, fill(rgba(0, 0, 0, 0)), stroke))
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(
      scene, vec2(128, 96), clearColor = color(0, 0, 0, 0)
    )
    let actual = ctx.readPixels(rect(0, 0, 0, 0), false)
    let expected = newImage(128, 96)
    expected.strokePath(
      parsePath("M116 48 A52 20 0 1 1 12 48 A52 20 0 1 1 116 48 Z"),
      color(1, 0, 0, 1),
      strokeWidth = 10,
    )
    for point in [(94, 29), (95, 33), (94, 37), (94, 23), (90, 20)]:
      let (x, y) = point
      check abs(actual[x, y].a.int - expected[x, y].a.int) < 60

  test "circle stroke extends equally inside and outside its path":
    var list: RenderList
    let stroke = RenderStroke(weight: 12, fill: fill(rgba(255, 0, 0, 255)))
    discard
      list.addRoot(figCircle(rect(16, 16, 32, 32), fill(rgba(0, 0, 0, 0)), stroke))
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
    let actual = ctx.readPixels(rect(0, 0, 0, 0), false)
    check actual[32, 32].a == 0
    check actual[20, 32].a == 255
    check actual[52, 32].a == 255
    check actual[55, 32].a == 0

  test "raw ellipse and circle drawables retain inset strokes":
    for isCircle in [false, true]:
      var list: RenderList
      let op =
        if isCircle:
          drawableCircle(vec2(16), 16)
        else:
          drawableEllipse(vec2(16), vec2(16))
      discard list.addRoot(
        Fig(
          kind: nkDrawable,
          screenBox: rect(16, 16, 32, 32),
          fill: fill(rgba(0, 0, 0, 0)),
          drawStroke: RenderStroke(weight: 12, fill: fill(rgba(255, 0, 0, 255))),
          drawOps: @[op],
        )
      )
      var scene = newRenders()
      scene.setLayer(0.ZLevel, list)
      let ctx = newSoftwareContext(workers = 1)
      newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
      let actual = ctx.readPixels(rect(0, 0, 0, 0), false)
      check actual[20, 32].a == 255
      check actual[52, 32].a == 0
