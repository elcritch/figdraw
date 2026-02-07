import common/shared
import common/uimaths
import common/rchannels
import common/fontutils
import common/imgutils

const WantVulkanBackend {.booldefine: "figdraw.vulkan".} =
  defined(bsd) or defined(linux) or defined(windows)
const WantMetalBackend {.booldefine: "figdraw.metal".} =
  defined(macosx)
const UseOpenGlBackend* {.booldefine: "figdraw.opengl".} =
  not (WantMetalBackend or WantVulkanBackend)
const UseVulkanBackend* = WantVulkanBackend and not UseOpenGlBackend
const UseMetalBackend* = WantMetalBackend and not UseOpenGlBackend and not UseVulkanBackend

export shared, uimaths, rchannels
export fontutils
export imgutils
