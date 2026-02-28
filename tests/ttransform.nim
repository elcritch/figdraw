import std/[tables, unittest]

import figdraw/figrender
import figdraw/fignodes

type RecordingBackend = ref object of BackendContext
  mat: Mat4
  mats: seq[Mat4]
  draws: seq[Rect]

method drawRect*(ctx: RecordingBackend, rect: Rect, color: Color) =
  discard color
  let topLeft = (ctx.mat * vec3(rect.x, rect.y, 1.0'f32)).xy
  var transformed = rect
  transformed.x = topLeft.x
  transformed.y = topLeft.y
  ctx.draws.add transformed

method translate*(ctx: RecordingBackend, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))

method applyTransform*(ctx: RecordingBackend, m: Mat4) =
  ctx.mat = ctx.mat * m

method saveTransform*(ctx: RecordingBackend) =
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: RecordingBackend) =
  if ctx.mats.len > 0:
    ctx.mat = ctx.mats.pop()

proc newRecordingBackend(): RecordingBackend =
  RecordingBackend(mat: mat4(), mats: @[], draws: @[])

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
        points: @[vec2(2.0'f32, 2.0'f32)],
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
        points: @[vec2(2.0'f32, 2.0'f32)],
      ),
    )

    let ctx = newRecordingBackend()
    ctx.renderRoot(renders)

    check ctx.draws.len == 1
    check abs(ctx.draws[0].x - 14.0'f32) < 0.0001'f32
    check abs(ctx.draws[0].y - 26.0'f32) < 0.0001'f32
