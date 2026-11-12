import std/unittest
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
