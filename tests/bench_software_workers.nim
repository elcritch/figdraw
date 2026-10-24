## nim r -d:release tests/bench_software_workers.nim
## nim r -d:release -d:figdraw.sdfySimd=off tests/bench_software_workers.nim
## Minimum of five alternating-order samples; each sample renders eight frames.
import std/[monotimes, strformat, times]
import pkg/chroma
import figdraw/[figbackend, fignodes]
import figdraw/software/[context, distances]

const Frames = 8

proc drawScene(ctx: SoftwareContext, scenario: string) =
  let
    radii = CornerRadii2D[float32](x: [28'f32, 14, 32, 8], y: [12'f32, 22, 10, 16])
    paint = BackendFill(
      kind: bfLinear3,
      lin3Start: rgba(210, 30, 70, 190),
      lin3Mid: rgba(60, 220, 90, 130),
      lin3Stop: rgba(30, 60, 230, 210),
      lin3MidPos: 0.4,
      lin3Axis: fgaDiagTLBR,
    )
  if scenario == "small draws":
    ctx.beginFrame(vec2(1024, 768), true, color(0.1, 0.2, 0.3, 0.6))
    for y in 0 ..< 16:
      for x in 0 ..< 16:
        ctx.drawRoundedRectSdf(
          rect((x * 64 + 3).float32, (y * 48 + 2).float32, 55, 39),
          paint,
          radii,
          sdfModeClipAA,
          0,
          0,
          vec2(0),
        )
  else:
    ctx.beginFrame(vec2(1920, 1080), true, color(0.1, 0.2, 0.3, 0.6))
    if scenario == "masked shadow":
      ctx.beginMask(rect(3, 2, 1911, 1073), radii)
      ctx.endMask()
    ctx.drawRoundedRectSdf(
      rect(7, 5, 1903, 1061),
      paint,
      radii,
      (if scenario == "masked shadow": sdfModeDropShadowAA else: sdfModeClipAA),
      12,
      1,
      (if scenario == "masked shadow": vec2(1800, 960)
      else: vec2(0)),
    )
    if scenario == "masked shadow":
      ctx.popMask()
  ctx.endFrame()

echo "SIMD: ", softwareSimdEnabled, ", threaded sdfy: ", ThreadedSdfyEnabled
let inline = newSoftwareContext(workers = 1)
let pooled = newSoftwareContext(workers = 4)
for scenario in ["large gradient", "masked shadow", "small draws"]:
  var best = [high(float64), high(float64)]
  var checksums: array[2, uint64]
  for trial in 0 ..< 5:
    for step in 0 ..< 2:
      let mode =
        if trial mod 2 == 0:
          step
        else:
          1 - step
      let ctx = if mode == 0: inline else: pooled
      # Initialize buffers, actors, and worker mailboxes before measurement.
      ctx.drawScene(scenario)
      let start = getMonoTime()
      for frame in 0 ..< Frames:
        ctx.drawScene(scenario)
      best[mode] = min(best[mode], (getMonoTime() - start).inNanoseconds.float64 / 1e6)
      checksums[mode] = 0
      for pixel in ctx.readPixels(rect(0, 0, 0, 0), false).data:
        checksums[mode] +=
          pixel.r.uint64 + pixel.g.uint64 + pixel.b.uint64 + pixel.a.uint64
  doAssert checksums[0] == checksums[1]
  echo &"{scenario}: inline {best[0]:.2f} ms, pool4 {best[1]:.2f} ms, {best[0]/best[1]:.2f}x, checksum {checksums[0]}"
