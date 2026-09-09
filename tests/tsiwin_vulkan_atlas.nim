import std/[os, unittest]
import figdraw/commons

when UseVulkanBackend:
  import pixie
  import figdraw/figrender
  import figdraw/figbasics
  import figdraw/windowing/siwinshim
  import figdraw/vulkan/vulkan_context

  type TestWindow = object
    renderer: FigRenderer[SiwinRenderBackend]
    window: Window
    ctx: VulkanContext

  proc close(testWindow: var TestWindow) =
    if not testWindow.ctx.isNil:
      testWindow.ctx.releaseBackendResources()
      check testWindow.ctx.validationErrorCount() == 0
    if not testWindow.window.isNil and testWindow.window.opened:
      testWindow.window.close()

  proc openTestWindow(title: string): TestWindow =
    result.renderer =
      newFigRenderer(atlasSize = 64, backendState = SiwinRenderBackend())
    try:
      result.window =
        newSiwinWindow(result.renderer, size = ivec2(256, 200), title = title)
      result.renderer.setupBackend(result.window)
      if result.renderer.backendKind() != rbVulkan:
        raise newException(ValueError, "Vulkan test cannot use OpenGL fallback")
      result.ctx = result.renderer.ctx.VulkanContext
      result.window.firstStep()
      result.renderer.beginFrame()
      result.ctx.beginFrame(vec2(result.window.backingSize()), clearMain = true)
      result.ctx.endFrame()
    except CatchableError:
      result.close()
      raise

  proc solidImage(r, g, b, a: uint8, width = 8, height = 8): Image =
    result = newImage(width, height)
    result.fill(rgba(r, g, b, a))

  proc begin(testWindow: TestWindow) =
    testWindow.renderer.presentationTarget().updatePresentationTarget(testWindow.window)
    testWindow.renderer.beginFrame()
    testWindow.ctx.beginFrame(
      vec2(testWindow.window.backingSize()),
      clearMain = true,
      clearMainColor = color(0, 0, 0, 1),
    )

  proc capture(testWindow: TestWindow): Image =
    testWindow.ctx.endFrame()
    testWindow.renderer.endFrame()
    result = takeOneFrameScreenshot(testWindow.renderer)
    doAssert not result.isNil
    doAssert result.width > 0 and result.height > 0

  proc drawImage(ctx: VulkanContext, key: Hash, x, y: float32) =
    ctx.drawImage(
      key,
      pos = vec2(x, y),
      colors = [
        rgba(255, 255, 255, 255),
        rgba(255, 255, 255, 255),
        rgba(255, 255, 255, 255),
        rgba(255, 255, 255, 255),
      ],
      size = vec2(24, 24),
      flipY = false,
    )

  proc assertPixel(image: Image, x, y: int, r, g, b: int) =
    let pixel = image[x, y]
    check abs(pixel.r.int - r) <= 3
    check abs(pixel.g.int - g) <= 3
    check abs(pixel.b.int - b) <= 3

  suite "Vulkan window atlas lifetime":
    test "keeps drawn images intact across update, growth and clear in one frame":
      block runWindow:
        var testWindow: TestWindow
        try:
          testWindow = openTestWindow("FigDraw Vulkan atlas lifetime")
        except CatchableError:
          if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
            raise
          skip()
          break runWindow
        defer:
          testWindow.close()
        let ctx = testWindow.ctx
        ctx.putImage(1.Hash, solidImage(255, 0, 0, 255))
        testWindow.begin()
        ctx.drawImage(1.Hash, 8, 8)
        ctx.updateImage(1.Hash, solidImage(0, 0, 255, 255))
        ctx.drawImage(1.Hash, 40, 8)
        ctx.putImage(2.Hash, solidImage(255, 255, 255, 255, 80, 8))
        check ctx.hasImage(1.Hash)
        ctx.drawImage(1.Hash, 72, 8)
        ctx.clearImageAtlas()
        ctx.putImage(3.Hash, solidImage(0, 255, 0, 255))
        ctx.drawImage(3.Hash, 104, 8)
        let image = testWindow.capture()
        image.assertPixel(16, 16, 255, 0, 0)
        image.assertPixel(48, 16, 0, 0, 255)
        image.assertPixel(80, 16, 0, 0, 255)
        image.assertPixel(112, 16, 0, 255, 0)

        ctx.putImage(4.Hash, solidImage(255, 0, 0, 128))
        testWindow.begin()
        ctx.drawImage(4.Hash, 8, 8)
        testWindow.capture().assertPixel(16, 16, 128, 0, 0)

    test "parent atlas survives popup rendering and destruction":
      block runWindows:
        var parent, popup: TestWindow
        try:
          parent = openTestWindow("FigDraw Vulkan parent")
        except CatchableError:
          if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
            raise
          skip()
          break runWindows
        defer:
          parent.close()
        parent.ctx.putImage(1.Hash, solidImage(255, 0, 0, 255))
        parent.begin()
        parent.ctx.drawImage(1.Hash, 8, 8)
        parent.capture().assertPixel(16, 16, 255, 0, 0)
        popup = openTestWindow("FigDraw Vulkan popup")
        defer:
          popup.close()
        popup.ctx.putImage(1.Hash, solidImage(0, 255, 0, 255))
        popup.begin()
        popup.ctx.drawImage(1.Hash, 8, 8)
        popup.capture().assertPixel(16, 16, 0, 255, 0)
        parent.begin()
        parent.ctx.drawImage(1.Hash, 8, 8)
        parent.capture().assertPixel(16, 16, 255, 0, 0)
        popup.close()
        parent.window.size = parent.window.size + ivec2(64, 32)
        parent.window.step()
        # More frames than the swapchain image count exercise semaphore reuse.
        for frame in 0 ..< 8:
          parent.begin()
          parent.ctx.drawImage(1.Hash, 8, 8)
          # Resizing may discard one acquired frame on MoltenVK.
          if frame == 0:
            parent.ctx.endFrame()
            parent.renderer.endFrame()
          else:
            parent.capture().assertPixel(16, 16, 255, 0, 0)

    test "later backdrop blur does not change an earlier blur radius":
      block runWindow:
        var testWindow: TestWindow
        try:
          testWindow = openTestWindow("FigDraw Vulkan blur uniforms")
        except CatchableError:
          if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
            raise
          skip()
          break runWindow
        defer:
          testWindow.close()
        proc renderBlurs(secondBlur: bool): Image =
          testWindow.begin()
          testWindow.ctx.drawRect(rect(128, 0, 128, 200), color(1, 1, 1, 1))
          testWindow.ctx.drawBackdropBlur(
            rect(80, 20, 96, 40), default(CornerRadii2D[float32]), 2
          )
          if secondBlur:
            testWindow.ctx.drawBackdropBlur(
              rect(80, 100, 96, 40), default(CornerRadii2D[float32]), 12
            )
          testWindow.capture()

        let single = renderBlurs(false)
        let multiple = renderBlurs(true)
        for x in 120 .. 135:
          check abs(single[x, 40].r.int - multiple[x, 40].r.int) <= 2
        # Ensure the blur actually sampled across the black/white boundary.
        check single[127, 40].r > 0
        check single[128, 40].r < 255
else:
  suite "Vulkan window atlas lifetime":
    test "Vulkan backend not enabled":
      skip()
