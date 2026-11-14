const WantVulkanBackend {.booldefine: "figdraw.vulkan".} =
  defined(bsd) or defined(linux) or defined(windows)
when defined(cpu32) and defined(figdraw.vulkan) and WantVulkanBackend:
  {.
    error:
      "FigDraw's Vulkan backend requires a 64-bit target; use OpenGL on 32-bit targets"
  .}

import common/shared
import common/uimaths
import sigils/rchannels
import common/fontutils
import common/imgutils
import extras/systemfonts

const UseVulkanReadback* {.booldefine: "figdraw.vulkanReadback".} = false
const WantMetalBackend {.booldefine: "figdraw.metal".} = defined(macosx)
const UseOpenGlBackend* {.booldefine: "figdraw.opengl".} =
  when defined(linux) or defined(cpu32):
    true
  else:
    not (WantMetalBackend or WantVulkanBackend)
const UseVulkanBackend* = WantVulkanBackend and not UseOpenGlBackend
const UseMetalBackend* =
  WantMetalBackend and not UseOpenGlBackend and not UseVulkanBackend
const WantOpenGlFallback* {.booldefine: "figdraw.openglFallback".} =
  UseMetalBackend or UseVulkanBackend
const UseOpenGlFallback* = WantOpenGlFallback and not UseOpenGlBackend

export shared, uimaths, rchannels
export fontutils
export imgutils
export systemfonts
