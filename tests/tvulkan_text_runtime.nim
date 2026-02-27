import std/unittest

import figdraw/commons

when UseVulkanBackend:
  import figdraw/vulkan/vulkan_context

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
else:
  suite "vulkan text runtime toggles":
    test "vulkan backend not enabled":
      check true
