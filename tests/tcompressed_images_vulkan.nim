import std/[unittest, hashes, os]
import figdraw/commons

when UseVulkanBackend:
  import pixie
  import figdraw/figrender
  import figdraw/figbasics
  import figdraw/windowing/siwinshim
  import figdraw/vulkan/vulkan_context
  import figdraw/common/texturecompression

  const white = [
    rgba(255, 255, 255, 255),
    rgba(255, 255, 255, 255),
    rgba(255, 255, 255, 255),
    rgba(255, 255, 255, 255),
  ]

  proc blocks(): CompressedImage =
    # Two BC3 blocks: opaque red over half-transparent blue.
    CompressedImage(
      format: tcfBc3,
      width: 4,
      height: 8,
      data: @[
        255'u8, 255, 0, 0, 0, 0, 0, 0, 0, 248, 0, 248, 0, 0, 0, 0, 128, 128, 0, 0, 0, 0,
        0, 0, 31, 0, 31, 0, 0, 0, 0, 0,
      ],
    )

  proc pixel(image: Image, x, y, r, g, b: int) =
    let p = image[x, y]
    check abs(p.r.int - r) <= 8
    check abs(p.g.int - g) <= 8
    check abs(p.b.int - b) <= 8

  suite "Vulkan compressed images":
    test "allocation and replacement follow device capability":
      let ctx = newContext(atlasSize = 64, maxQuads = 8)
      defer:
        ctx.releaseBackendResources()
      var available = true
      var native = false
      try:
        native = ctx.supportsTextureCompression(tcfBc3)
      except CatchableError:
        available = false
      if available:
        echo "Vulkan BC3 native: ", native
        let compressed = blocks()
        ctx.putCompressedImage(1.Hash, compressed)
        check ctx.hasImage(1.Hash)
        check ctx.compressedTextureCount() == ord(native)
        check ctx.compressedTextureBytes() == (if native: 32 else: 0)
        ctx.putImage(1.Hash, newImage(4, 8))
        check ctx.compressedTextureCount() == 0
        check 1.Hash in ctx.entries
        ctx.putCompressedImage(1.Hash, compressed)
        ctx.clearImageAtlas()
        check ctx.compressedTextureCount() == 0
        check not ctx.hasImage(1.Hash)

    test "readback preserves compressed pixels, draw order, and GPU resets":
      block runWindow:
        let renderer =
          newFigRenderer(atlasSize = 64, backendState = SiwinRenderBackend())
        let ctx = renderer.ctx.VulkanContext
        var window: Window
        try:
          # Upload before installing a presentation target, which recreates the device.
          let native = ctx.supportsTextureCompression(tcfBc3)
          echo "Vulkan readback BC3 native: ", native
          ctx.putCompressedImage(10.Hash, blocks())
          window =
            newSiwinWindow(renderer, size = ivec2(256, 200), title = "BC3 readback")
          renderer.setupBackend(window)
          if renderer.backendKind() != rbVulkan:
            raise newException(ValueError, "Vulkan backend unavailable")
          window.firstStep()
        except CatchableError:
          ctx.releaseBackendResources()
          if not window.isNil and window.opened:
            window.close()
          if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
            raise
          skip()
          break runWindow
        defer:
          ctx.releaseBackendResources()
          if not window.isNil and window.opened:
            window.close()
        renderer.presentationTarget().updatePresentationTarget(window)
        renderer.beginFrame()
        ctx.beginFrame(
          vec2(window.backingSize()),
          clearMain = true,
          clearMainColor = color(0, 0, 0, 1),
        )
        check ctx.hasImage(10.Hash)
        check ctx.compressedTextureCount() == ord(
          ctx.supportsTextureCompression(tcfBc3)
        )
        ctx.drawImage(10.Hash, vec2(8, 8), white, vec2(32, 64), false)
        ctx.drawImage(10.Hash, vec2(48, 8), white, vec2(32, 64), true)
        let green = newImage(4, 8)
        green.fill(rgba(0, 255, 0, 255))
        ctx.putImage(11.Hash, green)
        ctx.drawImage(11.Hash, vec2(88, 8), white, vec2(32, 64), false)
        ctx.drawImage(10.Hash, vec2(128, 8), color(0.5, 1, 1, 1), 8'f32)
        ctx.drawSprite(10.Hash, vec2(184, 40), color(1, 1, 1, 1), vec2(32, 64))
        ctx.beginMask(rect(8, 96, 16, 64), default(CornerRadii2D[float32]))
        ctx.endMask()
        ctx.drawImage(10.Hash, vec2(8, 96), white, vec2(32, 64), false)
        ctx.popMask()
        var greenBlocks = blocks()
        greenBlocks.data[8] = 224
        greenBlocks.data[9] = 7
        greenBlocks.data[10] = 224
        greenBlocks.data[11] = 7
        ctx.putCompressedImage(10.Hash, greenBlocks)
        ctx.drawImage(10.Hash, vec2(48, 96), white, 8'f32)
        ctx.putImage(10.Hash, green)
        ctx.drawImage(10.Hash, vec2(88, 96), white, vec2(32, 64), false)
        ctx.putCompressedImage(10.Hash, blocks())
        ctx.drawImageAdj(10.Hash, vec2(128, 96), color(1, 1, 1, 1), vec2(32, 64))
        ctx.drawSprite(10.Hash, vec2(184, 128), color(1, 1, 1, 1), 8.0)
        ctx.clearImageAtlas()
        ctx.putImage(12.Hash, green)
        ctx.drawImage(12.Hash, vec2(208, 96), white, vec2(32, 64), false)
        ctx.endFrame()
        renderer.endFrame()
        let image = takeOneFrameScreenshot(renderer)
        check not image.isNil
        image.pixel(20, 16, 255, 0, 0)
        image.pixel(20, 64, 0, 0, 128)
        image.pixel(60, 16, 0, 0, 128)
        image.pixel(60, 64, 255, 0, 0)
        image.pixel(100, 16, 0, 255, 0)
        image.pixel(140, 16, 128, 0, 0)
        image.pixel(184, 16, 255, 0, 0)
        image.pixel(12, 104, 255, 0, 0)
        image.pixel(30, 104, 0, 0, 0)
        image.pixel(60, 104, 0, 255, 0)
        image.pixel(100, 104, 0, 255, 0)
        image.pixel(140, 100, 255, 0, 0)
        image.pixel(184, 104, 255, 0, 0)
        image.pixel(220, 104, 0, 255, 0)
        check ctx.compressedTextureCount() == 0
        check ctx.validationErrorCount() == 0
