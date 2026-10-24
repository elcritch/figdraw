import std/unittest

when defined(features.figdraw.uirelays):
  import pkg/[chroma, pixie, vmath]
  import pkg/sdfy/spans
  import figdraw/[figbackend, fignodes]
  import figdraw/software/[context, raster, distances]

  proc scene(ctx: SoftwareContext, width, height: int) =
    ctx.beginFrame(vec2(width.float32, height.float32), true, color(0.1, 0.2, 0.3, 0.6))
    let radii = CornerRadii2D[float32](x: [19'f32, 5, 30, 0], y: [7'f32, 13, 30, 4])
    ctx.beginMask(rect(1.25, 2.5, (width - 3).float32, (height - 5).float32), radii)
    ctx.endMask()
    ctx.saveTransform()
    ctx.translate(vec2(12.5, 9.25))
    ctx.rotate(0.12'f32)
    ctx.scale(vec2(0.95, 1.05))
    ctx.beginMask(rect(0, 0, (width - 8).float32, (height - 4).float32), radii)
    ctx.endMask()
    for mode in [
      sdfModeClipAA, sdfModeAnnularAA, sdfModeDropShadowAA, sdfModeInsetShadow,
      sdfModeInsetShadowAnnular,
    ]:
      let paint = BackendFill(
        kind: bfLinear3,
        lin3Start: rgba(200, 20, 80, 170),
        lin3Mid: rgba(40, 220, 70, 130),
        lin3Stop: rgba(20, 60, 240, 190),
        lin3MidPos: 0.4,
        lin3Axis: fgaDiagBLTR,
      )
      ctx.drawRoundedRectSdf(
        rect(-3.25, 0.75, (width - 1).float32, (height - 1).float32),
        paint,
        radii,
        mode,
        5,
        1,
        vec2(2, -3),
      )
    ctx.popMask()
    ctx.restoreTransform()
    ctx.popMask()
    ctx.drawRoundedRectSdf(
      rect(0, 0, 5, 1),
      color(1, 0, 0, 0.5),
      [0'f32, 0, 0, 0],
      sdfModeClipAA,
      0,
      0,
      vec2(0),
    )
    ctx.endFrame()

  suite "software Sigils workers":
    test "pooled and inline draws match exactly through masks transforms and resize":
      block:
        let inline = newSoftwareContext(workers = 1)
        let pooled = newSoftwareContext(workers = 4, parallelThreshold = 1)
        for frame in 0 ..< 24:
          let width = if frame mod 2 == 0: 131 else: 73
          let height = if frame mod 2 == 0: 97 else: 51
          inline.scene(width, height)
          pooled.scene(width, height)
          check inline.readPixels(rect(0, 0, 0, 0), false).data ==
            pooled.readPixels(rect(0, 0, 0, 0), false).data

    test "worker errors are reported after the barrier and the pool remains usable":
      block:
        let workers = initRasterWorkers(2, 1)
        let image = newImage(17, 13)
        var raster = SdfyRaster(
          field: initRoundedBoxField(vec2(100), vec4(0)),
          paint: initSolidPaint(rgba(210, 30, 80, 150)),
          effect: initSpanEffect(),
          transform: default(Mat3),
          useSimd: softwareSimdEnabled,
        )
        expect ValueError:
          workers.renderSdfy(raster, image, nil, 0, 0, 17, 13)
        check image.data == newImage(17, 13).data
        raster.transform = mat3()
        workers.renderSdfy(raster, image, nil, 0, 0, 17, 13)
        for pixel in image.data:
          check pixel == rgba(210, 30, 80, 150).rgbx()

    test "automatic workers preserve synchronous owning-thread presentation":
      let owner = getThreadId()
      var presented = false
      let ctx = newSoftwareContext(
        parallelThreshold = 1,
        presenter = proc(image: Image) =
          check getThreadId() == owner
          check image[9, 5].r == 255
          presented = true,
      )
      ctx.beginFrame(vec2(19, 11), true, color(0, 0, 0, 0))
      ctx.drawRoundedRectSdf(
        rect(0, 0, 19, 11),
        color(1, 0, 0, 1),
        [3'f32, 3, 3, 3],
        sdfModeClipAA,
        0,
        0,
        vec2(0),
      )
      ctx.endFrame()
      check presented
else:
  suite "software Sigils workers":
    test "requires Atlas uirelays feature":
      skip()
