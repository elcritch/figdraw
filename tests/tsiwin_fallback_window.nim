import std/unittest

import siwin/platforms
import figdraw/commons
import figdraw/figrender
import figdraw/windowing/siwinshim

when defined(linux) or defined(bsd):
  import siwin/platforms/x11/x11api as xlib
when UseVulkanBackend and (defined(linux) or defined(bsd) or defined(windows)):
  from figdraw/vulkan/vulkan_utils import nil

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
    when UseVulkanBackend and (defined(linux) or defined(bsd)) and
        defined(features.figdraw.siwin):
      let original = xlib.XGetXCBConnection
      defer:
        xlib.XGetXCBConnection = original
      xlib.XGetXCBConnection = nil
      check vulkan_utils.x11XcbConnection(nil) == nil
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
          let visual = xlib.getWindowVisualInfo(display, xlib.XRootWindow(display, 0))
          check visual.visual != nil
          check visual.depth > 0
          when UseVulkanBackend:
            if xlib.x11XcbAvailable():
              check vulkan_utils.x11XcbConnection(cast[pointer](display)) != nil
            else:
              check vulkan_utils.x11XcbConnection(cast[pointer](display)) == nil
    else:
      skip()

  test "Win32 Vulkan surface create info carries native handles":
    when defined(windows) and UseVulkanBackend:
      # Matches VkWin32SurfaceCreateInfoKHR: sType, pNext, flags, hinstance, hwnd.
      check sizeof(vulkan_utils.VkWin32SurfaceCreateInfoKHRNative) == 5 * sizeof(
        pointer
      )
      var info = vulkan_utils.VkWin32SurfaceCreateInfoKHRNative(
        hinstance: cast[pointer](0x1000), hwnd: cast[pointer](0x2000)
      )
      check info.hinstance == cast[pointer](0x1000)
      check info.hwnd == cast[pointer](0x2000)
    else:
      skip()
