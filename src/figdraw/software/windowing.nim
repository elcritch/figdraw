## Upload a CPU frame through an existing FigDraw window renderer.
## This lets applications keep their siwin or Windy window/event APIs.

import std/hashes
import pkg/[chroma, pixie]
import ../[commons, figrender]

proc presentSoftwareFrame*[BackendState](
    renderer: FigRenderer[BackendState], image: Image
) =
  ## Use a dedicated window renderer as an image presenter. This submits its
  ## backend frame; the caller still brackets it with the window shim's
  ## `beginFrame` / `endFrame` for window setup and presentation.
  ## Image dimensions are physical frame pixels. No UI scale is applied again.
  if image.isNil:
    raise newException(ValueError, "Cannot present a nil software frame")
  renderer.activateContext()
  let
    ctx = renderer.ctx
    frameId = ImageId(hash(("figdraw.software.frame", cast[pointer](ctx))))
    size = vec2(image.width.float32, image.height.float32)
  ctx.replaceImageInAtlas(frameId, image)
  ctx.beginFrame(size, true, color(0, 0, 0, 0))
  ctx.drawImage(frameId.Hash, vec2(0, 0), color(1, 1, 1, 1), size, false)
  ctx.endFrame()
