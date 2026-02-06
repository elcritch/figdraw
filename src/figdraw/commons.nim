import common/shared
import common/uimaths
import common/rchannels
import common/fontutils
import common/imgutils

const UseVulkanBackend* {.booldefine: "figdraw.vulkan".} =
  defined(bsd) or defined(linux) or defined(windows)
const UseMetalBackend* {.booldefine: "figdraw.metal".} =
  defined(macosx) and not UseVulkanBackend

export shared, uimaths, rchannels
export fontutils
export imgutils
