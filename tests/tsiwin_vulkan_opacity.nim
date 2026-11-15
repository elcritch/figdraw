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

  suite "Vulkan opacity groups":
    test "overlap, nested groups and sibling state":
      block runWindow:
        var testWindow: TestWindow
        try:
          testWindow = openTestWindow("FigDraw Vulkan opacity")
        except CatchableError:
          if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
            raise
          skip()
          break runWindow
        defer:
          testWindow.close()
        let ctx = testWindow.ctx
        testWindow.begin()
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 0, 80, 80), color(1, 0, 0, 1))
        ctx.drawRect(rect(40, 0, 80, 80), color(0, 1, 0, 1))
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 80, 40, 40), color(0, 0, 1, 1))
        ctx.endOpacityGroup()
        ctx.endOpacityGroup()
        ctx.drawRect(rect(120, 0, 40, 40), color(0, 0, 1, 1))
        let image = testWindow.capture()
        image.assertPixel(20, 20, 128, 0, 0)
        image.assertPixel(60, 20, 0, 128, 0)
        image.assertPixel(20, 100, 0, 0, 64)
        image.assertPixel(140, 20, 0, 0, 255)

    test "fractional rounded clip applies once to overlapping children":
      block runWindow:
        var testWindow: TestWindow
        try:
          testWindow = openTestWindow("FigDraw Vulkan opacity clip")
        except CatchableError:
          if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
            raise
          skip()
          break runWindow
        defer:
          testWindow.close()
        let ctx = testWindow.ctx
        let radii =
          CornerRadii2D[float32](x: [20'f32, 20, 20, 20], y: [20'f32, 20, 20, 20])
        testWindow.begin()
        ctx.beginRectMask(rect(10, 10, 80, 80), radii)
        ctx.drawRect(rect(0, 0, 100, 100), color(1, 0, 0, 1))
        ctx.popRectMask()
        let reference = testWindow.capture()
        testWindow.begin()
        ctx.beginRectMask(rect(10, 10, 80, 80), radii)
        ctx.beginOpacityGroup(0.5)
        ctx.drawRect(rect(0, 0, 100, 100), color(1, 0, 0, 1))
        ctx.drawRect(rect(0, 0, 100, 100), color(1, 0, 0, 1))
        ctx.endOpacityGroup()
        ctx.popRectMask()
        let grouped = testWindow.capture()
        var fractionalPixels = 0
        for y in 0 ..< min(100, reference.height):
          for x in 0 ..< min(100, reference.width):
            let red = reference[x, y].r.int
            if red > 20 and red < 235:
              inc fractionalPixels
              check abs(grouped[x, y].r.int * 2 - red) <= 6
        check fractionalPixels > 0
else:
  suite "Vulkan opacity groups":
    test "Vulkan backend not enabled":
      skip()
