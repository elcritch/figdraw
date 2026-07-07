import std/[tables, unittest]

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

  test "renders bezier drawable as line segments with caps":
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

    check ctx.draws.len == 9

  test "renders arc drawable as line segments with caps":
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

    check ctx.draws.len == 9

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

    check ctx.draws.len == 14

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
