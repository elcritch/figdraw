import std/unittest

import siwin/platforms
import figdraw/figrender
import figdraw/windowing/siwinshim

when defined(linux) or defined(bsd):
  import siwin/platforms/x11/x11api as xlib
  from figdraw/windowing/siwinx11compat import nil
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

  test "a missing optional XCB bridge returns nil":
    when (defined(linux) or defined(bsd)) and defined(features.figdraw.siwin):
      let original = xlib.XGetXCBConnection
      defer:
        xlib.XGetXCBConnection = original
      xlib.XGetXCBConnection = nil
      check x11XcbConnection(nil) == nil
    else:
      skip()

  test "Siwin visual queries and XCB bridge accept an existing Xlib display":
    when defined(linux) or defined(bsd):
      if not xlib.x11Available():
        skip()
      else:
        let display = xlib.XOpenDisplay(nil)
        if display == nil:
          skip()
        else:
          defer:
            discard xlib.XCloseDisplay(display)
          let visual =
            siwinx11compat.getX11VisualInfo(display, xlib.XRootWindow(display, 0))
          require visual != nil
          siwinx11compat.freeX11VisualInfo(visual)
          if xlib.x11XcbAvailable():
            check x11XcbConnection(cast[pointer](display)) != nil
          else:
            check x11XcbConnection(cast[pointer](display)) == nil
    else:
      skip()
