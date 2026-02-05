import pkg/chronicles
import pkg/opengl
import pkg/vulkan

from pkg/pixie import Image, newImage, flipVertical

import ../commons
import ../utils/glutils
import ../opengl/glcontext as glctx

export glctx

logScope:
  scope = "vulkan"

var vulkanPreloaded = false

proc ensureVulkanAvailable() =
  if vulkanPreloaded:
    return
  try:
    vkPreload()
  except LibraryError as err:
    raise newException(ValueError, "Vulkan loader unavailable: " & err.msg)
  vulkanPreloaded = true

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0,
): Context =
  ## Initializes Vulkan loader (WIP) and uses the OpenGL-backed context.
  ensureVulkanAvailable()
  result = glctx.newContext(
    atlasSize = atlasSize,
    atlasMargin = atlasMargin,
    maxQuads = maxQuads,
    pixelate = pixelate,
    pixelScale = pixelScale,
  )

proc readPixels*(
    ctx: Context,
    frame: Rect = rect(0, 0, 0, 0),
    readFront = true,
): Image =
  var viewport: array[4, GLint]
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)

  let
    viewportWidth = viewport[2].int
    viewportHeight = viewport[3].int

  var x = frame.x.int
  var y = frame.y.int
  var w = frame.w.int
  var h = frame.h.int

  if w <= 0 or h <= 0:
    x = 0
    y = 0
    w = viewportWidth
    h = viewportHeight

  glReadBuffer(if readFront: GL_FRONT else: GL_BACK)
  result = newImage(w, h)
  glReadPixels(
    x.GLint, y.GLint, w.GLint, h.GLint, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr
  )
  result.flipVertical()
  glReadBuffer(GL_BACK)

proc beginFrame*(
    ctx: Context,
    frameSize: Vec2,
    proj: Mat4,
    clearMain = false,
    clearMainColor: Color = whiteColor,
) =
  if clearMain:
    clearColorBuffer(clearMainColor)
  glctx.beginFrame(ctx, frameSize, proj)

proc beginFrame*(
    ctx: Context,
    frameSize: Vec2,
    clearMain = false,
    clearMainColor: Color = whiteColor,
) =
  beginFrame(
    ctx,
    frameSize,
    ortho[float32](0.0, frameSize.x, frameSize.y, 0, -1000.0, 1000.0),
    clearMain = clearMain,
    clearMainColor = clearMainColor,
  )
