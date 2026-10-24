## nim r -d:release tests/bench_software_simd.nim
## nim r -d:release -d:figdraw.sdfySimd=off tests/bench_software_simd.nim
import std/[monotimes, strformat, times]
import pkg/chroma
import figdraw/[figbackend, fignodes]
import figdraw/software/[context, distances]

const Frames = 30

echo "Software SIMD enabled: ", softwareSimdEnabled
for scenario in [
  "circular fill", "elliptical fill", "elliptical stroke", "masked shadow"
]:
  let
    ctx = newSoftwareContext()
    circular = CornerRadii2D[float32](x: [24'f32, 12, 32, 8], y: [24'f32, 12, 32, 8])
    elliptical = CornerRadii2D[float32](x: [28'f32, 14, 32, 8], y: [12'f32, 22, 10, 16])
    radii = if scenario == "circular fill": circular else: elliptical
    mode =
      if scenario == "elliptical stroke":
        sdfModeAnnularAA
      elif scenario == "masked shadow":
        sdfModeDropShadowAA
      else:
        sdfModeClipAA
  var best = high(float64)
  var checksum: uint64
  for trial in 0 ..< 5:
    let start = getMonoTime()
    for frame in 0 ..< Frames:
      ctx.beginFrame(vec2(257, 193), true, color(0, 0, 0, 0))
      if scenario == "masked shadow":
        ctx.beginMask(rect(1, 2, 249, 183), elliptical)
        ctx.endMask()
      ctx.drawRoundedRectSdf(
        rect(10, 8, 237, 175),
        color(0.8, 0.3, 0.1, 0.7),
        radii,
        mode,
        6,
        1,
        (if scenario == "masked shadow": vec2(200, 140)
        else: vec2(0)),
      )
      if scenario == "masked shadow":
        ctx.popMask()
      ctx.endFrame()
    best = min(best, (getMonoTime() - start).inNanoseconds.float64 / 1e6)
    checksum = 0
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    for pixel in image.data:
      checksum += pixel.r.uint64 + pixel.g.uint64 + pixel.b.uint64 + pixel.a.uint64
  echo &"{scenario}: {best:.2f} ms / {Frames} frames, checksum {checksum}"
