import std/[hashes, os, unittest]
import figdraw/commons

when UseMetalBackend or UseOpenGlBackend:
  import pkg/[chroma, pixie]
  import figdraw/[figbasics, figbackend]
  import figdraw/common/texturecompression

  proc solid(w, h: int, value: ColorRGBA): Image =
    result = newImage(w, h)
    for pixel in result.data.mitems:
      pixel = value.rgbx

  template checkNear(actual: untyped, expected: int, tolerance = 8) =
    check abs(actual.int - expected) <= tolerance

  template exercise(ctx: untyped, readResult: untyped) =
    let asymmetric = newImage(5, 8)
    for y in 0 ..< asymmetric.height:
      for x in 0 ..< asymmetric.width:
        asymmetric[x, y] =
          (if y < 4: rgba(255, 0, 0, 255) else: rgba(0, 0, 255, 128)).rgbx
    let payload = compressImage(asymmetric)
    let decoded = payload.decompressImage()
    let second = compressImage(solid(5, 7, rgba(0, 255, 0, 255)))
    let atlas = solid(4, 4, rgba(255, 255, 0, 255))
    let field = solid(4, 4, rgba(255, 255, 255, 255))
    let firstKey = hash("bc3 asymmetry")
    let secondKey = hash("bc3 green")
    let atlasKey = hash("ordinary yellow")
    let fieldKey = hash("mtsdf white")
    let native = ctx.supportsTextureCompression(tcfBc3)
    echo "BC3 native support: ", native
    if getEnv("FIGDRAW_REQUIRE_NATIVE_BC3") == "1":
      require native
    ctx.putImage(firstKey, atlas)
    ctx.putCompressedImage(firstKey, payload)
    ctx.putCompressedImage(secondKey, second)
    ctx.putImage(atlasKey, atlas)
    ctx.putImage(fieldKey, field)
    check ctx.compressedTextureCount() == 2 * ord(native)
    check ctx.compressedTextureBytes() ==
      (payload.data.len + second.data.len) * ord(native)
    ctx.beginFrame(vec2(96, 48), clearMain = true, clearMainColor = color(0, 0, 0, 0))
    let white = rgba(255, 255, 255, 255)
    let tint = rgba(128, 255, 255, 255)
    ctx.drawImage(
      firstKey, vec2(0, 0), [white, white, white, white], vec2(16, 16), false
    )
    ctx.drawImage(
      atlasKey, vec2(16, 0), [white, white, white, white], vec2(16, 16), false
    )
    ctx.drawImage(
      secondKey, vec2(32, 0), [white, white, white, white], vec2(16, 16), false
    )
    ctx.drawMtsdfImage(
      fieldKey, vec2(48, 0), color(1, 0, 1, 1), vec2(16, 16), 4, 0.5, 0
    )
    ctx.drawImage(firstKey, vec2(64, 0), [tint, tint, tint, tint], vec2(16, 16), true)
    ctx.beginRectMask(rect(0, 16, 8, 16), default(CornerRadii2D[float32]))
    ctx.drawImage(
      secondKey, vec2(0, 16), [white, white, white, white], vec2(16, 16), false
    )
    ctx.popRectMask()
    ctx.drawRect(rect(16, 16, 16, 16), color(0, 0, 1, 1))
    ctx.endFrame()
    let pixels = readResult
    checkNear(pixels[4, 3].r, decoded[2, 1].r.int)
    checkNear(pixels[4, 12].b, decoded[2, 6].b.int)
    checkNear(pixels[4, 12].a, decoded[2, 6].a.int)
    check pixels[20, 4].r > 240 and pixels[20, 4].g > 240
    check pixels[36, 4].g > 240 and pixels[36, 4].r < 10
    check pixels[52, 4].r > 220 and pixels[52, 4].b > 220
    checkNear(pixels[68, 3].b, decoded[2, 6].b.int)
    checkNear(pixels[68, 12].r, decoded[2, 1].r.int div 2)
    check pixels[4, 24].g > 240
    check pixels[12, 24].a < 10
    check pixels[20, 24].b > 240
    ctx.beginFrame(vec2(96, 48), clearMain = true, clearMainColor = color(0, 0, 0, 0))
    ctx.drawImage(firstKey, vec2(0, 0), color(1, 1, 1, 1), 2.0'f32)
    ctx.drawImage(secondKey, vec2(16, 0), [white, white, white, white], 2.0'f32)
    ctx.drawImageAdj(secondKey, vec2(32, 0), color(1, 1, 1, 1), vec2(12, 12))
    ctx.drawSprite(secondKey, vec2(56, 8), color(1, 1, 1, 1), 2.0'f32)
    ctx.drawSprite(secondKey, vec2(72, 8), color(1, 1, 1, 1), vec2(12, 12))
    ctx.endFrame()
    let overloadPixels = readResult
    check overloadPixels[4, 3].r > 240
    check overloadPixels[20, 3].g > 240
    check overloadPixels[36, 3].g > 240
    check overloadPixels[56, 8].g > 240
    check overloadPixels[72, 8].g > 240
    ctx.putImage(firstKey, atlas)
    check ctx.compressedTextureCount() == ord(native)
    check ctx.compressedTextureBytes() == second.data.len * ord(native)
    ctx.putCompressedImage(firstKey, payload)
    check ctx.compressedTextureCount() == 2 * ord(native)
    ctx.removeImage(firstKey.ImageId)
    check not ctx.hasImage(firstKey)
    check ctx.compressedTextureCount() == ord(native)
    let owner = 123.OwnerToken
    ctx.retainImageOwner(secondKey.ImageId, owner)
    check ctx.releaseImageOwner(secondKey.ImageId, owner)
    ctx.removeImage(secondKey.ImageId)
    check not ctx.hasImage(secondKey)
    check ctx.compressedTextureCount() == 0
    ctx.putCompressedImage(firstKey, payload)
    ctx.resetImageAtlas(64)
    check ctx.compressedTextureCount() == 0
    ctx.putCompressedImage(firstKey, payload)
    check ctx.compressedTextureCount() == ord(native)
    ctx.clearImageAtlas()
    check ctx.compressedTextureCount() == 0
    check ctx.compressedTextureBytes() == 0
    ctx.finishPendingFrames()

when UseMetalBackend:
  import figdraw/metal/metal_context
  import metalx/[metal, objc_owned]

  suite "Metal compressed images":
    test "oversized compressed replacement preserves the existing texture":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        if getEnv("FIGDRAW_REQUIRE_NATIVE_BC3") == "1":
          require false
        skip()
      else:
        let ctx = newContext(atlasSize = 64, maxQuads = 8)
        if ctx.supportsTextureCompression(tcfBc3):
          let key = hash("oversized replacement")
          let original = compressImage(solid(4, 4, rgba(255, 0, 0, 255)))
          ctx.putCompressedImage(key, original)
          let oversized = CompressedImage(
            format: tcfBc3, width: 1, height: 20000, data: newSeq[uint8](5000 * 16)
          )
          expect ValueError:
            ctx.putCompressedImage(key, oversized)
          check ctx.hasImage(key)
          check ctx.compressedTextureCount() == 1
          check ctx.compressedTextureBytes() == original.data.len
          ctx.beginFrame(
            vec2(8, 8), clearMain = true, clearMainColor = color(0, 0, 0, 0)
          )
          let white = rgba(255, 255, 255, 255)
          ctx.drawImage(
            key, vec2(0, 0), [white, white, white, white], vec2(8, 8), false
          )
          ctx.endFrame()
          check ctx.readPixels()[4, 4].r > 240
          ctx.finishPendingFrames()
        else:
          if getEnv("FIGDRAW_REQUIRE_NATIVE_BC3") == "1":
            require false
          skip()
    test "standalone textures, atlas sampling and lifecycle":
      let device = fromRetained(MTLCreateSystemDefaultDevice())
      if device.isNil:
        if getEnv("FIGDRAW_REQUIRE_NATIVE_BC3") == "1":
          require false
        skip()
      else:
        let ctx = newContext(atlasSize = 64, maxQuads = 8)
        exercise(ctx, ctx.readPixels())

when UseOpenGlBackend:
  import figdraw/[windyshim, opengl/glcontext]
  import figdraw/utils/glutils

  suite "OpenGL compressed images":
    test "standalone textures, atlas sampling and lifecycle":
      let window = newWindow("compressed image test", ivec2(96, 48), visible = false)
      startOpenGL(openglVersion)
      window.makeContextCurrent()
      let ctx = newContext(atlasSize = 64, maxQuads = 8)
      exercise(ctx, ctx.readPixels(rect(0, 0, 0, 0), false))
      window.close()
