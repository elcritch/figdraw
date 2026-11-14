## Instance API versions tried by both Vulkan binding implementations.

const
  vulkanVersion1_0* = 1'u32 shl 22
  vulkanVersion1_1* = vulkanVersion1_0 or (1'u32 shl 12)

iterator instanceVersionAttempts*(loaderVersion: uint32): uint32 =
  if loaderVersion >= vulkanVersion1_1:
    yield vulkanVersion1_1
  yield vulkanVersion1_0
