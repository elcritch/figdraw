import std/[math, unittest]
import pkg/pixie
import figdraw/svgs/svgfields

suite "SVG distance fields":
  test "stroke reserves distance range and frame padding":
    let path = parsePath("M48 32 A16 12 0 1 1 16 32 A16 12 0 1 1 48 32 Z")
    let thin = generateSvgField(path, NonZero, 1.0, 6.0)
    let thick = generateSvgField(path, NonZero, 1.0, 6.0, 16.0)
    check thick.pixelRange > thin.pixelRange + 15
    check thick.frame.x < 8
    check thick.frame.y < 12
    check thick.frame.x + thick.frame.w > 56
    check thick.frame.y + thick.frame.h > 52
    check thick.image.width > thin.image.width
    check thick.image.height > thin.image.height
    let x = int((32 - thick.frame.x) * thick.image.width.float32 / thick.frame.w)
    let y = int((32 - thick.frame.y) * thick.image.height.float32 / thick.frame.h)
    check thick.image[x, y].a > 128

import figdraw/svgs/svg
import figdraw/figrender
import figdraw/software/context

suite "SVG ellipse stroke rendering":
  test "thick and thin strokes retain their shape at different sizes":
    for width in [2, 16]:
      let data =
        """<svg viewBox="0 0 64 64"><ellipse cx="32" cy="32" rx="16" ry="12" fill="none" stroke="red" stroke-width='""" &
        $width & "'/></svg>"
      let svg = newSvgMtsdfResource(data, longEdge = 64)
      for size in [64, 128]:
        var list: RenderList
        discard list.addSvgMtsdf(rect(0, 0, size.float32, size.float32), svg)
        var scene = newRenders()
        scene.setLayer(0.ZLevel, list)
        let ctx = newSoftwareContext(workers = 1)
        let renderer = newFigRenderer(ctx)
        renderer.renderFrame(scene, vec2(size.float32), clearColor = color(0, 0, 0, 0))
        let image = ctx.readPixels(rect(0, 0, 0, 0), false)
        let factor = size div 64

        check image[32 * factor, 32 * factor].a == 0
        check image[48 * factor, 32 * factor].a > 200
        check image[5 * factor, 32 * factor].a == 0
        if width == 16:
          check image[53 * factor, 32 * factor].a > 200
          check image[42 * factor, 32 * factor].a > 200

suite "SVG adaptive field resolution":
  test "narrow diagonal fills reconstruct more accurately without enlarging broad fills":
    let path = parsePath("M4 8 L60 52 L60 53 L4 9 Z")
    let fixed = generateSvgField(path, NonZero, 0.25, 6, adaptive = false)
    let adaptive = generateSvgField(path, NonZero, 0.25, 6)
    let reference = newImage(64, 64)
    reference.fillPath(path, color(1, 1, 1, 1))
    proc error(field: SvgField): float64 =
      let factor = field.image.width.float32 / field.frame.w
      for y in 0 ..< 64:
        for x in 0 ..< 64:
          let p =
            (vec2(x.float32 + 0.5, y.float32 + 0.5) - field.frame.xy) * factor -
            vec2(0.5)
          let ix = floor(p.x).int
          let iy = floor(p.y).int
          var alpha = 0'f32
          if ix >= 0 and iy >= 0 and ix + 1 < field.image.width and
              iy + 1 < field.image.height:
            let f = p - vec2(ix.float32, iy.float32)
            let a =
              field.image[ix, iy].a.float32 * (1 - f.x) +
              field.image[ix + 1, iy].a.float32 * f.x
            let b =
              field.image[ix, iy + 1].a.float32 * (1 - f.x) +
              field.image[ix + 1, iy + 1].a.float32 * f.x
            alpha = clamp(
              ((a * (1 - f.y) + b * f.y) / 255 - 0.5) * field.pixelRange / factor + 0.5,
              0,
              1,
            )
          result += abs(alpha.float64 - reference[x, y].a.float64 / 255)

    check error(adaptive) < error(fixed) * 0.8
    let broad = parsePath("M4 4 H60 V60 H4 Z")
    let broadFixed = generateSvgField(broad, NonZero, 1, 6, adaptive = false)
    let broadAdaptive = generateSvgField(broad, NonZero, 1, 6)
    check broadFixed.image.data == broadAdaptive.image.data
