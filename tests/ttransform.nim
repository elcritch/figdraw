import std/[tables, unittest]

import figdraw/commons
import figdraw/figrender
import figdraw/fignodes

type RecordingBackend = ref object of BackendContext
  mat: Mat4
  mats: seq[Mat4]
  draws: seq[Rect]
  aaFactor: float32
  aaChanges: seq[float32]

method drawRect*(ctx: RecordingBackend, rect: Rect, color: Color) =
  discard color
  let topLeft = (ctx.mat * vec3(rect.x, rect.y, 1.0'f32)).xy
  var transformed = rect
  transformed.x = topLeft.x
  transformed.y = topLeft.y
  ctx.draws.add transformed

method drawRoundedRectSdf*(
    ctx: RecordingBackend,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: array[DirectionCorners, float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) =
  discard colors
  discard radii
  discard mode
  discard factor
  discard spread
  discard shapeSize
  let topLeft = (ctx.mat * vec3(rect.x, rect.y, 1.0'f32)).xy
  var transformed = rect
  transformed.x = topLeft.x
  transformed.y = topLeft.y
  ctx.draws.add transformed

method drawQuadraticBezierSdf*(
    ctx: RecordingBackend,
    rect: Rect,
    fill: BackendFill,
    p0, p1, p2: Vec2,
    strokeWeight: float32,
    cap: StrokeCap,
) =
  discard fill
  discard p0
  discard p1
  discard p2
  discard strokeWeight
  discard cap
  let topLeft = (ctx.mat * vec3(rect.x, rect.y, 1.0'f32)).xy
  var transformed = rect
  transformed.x = topLeft.x
  transformed.y = topLeft.y
  ctx.draws.add transformed

method drawFilledQuad*(
    ctx: RecordingBackend, verts: array[4, Vec2], colors: array[4, ColorRGBA]
) =
  discard colors
  let topLeft = (ctx.mat * vec3(verts[0].x, verts[0].y, 1.0'f32)).xy
  ctx.draws.add rect(topLeft.x, topLeft.y, 0.0'f32, 0.0'f32)

method translate*(ctx: RecordingBackend, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))

method rotate*(ctx: RecordingBackend, angle: float32) =
  ctx.mat = ctx.mat * rotateZ(angle)

method applyTransform*(ctx: RecordingBackend, m: Mat4) =
  ctx.mat = ctx.mat * m

method saveTransform*(ctx: RecordingBackend) =
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: RecordingBackend) =
  if ctx.mats.len > 0:
    ctx.mat = ctx.mats.pop()

method supportsAtlasUsage*(ctx: RecordingBackend): bool =
  false

method sdfAaFactor*(ctx: RecordingBackend): float32 =
  ctx.aaFactor

method setSdfAaFactor*(ctx: RecordingBackend, aaFactor: float32) =
  if ctx.aaFactor == aaFactor:
    return
  ctx.aaFactor = aaFactor
  ctx.aaChanges.add aaFactor

proc newRecordingBackend(): RecordingBackend =
  RecordingBackend(
    mat: mat4(), mats: @[], draws: @[], aaFactor: DefaultSdfAaFactor, aaChanges: @[]
  )

proc renderedDrawableDraws(
    op: DrawableOp,
    screenBox = rect(0.0'f32, 0.0'f32, 300.0'f32, 300.0'f32),
    drawSteps = 0'u16,
): seq[Rect] =
  var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

  discard renders.addRoot(
    0.ZLevel,
    Fig(
      kind: nkDrawable,
      screenBox: screenBox,
      drawStroke: RenderStroke(weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255))),
      drawSteps: drawSteps,
      drawOps: @[op],
    ),
  )

  let ctx = newRecordingBackend()
  ctx.renderRoot(renders)
  result = ctx.draws

suite "nkTransform render behavior":
  test "applies translation to child nodes":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    let rootIdx = renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkTransform,
        transform: TransformStyle(translation: vec2(5.0'f32, -4.0'f32)),
      ),
    )

    discard renders.addChild(
      0.ZLevel,
      rootIdx,
      Fig(
        kind: nkDrawable,
        screenBox: rect(0.0'f32, 0.0'f32, 1.0'f32, 1.0'f32),
        fill: fill(rgba(255, 0, 0, 255)),
        drawOps: @[drawableRect(rect(2.0'f32, 2.0'f32, 1.0'f32, 1.0'f32))],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 1
    check abs(ctx.draws[0].x - 7.0'f32) < 0.0001'f32
    check abs(ctx.draws[0].y - (-2.0'f32)) < 0.0001'f32

  test "applies translation to fragment children":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    let rootIdx = renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkTransform,
        transform: TransformStyle(translation: vec2(5.0'f32, -4.0'f32)),
      ),
    )

    var fragment = RenderList()
    discard fragment.addRoot(
      Fig(
        kind: nkDrawable,
        screenBox: rect(0.0'f32, 0.0'f32, 1.0'f32, 1.0'f32),
        fill: fill(rgba(255, 0, 0, 255)),
        drawOps: @[drawableRect(rect(2.0'f32, 2.0'f32, 1.0'f32, 1.0'f32))],
      )
    )
    discard renders.insertChildren(0.ZLevel, rootIdx, fragment, 0)

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 1
    check abs(ctx.draws[0].x - 7.0'f32) < 0.0001'f32
    check abs(ctx.draws[0].y - (-2.0'f32)) < 0.0001'f32

  test "applies matrix transform to child nodes":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    let rootIdx = renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkTransform,
        transform: TransformStyle(
          translation: vec2(10.0'f32, 20.0'f32),
          matrix: scale(vec3(2.0'f32, 3.0'f32, 1.0'f32)),
          useMatrix: true,
        ),
      ),
    )

    discard renders.addChild(
      0.ZLevel,
      rootIdx,
      Fig(
        kind: nkDrawable,
        screenBox: rect(0.0'f32, 0.0'f32, 1.0'f32, 1.0'f32),
        fill: fill(rgba(255, 0, 0, 255)),
        drawOps: @[drawableRect(rect(2.0'f32, 2.0'f32, 1.0'f32, 1.0'f32))],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 1
    check abs(ctx.draws[0].x - 14.0'f32) < 0.0001'f32
    check abs(ctx.draws[0].y - 26.0'f32) < 0.0001'f32

  test "renders quadratic bezier drawable as one sdf op":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 30.0'f32, 20.0'f32),
        drawStroke: RenderStroke(weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255))),
        drawOps:
          @[
            drawableBezier(
              [
                vec2(0.0'f32, 0.0'f32),
                vec2(10.0'f32, 20.0'f32),
                vec2(20.0'f32, 0.0'f32),
              ],
              steps = 4'u16,
            )
          ],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 1

  test "renders round capped drawable line with endpoint caps":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 30.0'f32, 20.0'f32),
        drawStroke:
          RenderStroke(weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255)), cap: scRound),
        drawOps: @[drawableLine(vec2(0.0'f32, 0.0'f32), vec2(10.0'f32, 0.0'f32))],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 3

  test "renders square capped drawable line as one extended segment":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 30.0'f32, 20.0'f32),
        drawStroke:
          RenderStroke(weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255)), cap: scSquare),
        drawOps: @[drawableLine(vec2(0.0'f32, 0.0'f32), vec2(10.0'f32, 0.0'f32))],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 1

  test "decomposes higher order bezier drawable into quadratic sdf spans":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 30.0'f32, 20.0'f32),
        drawStroke: RenderStroke(weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255))),
        drawOps:
          @[
            drawableBezier(
              [
                vec2(0.0'f32, 0.0'f32),
                vec2(10.0'f32, 20.0'f32),
                vec2(20.0'f32, -10.0'f32),
                vec2(30.0'f32, 0.0'f32),
              ],
              steps = 4'u16,
            )
          ],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 4

  test "adaptively decomposes cubic bezier drawables by screen size":
    let
      smallCurve = drawableBezier(
        [
          vec2(0.0'f32, 0.0'f32),
          vec2(4.0'f32, 20.0'f32),
          vec2(8.0'f32, -20.0'f32),
          vec2(12.0'f32, 0.0'f32),
        ]
      )
      largeCurve = drawableBezier(
        [
          vec2(0.0'f32, 0.0'f32),
          vec2(40.0'f32, 200.0'f32),
          vec2(80.0'f32, -200.0'f32),
          vec2(120.0'f32, 0.0'f32),
        ]
      )
      smallDraws = renderedDrawableDraws(smallCurve)
      largeDraws = renderedDrawableDraws(largeCurve)

    check smallDraws.len > 0
    check largeDraws.len > smallDraws.len

  test "renders arc drawable as quadratic sdf spans":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 30.0'f32, 20.0'f32),
        drawStroke: RenderStroke(weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255))),
        drawOps:
          @[
            drawableArc(
              vec2(10.0'f32, 10.0'f32), 8.0'f32, 0.0'f32, 1.5707964'f32, steps = 4'u16
            )
          ],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 4

  test "adaptively decomposes arc drawables by screen size":
    let
      smallArc = drawableArc(vec2(16.0'f32, 16.0'f32), 8.0'f32, 0.0'f32, 3.1415927'f32)
      largeArc = drawableArc(vec2(90.0'f32, 90.0'f32), 80.0'f32, 0.0'f32, 3.1415927'f32)
      smallDraws = renderedDrawableDraws(smallArc)
      largeDraws = renderedDrawableDraws(largeArc)

    check smallDraws.len > 0
    check largeDraws.len > smallDraws.len

  test "renders explicit bevel joins for decomposed arc drawable":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 30.0'f32, 20.0'f32),
        drawStroke: RenderStroke(
          weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255)), cap: scButt, join: sjBevel
        ),
        drawOps:
          @[
            drawableArc(
              vec2(10.0'f32, 10.0'f32), 8.0'f32, 0.0'f32, 1.5707964'f32, steps = 4'u16
            )
          ],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 7

  test "drawable node steps are defaults for curve ops":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 40.0'f32, 30.0'f32),
        drawStroke: RenderStroke(weight: 2.0'f32, fill: fill(rgba(255, 0, 0, 255))),
        drawSteps: 4'u16,
        drawOps:
          @[
            drawableBezier(
              [
                vec2(0.0'f32, 0.0'f32),
                vec2(10.0'f32, 20.0'f32),
                vec2(20.0'f32, 0.0'f32),
              ]
            ),
            drawableArc(
              vec2(20.0'f32, 10.0'f32), 8.0'f32, 0.0'f32, 1.5707964'f32, steps = 2'u16
            ),
          ],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 3

  test "keeps quadratic sdf antialias padding in physical pixels":
    let oldScale = figUiScale()
    setFigUiScale(2.0'f32)
    try:
      let draws = renderedDrawableDraws(
        drawableBezier(
          vec2(0.0'f32, 0.0'f32), vec2(10.0'f32, 10.0'f32), vec2(20.0'f32, 0.0'f32)
        )
      )

      check draws.len == 1
      check abs(draws[0].w - 48.0'f32) < 0.0001'f32
      check abs(draws[0].h - 18.0'f32) < 0.0001'f32
    finally:
      setFigUiScale(oldScale)

  test "drawable aa overrides backend sdf aa and restores it":
    var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkDrawable,
        screenBox: rect(5.0'f32, 7.0'f32, 40.0'f32, 30.0'f32),
        fill: fill(rgba(255, 0, 0, 255)),
        drawAa: 0.75'f32,
        drawOps: @[drawableRect(rect(2.0'f32, 3.0'f32, 10.0'f32, 8.0'f32))],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 1
    check ctx.aaChanges.len == 2
    check abs(ctx.aaChanges[0] - 0.75'f32) < 0.0001'f32
    check abs(ctx.aaChanges[1] - DefaultSdfAaFactor) < 0.0001'f32
    check abs(ctx.aaFactor - DefaultSdfAaFactor) < 0.0001'f32
