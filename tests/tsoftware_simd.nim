import std/[math, random, unittest]

when defined(features.figdraw.uirelays):
  import pkg/[chroma, pixie, vmath]
  import pkg/sdfy/shapes
  import figdraw/[figbackend, fignodes]
  import figdraw/software/[context, distances]

  proc vector(values: array[DirectionCorners, float32]): Vec4 =
    vec4(
      values[dcBottomRight], values[dcTopRight], values[dcBottomLeft], values[dcTopLeft]
    )

  proc referenceAlpha(
      p, halfSize: Vec2,
      radii: CornerRadii2D[float32],
      aa: float32,
      mode: SdfMode,
      factor, spread: float32,
      offset: Vec2,
  ): float32 =
    let d = sdEllipticalRoundedBox(p, halfSize, vector(radii.x), vector(radii.y))
    result = clamp(0.5'f32 - d / aa, 0'f32, 1'f32)
    case mode
    of sdfModeAnnular, sdfModeAnnularAA:
      let band = abs(d + factor * 0.5'f32) - factor * 0.5'f32
      result =
        if mode == sdfModeAnnular:
          float32(band < 0)
        else:
          clamp(0.5'f32 - band / aa, 0'f32, 1'f32)
    of sdfModeDropShadow, sdfModeDropShadowAA:
      let sigma = max(factor * 0.5'f32, 0.5'f32)
      let outside = max(0'f32, d - spread)
      result = exp(-0.5'f32 * outside * outside / (sigma * sigma))
    of sdfModeInsetShadow, sdfModeInsetShadowAnnular:
      let inner =
        sdEllipticalRoundedBox(p - offset, halfSize, vector(radii.x), vector(radii.y)) +
        spread
      let sigma = max(factor * 0.5'f32, 0.5'f32)
      if inner < 0:
        result *= exp(-0.5'f32 * inner * inner / (sigma * sigma))
    else:
      discard

  suite "software SIMD":
    test "prepared fields and packets preserve sdfy radius semantics":
      var rng = initRand(78254)
      for trial in 0 ..< 1000:
        let bounds = vec2(rand(rng, 40.0).float32 - 2, rand(rng, 30.0).float32 - 2)
        var rx, ry: Vec4
        var points: array[4, Vec2]
        for lane in 0 ..< 4:
          rx[lane] = rand(rng, 60.0).float32 - 5
          ry[lane] =
            if trial mod 2 == 0:
              rx[lane]
            else:
              rand(rng, 60.0).float32 - 5
          points[lane] =
            vec2(rand(rng, 100.0).float32 - 50, rand(rng, 80.0).float32 - 40)
        let field = roundedBoxField(bounds, rx, ry)
        let packet = field.distances(points)
        for lane in 0 ..< 4:
          let expected = sdEllipticalRoundedBox(points[lane], bounds, rx, ry)
          check abs(field.distance(points[lane]) - expected) <=
            0.00002'f32 + abs(expected) * 0.000002'f32
          check abs(packet[lane] - expected) <=
            0.00002'f32 + abs(expected) * 0.000002'f32

    test "all rounded effects match scalar reference under affine transforms":
      let
        ctx = newSoftwareContext()
        box = rect(-7.25, -11.25, 38.5, 31.5)
        offset = vec2(2, -3)
        factor = 5'f32
        spread = 1.25'f32
      for radii in [
        CornerRadii2D[float32](x: [9'f32, 5, 12, 3], y: [9'f32, 5, 12, 3]),
        CornerRadii2D[float32](x: [13'f32, 0, 40, 6], y: [4'f32, 7, 40, 11]),
      ]:
        for transform in 0 ..< 3:
          var mat = translate(vec2(24.5, 22.5))
          if transform == 1:
            mat = mat * rotate(0.31'f32) * scale(vec2(1.2, 0.85))
          elif transform == 2:
            mat = mat * scale(vec2(-1.15, 1.1))
          let inverse = mat.inverse()
          let aa =
            max(
              length(inverse * vec2(1, 0) - inverse * vec2(0)),
              length(inverse * vec2(0, 1) - inverse * vec2(0)),
            ) / DefaultSdfAaFactor
          for mode in [
            sdfModeClipAA, sdfModeAnnular, sdfModeAnnularAA, sdfModeDropShadow,
            sdfModeDropShadowAA, sdfModeInsetShadow, sdfModeInsetShadowAnnular,
          ]:
            ctx.beginFrame(vec2(67, 61), true, color(0, 0, 0, 0))
            ctx.translate(vec2(24.5, 22.5))
            if transform == 1:
              ctx.rotate(0.31'f32)
              ctx.scale(vec2(1.2, 0.85))
            elif transform == 2:
              ctx.scale(vec2(-1.15, 1.1))
            # Cycle through every gradient axis and both stop counts.
            let axis = FillGradientAxis((transform * 7 + mode.ord) mod 4)
            let paint =
              if mode.ord mod 2 == 0:
                BackendFill(
                  kind: bfLinear2,
                  lin2Start: rgba(200, 50, 20, 180),
                  lin2Stop: rgba(10, 100, 220, 110),
                  lin2Axis: axis,
                )
              else:
                BackendFill(
                  kind: bfLinear3,
                  lin3Start: rgba(200, 50, 20, 180),
                  lin3Mid: rgba(70, 200, 30, 140),
                  lin3Stop: rgba(10, 100, 220, 110),
                  lin3MidPos: 0.37,
                  lin3Axis: axis,
                )
            ctx.drawRoundedRectSdf(box, paint, radii, mode, factor, spread, offset)
            let image = ctx.readPixels(rect(0, 0, 0, 0), false)
            var maxDelta = 0
            for y in 0 ..< image.height:
              for x in 0 ..< image.width:
                let p = inverse * vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
                var expected: ColorRGBX
                if p.x >= box.x and p.y >= box.y and p.x < box.x + box.w and
                    p.y < box.y + box.h:
                  # offset has a negative y, so shadow modes retain box half-extents.
                  let alpha = referenceAlpha(
                    p - box.xy - box.wh * 0.5'f32,
                    box.wh * 0.5'f32,
                    radii,
                    aa,
                    mode,
                    factor,
                    spread,
                    offset,
                  )
                  let uv = (p - box.xy) / box.wh
                  let t =
                    case axis
                    of fgaX:
                      uv.x
                    of fgaY:
                      uv.y
                    of fgaDiagTLBR:
                      (uv.x + uv.y) * 0.5'f32
                    of fgaDiagBLTR:
                      (uv.x + 1'f32 - uv.y) * 0.5'f32
                  var color = paint.sampleColor(t)
                  color.a = round(color.a.float32 * alpha).uint8
                  expected = color.rgbx()
                let actual = image[x, y]
                for delta in [
                  abs(actual.r.int - expected.r.int),
                  abs(actual.g.int - expected.g.int),
                  abs(actual.b.int - expected.b.int),
                  abs(actual.a.int - expected.a.int),
                ]:
                  maxDelta = max(maxDelta, delta)
            check maxDelta <= 1

    test "four-corner paint retains backend corner order and alpha":
      let ctx = newSoftwareContext()
      let bounds = rect(3.25, 5.5, 59.5, 43.25)
      let colors = [
        rgba(210, 40, 70, 190),
        rgba(20, 200, 150, 110),
        rgba(40, 70, 230, 225),
        rgba(180, 140, 30, 170),
      ]
      proc mix(a, b: ColorRGBA, t: float32): ColorRGBA =
        rgba(
          round(a.r.float32 * (1 - t) + b.r.float32 * t).uint8,
          round(a.g.float32 * (1 - t) + b.g.float32 * t).uint8,
          round(a.b.float32 * (1 - t) + b.b.float32 * t).uint8,
          round(a.a.float32 * (1 - t) + b.a.float32 * t).uint8,
        )

      ctx.beginFrame(vec2(69, 57), true, color(0, 0, 0, 0))
      ctx.drawRoundedRectSdf(
        bounds, colors, [0'f32, 0, 0, 0], sdfModeClipAA, 0, 0, vec2(0)
      )
      let image = ctx.readPixels(rect(0, 0, 0, 0), false)
      var maxDelta = 0
      for y in 0 ..< image.height:
        for x in 0 ..< image.width:
          let p = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
          if p.x >= bounds.x and p.y >= bounds.y and p.x < bounds.x + bounds.w and
              p.y < bounds.y + bounds.h:
            let uv = (p - bounds.xy) / bounds.wh
            var expected = mix(
              mix(colors[3], colors[2], uv.x), mix(colors[0], colors[1], uv.x), uv.y
            )
            let alpha = referenceAlpha(
              p - bounds.xy - bounds.wh * 0.5'f32,
              bounds.wh * 0.5'f32,
              default(CornerRadii2D[float32]),
              1'f32 / DefaultSdfAaFactor,
              sdfModeClipAA,
              0,
              0,
              vec2(0),
            )
            expected.a = round(expected.a.float32 * alpha).uint8
            let pixel = expected.rgbx()
            let actual = image[x, y]
            for delta in [
              abs(pixel.r.int - actual.r.int),
              abs(pixel.g.int - actual.g.int),
              abs(pixel.b.int - actual.b.int),
              abs(pixel.a.int - actual.a.int),
            ]:
              maxDelta = max(maxDelta, delta)
      check maxDelta <= 1

    test "nested transformed masks preserve partial packets and premultiplied alpha":
      let
        ctx = newSoftwareContext(pixelScale = 2)
        outer = rect(1.25, 0.75, 27.5, 25.5)
        inner = rect(-10.5, -8.25, 21.25, 17.5)
        radii = CornerRadii2D[float32](x: [9'f32, 4, 7, 2], y: [3'f32, 8, 4, 6])
        mat = scale(vec2(2)) * translate(vec2(15, 14)) * rotate(0.27'f32)
        inverse = mat.inverse()
        color = rgba(210, 60, 130, 170)
      ctx.beginFrame(vec2(33, 29), true, chroma.color(0, 0, 0, 0))
      ctx.scale(2)
      ctx.beginMask(outer, radii)
      ctx.endMask()
      ctx.translate(vec2(15, 14))
      ctx.rotate(0.27'f32)
      ctx.beginMask(inner, radii)
      ctx.endMask()
      ctx.drawRect(rect(-100, -100, 200, 200), color.color())
      ctx.popMask()
      ctx.popMask()
      let image = ctx.readPixels(rect(0, 0, 0, 0), false)
      var maxDelta = 0
      for y in 0 ..< image.height:
        for x in 0 ..< image.width:
          let screen = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
          var mask = 255
          for shape in [(outer, screen / 2'f32), (inner, inverse * screen)]:
            let (bounds, p) = shape
            var alpha = 0
            if p.x >= bounds.x and p.y >= bounds.y and p.x < bounds.x + bounds.w and
                p.y < bounds.y + bounds.h:
              alpha = round(
                255'f32 *
                  referenceAlpha(
                    p - bounds.xy - bounds.wh * 0.5'f32,
                    bounds.wh * 0.5'f32,
                    radii,
                    0.5'f32 / DefaultSdfAaFactor,
                    sdfModeClipAA,
                    0,
                    0,
                    vec2(0),
                  )
              ).int
            mask = (alpha * mask + 127) div 255
          let source = color.rgbx()
          let actual = image[x, y]
          for delta in [
            abs(actual.r.int - (source.r.int * mask + 127) div 255),
            abs(actual.g.int - (source.g.int * mask + 127) div 255),
            abs(actual.b.int - (source.b.int * mask + 127) div 255),
            abs(actual.a.int - (source.a.int * mask + 127) div 255),
          ]:
            maxDelta = max(maxDelta, delta)
      check maxDelta <= 1
else:
  suite "software SIMD":
    test "requires Atlas uirelays feature":
      skip()
