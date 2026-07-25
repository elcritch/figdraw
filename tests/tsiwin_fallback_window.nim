import std/unittest

import siwin/platforms
import figdraw/commons
import figdraw/windowing/siwinshim

suite "Siwin OpenGL fallback window selection":
  test "forced OpenGL always creates an OpenGL window":
    check usesOpenGlWindowForVulkanFallback(Platform.x11, true)

  test "Wayland has an OpenGL window when Vulkan fallback is enabled":
    when UseVulkanBackend and UseOpenGlFallback:
      check usesOpenGlWindowForVulkanFallback(Platform.wayland, false)
    else:
      check not usesOpenGlWindowForVulkanFallback(Platform.wayland, false)

  test "X11 has an OpenGL window when Vulkan fallback is enabled":
    when UseVulkanBackend and UseOpenGlFallback:
      check usesOpenGlWindowForVulkanFallback(Platform.x11, false)
    else:
      check not usesOpenGlWindowForVulkanFallback(Platform.x11, false)
