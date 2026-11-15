import std/unittest
import figdraw/commons
import figdraw/fignodes
import figdraw/figrender
import figdraw/utils/drawprimitives

type
  StrokeCall = object
    bounds: Rect
    shapeSize: Vec2
    mode: SdfMode
    width, spread: float32
    fillKind: BackendFillKind

  RecordingBackend = ref object of BackendContext
    calls: seq[StrokeCall]

method supportsAtlasUsage*(ctx: RecordingBackend): bool =
  false

method drawRoundedRectSdf*(
    ctx: RecordingBackend,
    rect: Rect,
    fill: BackendFill,
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor, spread: float32,
    shapeSize: Vec2,
) =
  if mode != sdfModeClipAA:
    ctx.calls.add StrokeCall(
      bounds: rect,
      shapeSize: shapeSize,
      mode: mode,
      width: factor,
      spread: spread,
      fillKind: fill.kind,
    )

suite "Prepared stroke backend parameters":
  test "centered ellipse selects its mode without inflating the shape":
    let ctx = RecordingBackend()
    let stroke = RenderStroke(weight: 8, fill: fill(rgba(10, 20, 30, 255)))
    var scene = newRenders()
    scene.addRoot(
      0.ZLevel, figEllipse(rect(10, 20, 40, 24), fill(rgba(0, 0, 0, 0)), stroke)
    )
    ctx.renderRoot(scene)
    check ctx.calls.len == 1
    let call = ctx.calls[0]
    check call.mode == sdfModeCenteredAnnularAA
    check call.bounds == rect(6, 16, 48, 32)
    check call.shapeSize == vec2(40, 24)
    check call.width == 8
    check call.spread == 0

  test "three stop stroke paints retain their gradient contract":
    let ctx = RecordingBackend()
    let stroke = RenderStroke(
      weight: 6,
      fill:
        linear(rgba(255, 0, 0, 255), rgba(0, 255, 0, 255), rgba(0, 0, 255, 255), fgaX),
    )
    var scene = newRenders()
    scene.addRoot(
      0.ZLevel, figCircle(rect(20, 20, 40, 40), fill(rgba(0, 0, 0, 0)), stroke)
    )
    ctx.renderRoot(scene)
    check ctx.calls.len == 1
    check ctx.calls[0].mode == sdfModeCenteredAnnularAA
    check ctx.calls[0].fillKind == bfLinear3
    check ctx.calls[0].bounds == rect(17, 17, 46, 46)
