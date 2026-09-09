import std/[unittest, os, importutils]
import figdraw/commons

when UseOpenGlBackend:
  import pkg/[opengl, pixie]
  import figdraw/[figrender, figbasics]
  import figdraw/windowing/siwinshim
  import figdraw/opengl/[glcontext, textures]

  privateAccess OpenGlContext

  proc glInteger(name: GLenum): GLint =
    glGetIntegerv(name, result.addr)

  type TestWindow = object
    window: Window
    renderer: FigRenderer[SiwinRenderBackend]
    ctx: OpenGlContext

  proc close(testWindow: var TestWindow) =
    if not testWindow.window.isNil and testWindow.window.opened:
      testWindow.window.close()

  proc openTestWindow(): TestWindow =
    result.window = newSiwinWindow(size = ivec2(256, 200), vsync = false)
    try:
      result.window.firstStep()
      result.window.makeCurrent()
      result.renderer =
        newFigRenderer(atlasSize = 64, backendState = SiwinRenderBackend())
      result.renderer.setupBackend(result.window)
      result.ctx = OpenGlContext(result.renderer.ctx)
    except CatchableError:
      result.close()
      raise

  proc solid(r, g, b: uint8, width = 8, height = 8): Image =
    result = newImage(width, height)
    result.fill(rgba(r, g, b, 255))

  proc draw(testWindow: TestWindow, key: Hash): Image =
    testWindow.renderer.beginFrame()
    testWindow.ctx.beginFrame(
      vec2(testWindow.window.backingSize()),
      clearMain = true,
      clearMainColor = color(0, 0, 0, 1),
    )
    testWindow.ctx.drawImage(
      key,
      vec2(8, 8),
      [
        rgba(255, 255, 255, 255),
        rgba(255, 255, 255, 255),
        rgba(255, 255, 255, 255),
        rgba(255, 255, 255, 255),
      ],
      vec2(24, 24),
      false,
    )
    testWindow.ctx.endFrame()
    result = testWindow.renderer.takeOneFrameScreenshot()

  template assertPixel(image: Image, expectedR, expectedG, expectedB: int) =
    let px = image[16, 16]
    check abs(px.r.int - expectedR) <= 2
    check abs(px.g.int - expectedG) <= 2
    check abs(px.b.int - expectedB) <= 2

  template withWindow(body: untyped) =
    block runWindow:
      var testWindow {.inject.}: TestWindow
      try:
        testWindow = openTestWindow()
      except CatchableError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        skip()
        break runWindow
      defer:
        testWindow.close()
      body

  suite "OpenGL atlas isolation":
    test "resource preparation selects its window before beginFrame":
      withWindow:
        let parent = testWindow
        discard parent.renderer.ensureImage(1.ImageId, solid(255, 0, 0))
        var popup = openTestWindow()
        defer:
          popup.close()
        discard popup.renderer.ensureImage(1.ImageId, solid(0, 255, 0))
        # Match Merenda prepare(): uploads happen while the popup is current.
        discard parent.renderer.ensureImage(2.ImageId, solid(0, 0, 255))
        parent.draw(2.Hash).assertPixel(0, 0, 255)
        popup.draw(1.Hash).assertPixel(0, 255, 0)
        parent.draw(1.Hash).assertPixel(255, 0, 0)
        popup.renderer.activateContext()
        parent.renderer.rebuildImageAtlas()
        discard parent.renderer.ensureImage(3.ImageId, solid(255, 0, 0))
        parent.draw(3.Hash).assertPixel(255, 0, 0)
        popup.draw(1.Hash).assertPixel(0, 255, 0)
        popup.close()
        parent.draw(3.Hash).assertPixel(255, 0, 0)

    test "single-pixel and narrow images upload their base level":
      withWindow:
        testWindow.ctx.putImage(1.Hash, solid(255, 0, 0, 1, 1))
        testWindow.draw(1.Hash).assertPixel(255, 0, 0)
        testWindow.ctx.putImage(2.Hash, solid(0, 255, 0, 1, 8))
        testWindow.draw(2.Hash).assertPixel(0, 255, 0)

    test "growth preserves images and exact-width allocations fit":
      withWindow:
        testWindow.ctx.putImage(1.Hash, solid(255, 0, 0, 56, 8))
        check testWindow.ctx.atlasSize == 64
        testWindow.ctx.putImage(2.Hash, solid(0, 0, 255, 160, 8))
        check testWindow.ctx.hasImage(1.Hash)
        if testWindow.ctx.hasImage(1.Hash):
          testWindow.draw(1.Hash).assertPixel(255, 0, 0)
        let oldTexture = testWindow.ctx.atlasTexture.textureId
        expect ValueError:
          testWindow.ctx.resetImageAtlas(high(int))
        check testWindow.ctx.atlasTexture.textureId == oldTexture
        testWindow.ctx.clearImageAtlas()
        check glIsTexture(oldTexture) == GL_FALSE

    test "uploads and screenshots ignore and restore foreign pixel-transfer state":
      withWindow:
        var uploadBuffer, readBuffer: GLuint
        glGenBuffers(1, uploadBuffer.addr)
        glGenBuffers(1, readBuffer.addr)
        defer:
          glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
          glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
          glDeleteBuffers(1, uploadBuffer.addr)
          glDeleteBuffers(1, readBuffer.addr)
          glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
          glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
          glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
          glPixelStorei(GL_PACK_ROW_LENGTH, 0)
          glPixelStorei(GL_PACK_SKIP_PIXELS, 0)
          glPixelStorei(GL_PACK_SKIP_ROWS, 0)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, uploadBuffer)
        glBufferData(GL_PIXEL_UNPACK_BUFFER, 64, nil, GL_STATIC_DRAW)
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 23)
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 3)
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 2)
        testWindow.ctx.putImage(1.Hash, solid(255, 0, 0, 3, 5))
        check glInteger(GL_PIXEL_UNPACK_BUFFER_BINDING).GLuint == uploadBuffer
        check glInteger(GL_UNPACK_ROW_LENGTH) == 23
        check glInteger(GL_UNPACK_SKIP_PIXELS) == 3
        check glInteger(GL_UNPACK_SKIP_ROWS) == 2
        glBindBuffer(GL_PIXEL_PACK_BUFFER, readBuffer)
        glBufferData(GL_PIXEL_PACK_BUFFER, 64, nil, GL_STATIC_DRAW)
        glPixelStorei(GL_PACK_ROW_LENGTH, 23)
        glPixelStorei(GL_PACK_SKIP_PIXELS, 3)
        glPixelStorei(GL_PACK_SKIP_ROWS, 2)
        testWindow.draw(1.Hash).assertPixel(255, 0, 0)
        check glInteger(GL_PIXEL_PACK_BUFFER_BINDING).GLuint == readBuffer
        check glInteger(GL_PACK_ROW_LENGTH) == 23
        check glInteger(GL_PACK_SKIP_PIXELS) == 3
        check glInteger(GL_PACK_SKIP_ROWS) == 2

    test "a fresh popup context establishes alpha blending and draw state":
      withWindow:
        let image = newImage(8, 8)
        image.fill(rgba(255, 0, 0, 128))
        testWindow.ctx.putImage(1.Hash, image)
        glDisable(GL_BLEND)
        glEnable(GL_SCISSOR_TEST)
        glScissor(0, 0, 0, 0)
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE)
        testWindow.draw(1.Hash).assertPixel(128, 0, 0)

    test "backdrop blur composites premultiplied transparent pixels correctly":
      withWindow:
        let ctx = testWindow.ctx
        testWindow.renderer.beginFrame()
        ctx.beginFrame(
          vec2(testWindow.window.backingSize()),
          clearMain = true,
          clearMainColor = color(0, 0, 0, 0),
        )
        ctx.drawRect(rect(0, 0, 128, 128), color(1, 0, 0, 0.5))
        ctx.drawBackdropBlur(rect(8, 8, 32, 32), default(CornerRadii2D[float32]), 4)
        ctx.endFrame()
        testWindow.renderer.takeOneFrameScreenshot().assertPixel(192, 0, 0)

    test "resizing releases replaced backdrop textures":
      withWindow:
        let ctx = testWindow.ctx
        proc drawBlur(size: float32) =
          ctx.beginFrame(vec2(size, size), clearMain = true)
          ctx.drawBackdropBlur(rect(8, 8, 32, 32), default(CornerRadii2D[float32]), 4)
          ctx.endFrame()

        drawBlur(128)
        let oldBackdrop = ctx.backdropTexture.textureId
        let oldTemp = ctx.backdropBlurTempTexture.textureId
        ctx.beginFrame(vec2(96, 96), clearMain = true)
        check glIsTexture(oldBackdrop) == GL_FALSE
        ctx.drawBackdropBlur(rect(8, 8, 32, 32), default(CornerRadii2D[float32]), 4)
        check glIsTexture(oldTemp) == GL_FALSE
        ctx.endFrame()

    test "an image update cannot change already batched draws":
      withWindow:
        let ctx = testWindow.ctx
        ctx.putImage(1.Hash, solid(255, 0, 0))
        testWindow.renderer.beginFrame()
        ctx.beginFrame(vec2(testWindow.window.backingSize()), clearMain = true)
        ctx.drawImage(
          1.Hash,
          vec2(8, 8),
          [
            rgba(255, 255, 255, 255),
            rgba(255, 255, 255, 255),
            rgba(255, 255, 255, 255),
            rgba(255, 255, 255, 255),
          ],
          vec2(24, 24),
          false,
        )
        ctx.updateImage(1.Hash, solid(0, 0, 255))
        ctx.endFrame()
        testWindow.renderer.takeOneFrameScreenshot().assertPixel(255, 0, 0)
        expect ValueError:
          ctx.updateImage(1.Hash, solid(0, 255, 0, 16, 8))
        testWindow.draw(1.Hash).assertPixel(0, 0, 255)
else:
  suite "OpenGL atlas isolation":
    test "OpenGL backend not enabled":
      skip()
