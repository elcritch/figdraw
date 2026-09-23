import common/shared
import common/uimaths
import sigils/rchannels
import common/fontutils
import common/imgutils
import extras/systemfonts

const WantVulkanBackend {.booldefine: "figdraw.vulkan".} =
  defined(bsd) or defined(linux) or defined(windows)
const UseVulkanReadback* {.booldefine: "figdraw.vulkanReadback".} = false
const WantMetalBackend {.booldefine: "figdraw.metal".} = defined(macosx)
const WantQuartzBackend {.booldefine: "figdraw.quartz".} = false
const UseOpenGlBackend* {.booldefine: "figdraw.opengl".} =
  when defined(linux) or defined(cpu32):
    true
  else:
    not (WantMetalBackend or WantQuartzBackend or WantVulkanBackend)
const UseVulkanBackend* =
  WantVulkanBackend and not UseOpenGlBackend and not WantQuartzBackend
const UseMetalBackend* =
  WantMetalBackend and not UseOpenGlBackend and not UseVulkanBackend and
  not WantQuartzBackend
const UseQuartzBackend* =
  WantQuartzBackend and not UseOpenGlBackend and not UseVulkanBackend and
  not UseMetalBackend
const WantOpenGlFallback* {.booldefine: "figdraw.openglFallback".} =
  UseMetalBackend or UseVulkanBackend
const UseOpenGlFallback* =
  WantOpenGlFallback and not UseOpenGlBackend and not UseQuartzBackend

export shared, uimaths, rchannels
export fontutils
export imgutils
export systemfonts
