import std/unittest
import figdraw/figbackend
import figdraw/fignodes

suite "SDF band factor packing":
  test "annular modes pack half of the full stroke width":
    for mode in [sdfModeAnnular, sdfModeAnnularAA, sdfModeCenteredAnnularAA]:
      check sdfFactor(mode, 8'f32) == 4'f32
      check sdfFactor(mode, 0'f32) == 0'f32
      check sdfFactor(mode, -2'f32) == 0'f32

  test "other modes retain their factors":
    check sdfFactor(sdfModeClipAA, 8'f32) == 8'f32
    check sdfFactor(sdfModeDropShadowAA, -2'f32) == -2'f32

import pkg/pixie
import figdraw/software/context

suite "Centered band software defaults":
  test "omitted shape size uses the drawing rectangle":
    let ctx = newSoftwareContext(workers = 1)
    ctx.beginFrame(vec2(32), true, color(0, 0, 0, 0))
    ctx.drawRoundedRectSdf(
      rect(0, 0, 32, 32),
      BackendFill(kind: bfColor, color: rgba(255, 0, 0, 255)),
      CornerRadii2D[float32](x: [16'f32, 16, 16, 16], y: [16'f32, 16, 16, 16]),
      sdfModeCenteredAnnularAA,
      8,
      0,
      vec2(0),
    )
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[2, 16].a > 220
    check image[6, 16].a == 0
    check image[16, 16].a == 0
