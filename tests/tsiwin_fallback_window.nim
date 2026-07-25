import std/unittest

import siwin/platforms
import figdraw/windowing/siwinshim

suite "Siwin OpenGL fallback window selection":
  test "forced OpenGL always creates an OpenGL window":
    check usesOpenGlWindowForVulkanFallback(Platform.x11, true)

  test "Wayland keeps a non-OpenGL window while Vulkan is preferred":
    check not usesOpenGlWindowForVulkanFallback(Platform.wayland, false)

  test "X11 keeps a non-OpenGL window while Vulkan is preferred":
    check not usesOpenGlWindowForVulkanFallback(Platform.x11, false)
