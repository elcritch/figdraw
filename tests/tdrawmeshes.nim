import std/unittest
import pkg/pixie
import figdraw/fignodes
import figdraw/figrender
import figdraw/software/context
import figdraw/svgs/svgstrokes
import figdraw/utils/drawmeshes

suite "Stroke outline meshes":
  test "draws opaque joined strokes and transformed quads":
    let outline =
      strokeOutline(parsePath("M10 12 L36 12 L36 38"), 8, ButtCap, MiterJoin, 4, @[], 0)
    let ops = drawableStrokeOutlineOps(outline)
    check ops.len > 2
    var list: RenderList
    var matrix = mat4()
    matrix[0, 0] = 1.5
    matrix[1, 1] = 1.5
    let transform = list.addRoot(
      Fig(
        kind: nkTransform,
        screenBox: rect(0, 0, 80, 80),
        transform:
          TransformStyle(translation: vec2(5, 3), matrix: matrix, useMatrix: true),
      )
    )
    discard list.addChild(
      transform,
      Fig(
        kind: nkDrawable,
        screenBox: rect(0, 0, 50, 50),
        fill: fill(rgba(255, 0, 0, 255)),
        drawOps: ops,
      ),
    )
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(80), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[35, 21].a > 220
    check image[59, 35].a > 220
    check image[63, 17].a > 220
    check image[30, 45].a == 0

  test "round caps and joins become circle primitives":
    let outline = strokeOutline(
      parsePath("M10 12 L36 12 L36 38"), 8, RoundCap, RoundJoin, 4, @[], 0
    )
    let ops = drawableStrokeOutlineOps(outline)
    var circles = 0
    for op in ops:
      if op.kind == dkCircle:
        inc circles
    check circles >= 3
