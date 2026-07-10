import std/unittest

import figdraw/commons

when UseVulkanBackend:
  import pkg/vulkan
  import figdraw/vulkan/vulkan_context
  import figdraw/vulkan/vulkan_utils

  suite "vulkan text runtime toggles":
    test "vulkan context stores text runtime flags":
      var ctx = VulkanContext()

      check ctx.textLcdFilteringEnabled() == false
      check ctx.textSubpixelPositioningEnabled() == false
      check ctx.textSubpixelGlyphVariantsEnabled() == false

      ctx.setTextLcdFilteringEnabled(true)
      ctx.setTextSubpixelPositioningEnabled(true)
      ctx.setTextSubpixelGlyphVariantsEnabled(true)
      ctx.setTextSubpixelShift(0.42'f32)

      check ctx.textLcdFilteringEnabled() == true
      check ctx.textSubpixelPositioningEnabled() == true
      check ctx.textSubpixelGlyphVariantsEnabled() == true

    test "zero surface extent uses requested window size":
      let capabilities = VkSurfaceCapabilitiesKHR(
        currentExtent: newVkExtent2D(width = 0, height = 0),
        minImageExtent: newVkExtent2D(width = 1, height = 1),
        maxImageExtent: newVkExtent2D(width = 4096, height = 4096),
      )

      let extent = chooseSwapExtent(capabilities, 800, 600)

      check extent.width == 800
      check extent.height == 600
else:
  suite "vulkan text runtime toggles":
    test "vulkan backend not enabled":
      check true
