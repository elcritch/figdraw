import std/unittest

import figdraw/commons

when UseMetalBackend:
  # Inspect optional allocations alongside their public rendering paths.
  include ../src/figdraw/metal/metal_context

  suite "Metal optional memory":
    test "allocates backdrop and rect-mask storage only when used":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        skip()
      else:
        let ctx = newContext(atlasSize = 32, maxQuads = 8)
        check ctx.backdropTexture.isNil
        check ctx.rectMaskParams.data.len == 0

        ctx.beginFrame(vec2(32, 32), clearMain = true)
        ctx.drawRect(rect(0, 0, 32, 32), color(1, 0, 0, 1))
        ctx.endFrame()
        check ctx.backdropTexture.isNil
        check ctx.rectMaskParams.data.len == 0
        let pixels = ctx.readPixels()
        check pixels[8, 8].r == 255
        check pixels[8, 8].g == 0
        check pixels[8, 8].b == 0

        ctx.beginFrame(vec2(32, 32), clearMain = true)
        ctx.beginRectMask(rect(0, 0, 16, 16), default(CornerRadii2D[float32]))
        ctx.drawRect(rect(0, 0, 16, 16), color(0, 1, 0, 1))
        ctx.popRectMask()
        check ctx.rectMaskParams.data.len == 4 * 8 * 4
        ctx.drawBackdropBlur(rect(0, 0, 16, 16), default(CornerRadii2D[float32]), 4)
        ctx.beginMask(rect(0, 0, 16, 16), default(CornerRadii2D[float32]))
        ctx.endMask()
        ctx.drawRect(rect(0, 0, 16, 16), color(0, 0, 1, 1))
        ctx.popMask()
        ctx.endFrame()
        check not ctx.backdropTexture.isNil
        check not ctx.backdropBlurTempTexture.isNil
        check ctx.maskTextures.len == 2
        check not ctx.maskTextures[1].isNil

        for unusedFrame in 1 .. maxFramesInFlight:
          ctx.beginFrame(vec2(32, 32), clearMain = true)
          ctx.drawRect(rect(0, 0, 8, 8), color(1, 0, 0, 1))
          ctx.endFrame()
          if unusedFrame < maxFramesInFlight:
            check not ctx.backdropTexture.isNil
            check not ctx.backdropBlurTempTexture.isNil
        check ctx.backdropTexture.isNil
        check ctx.backdropBlurTempTexture.isNil

        ctx.beginFrame(vec2(32, 32), clearMain = true)
        ctx.drawBackdropBlur(rect(0, 0, 16, 16), default(CornerRadii2D[float32]), 4)
        ctx.endFrame()
        check not ctx.backdropTexture.isNil

        ctx.beginFrame(vec2(16, 16), clearMain = true)
        check ctx.backdropTexture.isNil
        check ctx.backdropBlurTempTexture.isNil
        check ctx.maskTextures[1].isNil
        ctx.beginMask(rect(0, 0, 8, 8), default(CornerRadii2D[float32]))
        ctx.endMask()
        check not ctx.maskTextures[1].isNil
        ctx.popMask()
        ctx.endFrame()
else:
  suite "Metal optional memory":
    test "Metal backend not enabled":
      skip()
