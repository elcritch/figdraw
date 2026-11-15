import std/[importutils, unittest]
import figdraw/commons

when UseMetalBackend:
  import pkg/pixie
  import figdraw/[figbasics, metal/metal_context]
  import metalx/[metal, objc_owned]

  privateAccess MetalContext

  template checkPixel(image: untyped, x, y, red, green, blue, alpha: int) =
    block:
      let pixel = image[x, y]
      check abs(pixel.r.int - red) <= 2
      check abs(pixel.g.int - green) <= 2
      check abs(pixel.b.int - blue) <= 2
      check abs(pixel.a.int - alpha) <= 2

  suite "Metal opacity groups":
    test "overlapping children receive opacity once and nested groups multiply":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        skip()
      else:
        let ctx = newContext(atlasSize = 32, maxQuads = 8)
        ctx.beginFrame(
          vec2(32, 32), clearMain = true, clearMainColor = color(0, 0, 0, 0)
        )
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 0, 20, 20), color(1, 0, 0, 1))
        ctx.drawRect(rect(10, 0, 20, 20), color(0, 1, 0, 1))
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 20, 16, 12), color(0, 0, 1, 1))
        ctx.endOpacityGroup()
        ctx.endOpacityGroup()
        ctx.endFrame()
        let image = ctx.readPixels()
        image.checkPixel(4, 4, 128, 0, 0, 128)
        image.checkPixel(14, 4, 0, 128, 0, 128)
        image.checkPixel(24, 4, 0, 128, 0, 128)
        image.checkPixel(4, 25, 0, 0, 64, 64)

    test "clip applies within groups and is restored for later siblings":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        skip()
      else:
        let ctx = newContext(atlasSize = 32, maxQuads = 8)
        ctx.beginFrame(
          vec2(32, 32), clearMain = true, clearMainColor = color(0, 0, 0, 0)
        )
        ctx.beginRectMask(rect(0, 0, 16, 32), default(CornerRadii2D[float32]))
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 0, 32, 16), color(1, 0, 0, 1))
        ctx.endOpacityGroup()
        ctx.drawRect(rect(0, 16, 32, 8), color(0, 1, 0, 1))
        ctx.popRectMask()
        ctx.drawRect(rect(16, 24, 16, 8), color(0, 0, 1, 1))
        ctx.endFrame()
        let image = ctx.readPixels()
        image.checkPixel(4, 4, 128, 0, 0, 128)
        image.checkPixel(24, 4, 0, 0, 0, 0)
        image.checkPixel(4, 20, 0, 255, 0, 255)
        image.checkPixel(24, 20, 0, 0, 0, 0)
        image.checkPixel(24, 28, 0, 0, 255, 255)
    test "fractional mask coverage is applied only once":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        skip()
      else:
        let ctx = newContext(atlasSize = 32, maxQuads = 8)
        ctx.beginFrame(
          vec2(32, 32), clearMain = true, clearMainColor = color(0, 0, 0, 0)
        )
        ctx.beginMask(
          rect(4.3, 4.3, 16, 16),
          CornerRadii2D[float32](x: [6'f32, 6, 6, 6], y: [6'f32, 6, 6, 6]),
        )
        ctx.endMask()
        ctx.drawRect(rect(0, 0, 32, 32), color(1, 0, 0, 1))
        ctx.popMask()
        ctx.endFrame()
        let reference = ctx.readPixels()

        ctx.beginFrame(
          vec2(32, 32), clearMain = true, clearMainColor = color(0, 0, 0, 0)
        )
        ctx.beginMask(
          rect(4.3, 4.3, 16, 16),
          CornerRadii2D[float32](x: [6'f32, 6, 6, 6], y: [6'f32, 6, 6, 6]),
        )
        ctx.endMask()
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 0, 32, 32), color(1, 0, 0, 1))
        ctx.drawRect(rect(0, 0, 32, 32), color(1, 0, 0, 1))
        ctx.endOpacityGroup()
        ctx.popMask()
        ctx.endFrame()
        let grouped = ctx.readPixels()
        var fractionalPixels = 0
        for y in 0 ..< 32:
          for x in 0 ..< 32:
            let alpha = reference[x, y].a.int
            if alpha > 20 and alpha < 235:
              inc fractionalPixels
              check abs(grouped[x, y].a.int * 2 - alpha) <= 5
        check fractionalPixels > 0

    test "fractional fast rect coverage is applied only once":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        skip()
      else:
        let ctx = newContext(atlasSize = 32, maxQuads = 8)
        ctx.beginFrame(
          vec2(32, 32), clearMain = true, clearMainColor = color(0, 0, 0, 0)
        )
        ctx.beginRectMask(
          rect(4.3, 4.3, 16, 16),
          CornerRadii2D[float32](x: [6'f32, 6, 6, 6], y: [6'f32, 6, 6, 6]),
        )
        ctx.drawRect(rect(0, 0, 32, 32), color(1, 0, 0, 1))
        ctx.popRectMask()
        ctx.endFrame()
        let reference = ctx.readPixels()

        ctx.beginFrame(
          vec2(32, 32), clearMain = true, clearMainColor = color(0, 0, 0, 0)
        )
        ctx.beginRectMask(
          rect(4.3, 4.3, 16, 16),
          CornerRadii2D[float32](x: [6'f32, 6, 6, 6], y: [6'f32, 6, 6, 6]),
        )
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 0, 32, 32), color(1, 0, 0, 1))
        ctx.drawRect(rect(0, 0, 32, 32), color(1, 0, 0, 1))
        ctx.endOpacityGroup()
        ctx.popRectMask()
        ctx.endFrame()
        let grouped = ctx.readPixels()
        var fractionalPixels = 0
        for y in 0 ..< 32:
          for x in 0 ..< 32:
            let alpha = reference[x, y].a.int
            if alpha > 20 and alpha < 235:
              inc fractionalPixels
              check abs(grouped[x, y].a.int * 2 - alpha) <= 5
        check fractionalPixels > 0

    test "reuses nested targets and releases mismatched targets on resize":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        skip()
      else:
        let ctx = newContext(atlasSize = 32, maxQuads = 8)
        ctx.beginFrame(vec2(32, 32), clearMain = true)
        ctx.beginOpacityGroup(0.5)
        ctx.beginOpacityGroup(0.5)
        let outer = ctx.opacityTextures[0].borrow
        let inner = ctx.opacityTextures[1].borrow
        ctx.endOpacityGroup()
        ctx.endOpacityGroup()
        ctx.beginOpacityGroup(0.5)
        ctx.beginOpacityGroup(0.5)
        check ctx.opacityTextures[0].borrow == outer
        check ctx.opacityTextures[1].borrow == inner
        ctx.endOpacityGroup()
        ctx.endOpacityGroup()
        ctx.endFrame()
        ctx.beginFrame(vec2(16, 16), clearMain = true)
        check ctx.opacityTextures[0].isNil
        check ctx.opacityTextures[1].isNil
        ctx.endFrame()
else:
  suite "Metal opacity groups":
    test "Metal backend not enabled":
      skip()
