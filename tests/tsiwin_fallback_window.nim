import std/unittest

import siwin/platforms
import figdraw/figrender
import figdraw/windowing/siwinshim

when defined(linux) or defined(bsd):
  import std/dynlib
  import x11/xlib as xlib
  from figdraw/vulkan/vulkan_utils import x11XcbConnection

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

  test "XCB bridge resolves an existing Xlib display":
    when defined(linux) or defined(bsd):
      let bridge = loadLib("libX11-xcb.so.1")
      if bridge == nil:
        skip()
      else:
        defer:
          unloadLib(bridge)
        let display = xlib.XOpenDisplay(nil)
        if display == nil:
          skip()
        else:
          defer:
            discard xlib.XCloseDisplay(display)
          check x11XcbConnection(cast[pointer](display)) != nil
    else:
      skip()
