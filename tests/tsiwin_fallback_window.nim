import std/unittest

import siwin/platforms
import figdraw/figrender
import figdraw/windowing/siwinshim

suite "Siwin OpenGL fallback window selection":
  test "forced OpenGL always creates an OpenGL window":
    check usesOpenGlWindowForVulkanFallback(Platform.x11, true)

  test "Wayland keeps a non-OpenGL window while Vulkan is preferred":
    check not usesOpenGlWindowForVulkanFallback(Platform.wayland, false)

  test "X11 keeps a non-OpenGL window while Vulkan is preferred":
    check not usesOpenGlWindowForVulkanFallback(Platform.x11, false)

  test "renderer-specific layer surface API compiles":
    when defined(linux) or defined(bsd):
      check compiles(
        block:
          let
            renderer =
              newFigRenderer(atlasSize = 64, backendState = SiwinRenderBackend())
            config = default(LayerSurfaceConfig)
          discard
            newSiwinLayerSurfaceWindow(renderer, size = ivec2(320, 32), config = config)
      )
    else:
      skip()
