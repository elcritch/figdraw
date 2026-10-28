## Compatibility helpers for FigDraw's vk14 renderer.
## Constructors adapted from planetis-m/vulkan (MIT, Leonardo Mariscal, 2019).

# MIT License
# Copyright (c) 2019 Leonardo Mariscal
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import pkg/vk14/[types, commands, enums]
export types, commands, enums

when sizeof(pointer) != 8:
  {.error: "vk14's Vulkan handle declarations require a 64-bit target".}

type CAMetalLayer* = object

type VulkanError* = object of CatchableError
  res*: VkResult

proc raiseVkError*(msg: string, res: VkResult) {.noinline, noreturn.} =
  raise (ref VulkanError)(msg: msg, res: res)

template vkMakeVersion*(variant, major, minor, patch: untyped): untyped =
  vkMakeApiVersion(variant, major, minor, patch)

template vkVersionMajor*(v: untyped): untyped =
  vkApiVersionMajor(v)

template vkVersionMinor*(v: untyped): untyped =
  vkApiVersionMinor(v)

template vkVersionPatch*(v: untyped): untyped =
  vkApiVersionPatch(v)

const
  vkApiVersion1_0* = VK_API_VERSION_1_0
  vkApiVersion1_1* = VK_API_VERSION_1_1
  VkKhrSurfaceExtensionName* = "VK_KHR_surface"
  VkKhrSwapchainExtensionName* = "VK_KHR_swapchain"
  VkKhrXlibSurfaceExtensionName* = "VK_KHR_xlib_surface"
  VkKhrXcbSurfaceExtensionName* = "VK_KHR_xcb_surface"
  VkKhrWaylandSurfaceExtensionName* = "VK_KHR_wayland_surface"
  VkKhrWin32SurfaceExtensionName* = "VK_KHR_win32_surface"
  VkExtMetalSurfaceExtensionName* = "VK_EXT_metal_surface"
  VkExtDebugUtilsExtensionName* = "VK_EXT_debug_utils"

proc `==`*(a, b: VkInstance): bool {.borrow.}
proc `==`*(a, b: VkPhysicalDevice): bool {.borrow.}
proc `==`*(a, b: VkDevice): bool {.borrow.}
proc `==`*(a, b: VkQueue): bool {.borrow.}
proc `==`*(a, b: VkCommandBuffer): bool {.borrow.}
proc `==`*(a, b: VkDeviceMemory): bool {.borrow.}
proc `==`*(a, b: VkCommandPool): bool {.borrow.}
proc `==`*(a, b: VkBuffer): bool {.borrow.}
proc `==`*(a, b: VkBufferView): bool {.borrow.}
proc `==`*(a, b: VkImage): bool {.borrow.}
proc `==`*(a, b: VkImageView): bool {.borrow.}
proc `==`*(a, b: VkShaderModule): bool {.borrow.}
proc `==`*(a, b: VkPipeline): bool {.borrow.}
proc `==`*(a, b: VkPipelineLayout): bool {.borrow.}
proc `==`*(a, b: VkSampler): bool {.borrow.}
proc `==`*(a, b: VkDescriptorSet): bool {.borrow.}
proc `==`*(a, b: VkDescriptorSetLayout): bool {.borrow.}
proc `==`*(a, b: VkDescriptorPool): bool {.borrow.}
proc `==`*(a, b: VkFence): bool {.borrow.}
proc `==`*(a, b: VkSemaphore): bool {.borrow.}
proc `==`*(a, b: VkFramebuffer): bool {.borrow.}
proc `==`*(a, b: VkRenderPass): bool {.borrow.}
proc `==`*(a, b: VkPipelineCache): bool {.borrow.}
proc `==`*(a, b: VkSurfaceKHR): bool {.borrow.}
proc `==`*(a, b: VkSwapchainKHR): bool {.borrow.}
proc `==`*(a, b: VkDebugUtilsMessengerEXT): bool {.borrow.}
proc `==`*(a, b: VkFramebufferCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkRenderPassCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkSamplerCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineLayoutCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineDynamicStateCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineColorBlendStateCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineMultisampleStateCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineRasterizationStateCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineViewportStateCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineInputAssemblyStateCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineVertexInputStateCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineShaderStageCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkDescriptorSetLayoutCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkInstanceCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkDeviceCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkDeviceQueueCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkMemoryPropertyFlags): bool {.borrow.}
proc `==`*(a, b: VkAccessFlags): bool {.borrow.}
proc `==`*(a, b: VkBufferUsageFlags): bool {.borrow.}
proc `==`*(a, b: VkBufferCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkShaderStageFlags): bool {.borrow.}
proc `==`*(a, b: VkImageUsageFlags): bool {.borrow.}
proc `==`*(a, b: VkImageCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkImageViewCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkColorComponentFlags): bool {.borrow.}
proc `==`*(a, b: VkFenceCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkSemaphoreCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkShaderModuleCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkCommandPoolCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkCommandBufferResetFlags): bool {.borrow.}
proc `==`*(a, b: VkCommandBufferUsageFlags): bool {.borrow.}
proc `==`*(a, b: VkMemoryMapFlags): bool {.borrow.}
proc `==`*(a, b: VkImageAspectFlags): bool {.borrow.}
proc `==`*(a, b: VkSubpassDescriptionFlags): bool {.borrow.}
proc `==`*(a, b: VkPipelineStageFlags): bool {.borrow.}
proc `==`*(a, b: VkAttachmentDescriptionFlags): bool {.borrow.}
proc `==`*(a, b: VkCullModeFlags): bool {.borrow.}
proc `==`*(a, b: VkDescriptorPoolCreateFlags): bool {.borrow.}
proc `==`*(a, b: VkDescriptorPoolResetFlags): bool {.borrow.}
proc `==`*(a, b: VkDependencyFlags): bool {.borrow.}
proc `==`*(a, b: VkCompositeAlphaFlagsKHR): bool {.borrow.}
proc `==`*(a, b: VkSwapchainCreateFlagsKHR): bool {.borrow.}
proc `==`*(a, b: VkWaylandSurfaceCreateFlagsKHR): bool {.borrow.}
proc `==`*(a, b: VkWin32SurfaceCreateFlagsKHR): bool {.borrow.}
proc `==`*(a, b: VkXlibSurfaceCreateFlagsKHR): bool {.borrow.}
proc `==`*(a, b: VkXcbSurfaceCreateFlagsKHR): bool {.borrow.}
proc `==`*(a, b: VkMetalSurfaceCreateFlagsEXT): bool {.borrow.}
proc `==`*(a, b: VkDebugUtilsMessageSeverityFlagsEXT): bool {.borrow.}
proc `==`*(a, b: VkDebugUtilsMessageTypeFlagsEXT): bool {.borrow.}
proc `==`*(a, b: VkDebugUtilsMessengerCreateFlagsEXT): bool {.borrow.}

func contains*(flags: VkQueueFlags, bit: uint32): bool =
  (flags.uint32 and bit) != 0
func contains*(flags: VkCompositeAlphaFlagsKHR, bit: uint32): bool =
  (flags.uint32 and bit) != 0
func contains*(flags: VkImageUsageFlags, bit: uint32): bool =
  (flags.uint32 and bit) != 0
func `<=`*(a, b: VkMemoryPropertyFlags): bool =
  (a.uint32 and not b.uint32) == 0

proc newVkApplicationInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
    pNext: pointer = nil,
    pApplicationName: cstring,
    applicationVersion: uint32,
    pEngineName: cstring,
    engineVersion: uint32,
    apiVersion: uint32,
): VkApplicationInfo =
  result = VkApplicationInfo(
    sType: sType,
    pNext: pNext,
    pApplicationName: pApplicationName,
    applicationVersion: applicationVersion,
    pEngineName: pEngineName,
    engineVersion: engineVersion,
    apiVersion: apiVersion,
  )

proc newVkBufferCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkBufferCreateFlags = 0.VkBufferCreateFlags,
    size: VkDeviceSize,
    usage: VkBufferUsageFlags,
    sharingMode: VkSharingMode,
    queueFamilyIndices: openarray[uint32],
): VkBufferCreateInfo =
  result = VkBufferCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    size: size,
    usage: usage,
    sharingMode: sharingMode,
    queueFamilyIndexCount: len(queueFamilyIndices).uint32,
    pQueueFamilyIndices:
      if len(queueFamilyIndices) == 0:
        nil
      else:
        cast[ptr uint32](queueFamilyIndices),
  )

proc newVkCommandBufferAllocateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    pNext: pointer = nil,
    commandPool: VkCommandPool,
    level: VkCommandBufferLevel,
    commandBufferCount: uint32,
): VkCommandBufferAllocateInfo =
  result = VkCommandBufferAllocateInfo(
    sType: sType,
    pNext: pNext,
    commandPool: commandPool,
    level: level,
    commandBufferCount: commandBufferCount,
  )

proc newVkCommandBufferBeginInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pNext: pointer = nil,
    flags: VkCommandBufferUsageFlags = 0.VkCommandBufferUsageFlags,
    pInheritanceInfo: ptr VkCommandBufferInheritanceInfo,
): VkCommandBufferBeginInfo =
  result = VkCommandBufferBeginInfo(
    sType: sType, pNext: pNext, flags: flags, pInheritanceInfo: pInheritanceInfo
  )

proc newVkCommandPoolCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkCommandPoolCreateFlags = 0.VkCommandPoolCreateFlags,
    queueFamilyIndex: uint32,
): VkCommandPoolCreateInfo =
  result = VkCommandPoolCreateInfo(
    sType: sType, pNext: pNext, flags: flags, queueFamilyIndex: queueFamilyIndex
  )

proc newVkComponentMapping*(
    r: VkComponentSwizzle,
    g: VkComponentSwizzle,
    b: VkComponentSwizzle,
    a: VkComponentSwizzle,
): VkComponentMapping =
  result = VkComponentMapping(r: r, g: g, b: b, a: a)

proc newVkDebugUtilsMessengerCreateInfoEXT*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
    pNext: pointer = nil,
    flags: VkDebugUtilsMessengerCreateFlagsEXT = 0.VkDebugUtilsMessengerCreateFlagsEXT,
    messageSeverity: VkDebugUtilsMessageSeverityFlagsEXT,
    messageType: VkDebugUtilsMessageTypeFlagsEXT,
    pfnUserCallback: PFN_vkDebugUtilsMessengerCallbackEXT,
    pUserData: pointer = nil,
): VkDebugUtilsMessengerCreateInfoEXT =
  result = VkDebugUtilsMessengerCreateInfoEXT(
    sType: sType,
    pNext: pNext,
    flags: flags,
    messageSeverity: messageSeverity,
    messageType: messageType,
    pfnUserCallback: pfnUserCallback,
    pUserData: pUserData,
  )

proc newVkDescriptorBufferInfo*(
    buffer: VkBuffer, offset: VkDeviceSize, range: VkDeviceSize
): VkDescriptorBufferInfo =
  result = VkDescriptorBufferInfo(buffer: buffer, offset: offset, range: range)

proc newVkDescriptorImageInfo*(
    sampler: VkSampler, imageView: VkImageView, imageLayout: VkImageLayout
): VkDescriptorImageInfo =
  result = VkDescriptorImageInfo(
    sampler: sampler, imageView: imageView, imageLayout: imageLayout
  )

proc newVkDescriptorPoolCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkDescriptorPoolCreateFlags = 0.VkDescriptorPoolCreateFlags,
    maxSets: uint32,
    poolSizes: openarray[VkDescriptorPoolSize],
): VkDescriptorPoolCreateInfo =
  result = VkDescriptorPoolCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    maxSets: maxSets,
    poolSizeCount: len(poolSizes).uint32,
    pPoolSizes:
      if len(poolSizes) == 0:
        nil
      else:
        cast[ptr VkDescriptorPoolSize](poolSizes),
  )

proc newVkDescriptorPoolSize*(
    `type`: VkDescriptorType, descriptorCount: uint32
): VkDescriptorPoolSize =
  result = VkDescriptorPoolSize(`type`: `type`, descriptorCount: descriptorCount)

proc newVkDescriptorSetAllocateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    pNext: pointer = nil,
    descriptorPool: VkDescriptorPool,
    setLayouts: openarray[VkDescriptorSetLayout],
): VkDescriptorSetAllocateInfo =
  result = VkDescriptorSetAllocateInfo(
    sType: sType,
    pNext: pNext,
    descriptorPool: descriptorPool,
    descriptorSetCount: len(setLayouts).uint32,
    pSetLayouts:
      if len(setLayouts) == 0:
        nil
      else:
        cast[ptr VkDescriptorSetLayout](setLayouts),
  )

proc newVkDescriptorSetLayoutBinding*(
    binding: uint32,
    descriptorType: VkDescriptorType,
    descriptorCount: uint32,
    stageFlags: VkShaderStageFlags,
    pImmutableSamplers: ptr VkSampler,
): VkDescriptorSetLayoutBinding =
  result = VkDescriptorSetLayoutBinding(
    binding: binding,
    descriptorType: descriptorType,
    descriptorCount: descriptorCount,
    stageFlags: stageFlags,
    pImmutableSamplers: pImmutableSamplers,
  )

proc newVkDescriptorSetLayoutCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkDescriptorSetLayoutCreateFlags = 0.VkDescriptorSetLayoutCreateFlags,
    bindings: openarray[VkDescriptorSetLayoutBinding],
): VkDescriptorSetLayoutCreateInfo =
  result = VkDescriptorSetLayoutCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    bindingCount: len(bindings).uint32,
    pBindings:
      if len(bindings) == 0:
        nil
      else:
        cast[ptr VkDescriptorSetLayoutBinding](bindings),
  )

proc newVkDeviceCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkDeviceCreateFlags = 0.VkDeviceCreateFlags,
    queueCreateInfos: openarray[VkDeviceQueueCreateInfo],
    pEnabledLayerNames: openarray[cstring],
    pEnabledExtensionNames: openarray[cstring],
    enabledFeatures: openarray[VkPhysicalDeviceFeatures],
): VkDeviceCreateInfo =
  result = VkDeviceCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    queueCreateInfoCount: len(queueCreateInfos).uint32,
    pQueueCreateInfos:
      if len(queueCreateInfos) == 0:
        nil
      else:
        cast[ptr VkDeviceQueueCreateInfo](queueCreateInfos),
    enabledLayerCount: len(pEnabledLayerNames).uint32,
    ppEnabledLayerNames:
      if len(pEnabledLayerNames) == 0:
        nil
      else:
        cast[cstringArray](pEnabledLayerNames),
    enabledExtensionCount: len(pEnabledExtensionNames).uint32,
    ppEnabledExtensionNames:
      if len(pEnabledExtensionNames) == 0:
        nil
      else:
        cast[cstringArray](pEnabledExtensionNames),
    pEnabledFeatures:
      if len(enabledFeatures) == 0:
        nil
      else:
        cast[ptr VkPhysicalDeviceFeatures](enabledFeatures),
  )

proc newVkDeviceQueueCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkDeviceQueueCreateFlags = 0.VkDeviceQueueCreateFlags,
    queueFamilyIndex: uint32,
    queuePriorities: openarray[float32],
): VkDeviceQueueCreateInfo =
  result = VkDeviceQueueCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    queueFamilyIndex: queueFamilyIndex,
    queueCount: len(queuePriorities).uint32,
    pQueuePriorities:
      if len(queuePriorities) == 0:
        nil
      else:
        cast[ptr float32](queuePriorities),
  )

proc newVkExtent2D*(width: uint32, height: uint32): VkExtent2D =
  result = VkExtent2D(width: width, height: height)

proc newVkExtent3D*(width: uint32, height: uint32, depth: uint32): VkExtent3D =
  result = VkExtent3D(width: width, height: height, depth: depth)

proc newVkFenceCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkFenceCreateFlags = 0.VkFenceCreateFlags,
): VkFenceCreateInfo =
  result = VkFenceCreateInfo(sType: sType, pNext: pNext, flags: flags)

proc newVkFramebufferCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkFramebufferCreateFlags = 0.VkFramebufferCreateFlags,
    renderPass: VkRenderPass,
    attachments: openarray[VkImageView],
    width: uint32,
    height: uint32,
    layers: uint32,
): VkFramebufferCreateInfo =
  result = VkFramebufferCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    renderPass: renderPass,
    attachmentCount: len(attachments).uint32,
    pAttachments:
      if len(attachments) == 0:
        nil
      else:
        cast[ptr VkImageView](attachments),
    width: width,
    height: height,
    layers: layers,
  )

proc newVkGraphicsPipelineCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkPipelineCreateFlags = 0.VkPipelineCreateFlags,
    stages: openarray[VkPipelineShaderStageCreateInfo],
    pVertexInputState: ptr VkPipelineVertexInputStateCreateInfo,
    pInputAssemblyState: ptr VkPipelineInputAssemblyStateCreateInfo,
    pTessellationState: ptr VkPipelineTessellationStateCreateInfo,
    pViewportState: ptr VkPipelineViewportStateCreateInfo,
    pRasterizationState: ptr VkPipelineRasterizationStateCreateInfo,
    pMultisampleState: ptr VkPipelineMultisampleStateCreateInfo,
    pDepthStencilState: ptr VkPipelineDepthStencilStateCreateInfo,
    pColorBlendState: ptr VkPipelineColorBlendStateCreateInfo,
    pDynamicState: ptr VkPipelineDynamicStateCreateInfo,
    layout: VkPipelineLayout,
    renderPass: VkRenderPass,
    subpass: uint32,
    basePipelineHandle: VkPipeline,
    basePipelineIndex: int32,
): VkGraphicsPipelineCreateInfo =
  result = VkGraphicsPipelineCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    stageCount: len(stages).uint32,
    pStages:
      if len(stages) == 0:
        nil
      else:
        cast[ptr VkPipelineShaderStageCreateInfo](stages),
    pVertexInputState: pVertexInputState,
    pInputAssemblyState: pInputAssemblyState,
    pTessellationState: pTessellationState,
    pViewportState: pViewportState,
    pRasterizationState: pRasterizationState,
    pMultisampleState: pMultisampleState,
    pDepthStencilState: pDepthStencilState,
    pColorBlendState: pColorBlendState,
    pDynamicState: pDynamicState,
    layout: layout,
    renderPass: renderPass,
    subpass: subpass,
    basePipelineHandle: basePipelineHandle,
    basePipelineIndex: basePipelineIndex,
  )

proc newVkImageCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkImageCreateFlags = 0.VkImageCreateFlags,
    imageType: VkImageType,
    format: VkFormat,
    extent: VkExtent3D,
    mipLevels: uint32,
    arrayLayers: uint32,
    samples: VkSampleCountFlagBits,
    tiling: VkImageTiling,
    usage: VkImageUsageFlags,
    sharingMode: VkSharingMode,
    queueFamilyIndices: openarray[uint32],
    initialLayout: VkImageLayout,
): VkImageCreateInfo =
  result = VkImageCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    imageType: imageType,
    format: format,
    extent: extent,
    mipLevels: mipLevels,
    arrayLayers: arrayLayers,
    samples: samples,
    tiling: tiling,
    usage: usage,
    sharingMode: sharingMode,
    queueFamilyIndexCount: len(queueFamilyIndices).uint32,
    pQueueFamilyIndices:
      if len(queueFamilyIndices) == 0:
        nil
      else:
        cast[ptr uint32](queueFamilyIndices),
    initialLayout: initialLayout,
  )

proc newVkImageSubresourceLayers*(
    aspectMask: VkImageAspectFlags,
    mipLevel: uint32,
    baseArrayLayer: uint32,
    layerCount: uint32,
): VkImageSubresourceLayers =
  result = VkImageSubresourceLayers(
    aspectMask: aspectMask,
    mipLevel: mipLevel,
    baseArrayLayer: baseArrayLayer,
    layerCount: layerCount,
  )

proc newVkImageSubresourceRange*(
    aspectMask: VkImageAspectFlags,
    baseMipLevel: uint32,
    levelCount: uint32,
    baseArrayLayer: uint32,
    layerCount: uint32,
): VkImageSubresourceRange =
  result = VkImageSubresourceRange(
    aspectMask: aspectMask,
    baseMipLevel: baseMipLevel,
    levelCount: levelCount,
    baseArrayLayer: baseArrayLayer,
    layerCount: layerCount,
  )

proc newVkImageViewCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkImageViewCreateFlags = 0.VkImageViewCreateFlags,
    image: VkImage,
    viewType: VkImageViewType,
    format: VkFormat,
    components: VkComponentMapping,
    subresourceRange: VkImageSubresourceRange,
): VkImageViewCreateInfo =
  result = VkImageViewCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    image: image,
    viewType: viewType,
    format: format,
    components: components,
    subresourceRange: subresourceRange,
  )

proc newVkInstanceCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkInstanceCreateFlags = 0.VkInstanceCreateFlags,
    pApplicationInfo: ptr VkApplicationInfo,
    pEnabledLayerNames: openarray[cstring],
    pEnabledExtensionNames: openarray[cstring],
): VkInstanceCreateInfo =
  result = VkInstanceCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    pApplicationInfo: pApplicationInfo,
    enabledLayerCount: len(pEnabledLayerNames).uint32,
    ppEnabledLayerNames:
      if len(pEnabledLayerNames) == 0:
        nil
      else:
        cast[cstringArray](pEnabledLayerNames),
    enabledExtensionCount: len(pEnabledExtensionNames).uint32,
    ppEnabledExtensionNames:
      if len(pEnabledExtensionNames) == 0:
        nil
      else:
        cast[cstringArray](pEnabledExtensionNames),
  )

proc newVkMemoryAllocateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    pNext: pointer = nil,
    allocationSize: VkDeviceSize,
    memoryTypeIndex: uint32,
): VkMemoryAllocateInfo =
  result = VkMemoryAllocateInfo(
    sType: sType,
    pNext: pNext,
    allocationSize: allocationSize,
    memoryTypeIndex: memoryTypeIndex,
  )

proc newVkMetalSurfaceCreateInfoEXT*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
    pNext: pointer = nil,
    flags: VkMetalSurfaceCreateFlagsEXT = 0.VkMetalSurfaceCreateFlagsEXT,
    pLayer: ptr CAMetalLayer,
): VkMetalSurfaceCreateInfoEXT =
  result = VkMetalSurfaceCreateInfoEXT(
    sType: sType, pNext: pNext, flags: flags, pLayer: pLayer
  )

proc newVkOffset2D*(x: int32, y: int32): VkOffset2D =
  result = VkOffset2D(x: x, y: y)

proc newVkOffset3D*(x: int32, y: int32, z: int32): VkOffset3D =
  result = VkOffset3D(x: x, y: y, z: z)

proc newVkPipelineColorBlendAttachmentState*(
    blendEnable: VkBool32,
    srcColorBlendFactor: VkBlendFactor,
    dstColorBlendFactor: VkBlendFactor,
    colorBlendOp: VkBlendOp,
    srcAlphaBlendFactor: VkBlendFactor,
    dstAlphaBlendFactor: VkBlendFactor,
    alphaBlendOp: VkBlendOp,
    colorWriteMask: VkColorComponentFlags,
): VkPipelineColorBlendAttachmentState =
  result = VkPipelineColorBlendAttachmentState(
    blendEnable: blendEnable,
    srcColorBlendFactor: srcColorBlendFactor,
    dstColorBlendFactor: dstColorBlendFactor,
    colorBlendOp: colorBlendOp,
    srcAlphaBlendFactor: srcAlphaBlendFactor,
    dstAlphaBlendFactor: dstAlphaBlendFactor,
    alphaBlendOp: alphaBlendOp,
    colorWriteMask: colorWriteMask,
  )

proc newVkPipelineLayoutCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkPipelineLayoutCreateFlags = 0.VkPipelineLayoutCreateFlags,
    setLayouts: openarray[VkDescriptorSetLayout],
    pushConstantRanges: openarray[VkPushConstantRange],
): VkPipelineLayoutCreateInfo =
  result = VkPipelineLayoutCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    setLayoutCount: len(setLayouts).uint32,
    pSetLayouts:
      if len(setLayouts) == 0:
        nil
      else:
        cast[ptr VkDescriptorSetLayout](setLayouts),
    pushConstantRangeCount: len(pushConstantRanges).uint32,
    pPushConstantRanges:
      if len(pushConstantRanges) == 0:
        nil
      else:
        cast[ptr VkPushConstantRange](pushConstantRanges),
  )

proc newVkPipelineShaderStageCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkPipelineShaderStageCreateFlags = 0.VkPipelineShaderStageCreateFlags,
    stage: VkShaderStageFlagBits,
    module: VkShaderModule,
    pName: cstring,
    pSpecializationInfo: ptr VkSpecializationInfo,
): VkPipelineShaderStageCreateInfo =
  result = VkPipelineShaderStageCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    stage: stage,
    module: module,
    pName: pName,
    pSpecializationInfo: pSpecializationInfo,
  )

proc newVkPipelineVertexInputStateCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkPipelineVertexInputStateCreateFlags =
      0.VkPipelineVertexInputStateCreateFlags,
    vertexBindingDescriptions: openarray[VkVertexInputBindingDescription],
    vertexAttributeDescriptions: openarray[VkVertexInputAttributeDescription],
): VkPipelineVertexInputStateCreateInfo =
  result = VkPipelineVertexInputStateCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    vertexBindingDescriptionCount: len(vertexBindingDescriptions).uint32,
    pVertexBindingDescriptions:
      if len(vertexBindingDescriptions) == 0:
        nil
      else:
        cast[ptr VkVertexInputBindingDescription](vertexBindingDescriptions),
    vertexAttributeDescriptionCount: len(vertexAttributeDescriptions).uint32,
    pVertexAttributeDescriptions:
      if len(vertexAttributeDescriptions) == 0:
        nil
      else:
        cast[ptr VkVertexInputAttributeDescription](vertexAttributeDescriptions),
  )

proc newVkPresentInfoKHR*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    pNext: pointer = nil,
    waitSemaphores: openarray[VkSemaphore],
    swapchains: openarray[VkSwapchainKHR],
    imageIndices: openarray[uint32],
    results: openarray[VkResult],
): VkPresentInfoKHR =
  result = VkPresentInfoKHR(
    sType: sType,
    pNext: pNext,
    waitSemaphoreCount: len(waitSemaphores).uint32,
    pWaitSemaphores:
      if len(waitSemaphores) == 0:
        nil
      else:
        cast[ptr VkSemaphore](waitSemaphores),
    swapchainCount: len(swapchains).uint32,
    pSwapchains:
      if len(swapchains) == 0:
        nil
      else:
        cast[ptr VkSwapchainKHR](swapchains),
    pImageIndices:
      if len(imageIndices) == 0:
        nil
      else:
        cast[ptr uint32](imageIndices),
    pResults:
      if len(results) == 0:
        nil
      else:
        cast[ptr VkResult](results),
  )

proc newVkRect2D*(offset: VkOffset2D, extent: VkExtent2D): VkRect2D =
  result = VkRect2D(offset: offset, extent: extent)

proc newVkRenderPassCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkRenderPassCreateFlags = 0.VkRenderPassCreateFlags,
    attachments: openarray[VkAttachmentDescription],
    subpasses: openarray[VkSubpassDescription],
    dependencies: openarray[VkSubpassDependency],
): VkRenderPassCreateInfo =
  result = VkRenderPassCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    attachmentCount: len(attachments).uint32,
    pAttachments:
      if len(attachments) == 0:
        nil
      else:
        cast[ptr VkAttachmentDescription](attachments),
    subpassCount: len(subpasses).uint32,
    pSubpasses:
      if len(subpasses) == 0:
        nil
      else:
        cast[ptr VkSubpassDescription](subpasses),
    dependencyCount: len(dependencies).uint32,
    pDependencies:
      if len(dependencies) == 0:
        nil
      else:
        cast[ptr VkSubpassDependency](dependencies),
  )

proc newVkSamplerCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkSamplerCreateFlags = 0.VkSamplerCreateFlags,
    magFilter: VkFilter,
    minFilter: VkFilter,
    mipmapMode: VkSamplerMipmapMode,
    addressModeU: VkSamplerAddressMode,
    addressModeV: VkSamplerAddressMode,
    addressModeW: VkSamplerAddressMode,
    mipLodBias: float32,
    anisotropyEnable: VkBool32,
    maxAnisotropy: float32,
    compareEnable: VkBool32,
    compareOp: VkCompareOp,
    minLod: float32,
    maxLod: float32,
    borderColor: VkBorderColor,
    unnormalizedCoordinates: VkBool32,
): VkSamplerCreateInfo =
  result = VkSamplerCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    magFilter: magFilter,
    minFilter: minFilter,
    mipmapMode: mipmapMode,
    addressModeU: addressModeU,
    addressModeV: addressModeV,
    addressModeW: addressModeW,
    mipLodBias: mipLodBias,
    anisotropyEnable: anisotropyEnable,
    maxAnisotropy: maxAnisotropy,
    compareEnable: compareEnable,
    compareOp: compareOp,
    minLod: minLod,
    maxLod: maxLod,
    borderColor: borderColor,
    unnormalizedCoordinates: unnormalizedCoordinates,
  )

proc newVkSemaphoreCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkSemaphoreCreateFlags = 0.VkSemaphoreCreateFlags,
): VkSemaphoreCreateInfo =
  result = VkSemaphoreCreateInfo(sType: sType, pNext: pNext, flags: flags)

proc newVkShaderModuleCreateInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    pNext: pointer = nil,
    flags: VkShaderModuleCreateFlags = 0.VkShaderModuleCreateFlags,
    code: openarray[char],
): VkShaderModuleCreateInfo =
  result = VkShaderModuleCreateInfo(
    sType: sType,
    pNext: pNext,
    flags: flags,
    codeSize: len(code).uint,
    pCode:
      if len(code) == 0:
        nil
      else:
        cast[ptr uint32](code),
  )

proc newVkSubmitInfo*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
    pNext: pointer = nil,
    waitSemaphores: openarray[VkSemaphore],
    waitDstStageMask: openarray[VkPipelineStageFlags],
    commandBuffers: openarray[VkCommandBuffer],
    signalSemaphores: openarray[VkSemaphore],
): VkSubmitInfo =
  result = VkSubmitInfo(
    sType: sType,
    pNext: pNext,
    waitSemaphoreCount: len(waitSemaphores).uint32,
    pWaitSemaphores:
      if len(waitSemaphores) == 0:
        nil
      else:
        cast[ptr VkSemaphore](waitSemaphores),
    pWaitDstStageMask:
      if len(waitDstStageMask) == 0:
        nil
      else:
        cast[ptr VkPipelineStageFlags](waitDstStageMask),
    commandBufferCount: len(commandBuffers).uint32,
    pCommandBuffers:
      if len(commandBuffers) == 0:
        nil
      else:
        cast[ptr VkCommandBuffer](commandBuffers),
    signalSemaphoreCount: len(signalSemaphores).uint32,
    pSignalSemaphores:
      if len(signalSemaphores) == 0:
        nil
      else:
        cast[ptr VkSemaphore](signalSemaphores),
  )

proc newVkSwapchainCreateInfoKHR*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    pNext: pointer = nil,
    flags: VkSwapchainCreateFlagsKHR = 0.VkSwapchainCreateFlagsKHR,
    surface: VkSurfaceKHR,
    minImageCount: uint32,
    imageFormat: VkFormat,
    imageColorSpace: VkColorSpaceKHR,
    imageExtent: VkExtent2D,
    imageArrayLayers: uint32,
    imageUsage: VkImageUsageFlags,
    imageSharingMode: VkSharingMode,
    queueFamilyIndices: openarray[uint32],
    preTransform: VkSurfaceTransformFlagBitsKHR,
    compositeAlpha: VkCompositeAlphaFlagBitsKHR,
    presentMode: VkPresentModeKHR,
    clipped: VkBool32,
    oldSwapchain: VkSwapchainKHR,
): VkSwapchainCreateInfoKHR =
  result = VkSwapchainCreateInfoKHR(
    sType: sType,
    pNext: pNext,
    flags: flags,
    surface: surface,
    minImageCount: minImageCount,
    imageFormat: imageFormat,
    imageColorSpace: imageColorSpace,
    imageExtent: imageExtent,
    imageArrayLayers: imageArrayLayers,
    imageUsage: imageUsage,
    imageSharingMode: imageSharingMode,
    queueFamilyIndexCount: len(queueFamilyIndices).uint32,
    pQueueFamilyIndices:
      if len(queueFamilyIndices) == 0:
        nil
      else:
        cast[ptr uint32](queueFamilyIndices),
    preTransform: preTransform,
    compositeAlpha: compositeAlpha,
    presentMode: presentMode,
    clipped: clipped,
    oldSwapchain: oldSwapchain,
  )

proc newVkValidationFeaturesEXT*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT,
    pNext: pointer = nil,
    enabledValidationFeatures: openarray[VkValidationFeatureEnableEXT],
    disabledValidationFeatures: openarray[VkValidationFeatureDisableEXT],
): VkValidationFeaturesEXT =
  result = VkValidationFeaturesEXT(
    sType: sType,
    pNext: pNext,
    enabledValidationFeatureCount: len(enabledValidationFeatures).uint32,
    pEnabledValidationFeatures:
      if len(enabledValidationFeatures) == 0:
        nil
      else:
        cast[ptr VkValidationFeatureEnableEXT](enabledValidationFeatures),
    disabledValidationFeatureCount: len(disabledValidationFeatures).uint32,
    pDisabledValidationFeatures:
      if len(disabledValidationFeatures) == 0:
        nil
      else:
        cast[ptr VkValidationFeatureDisableEXT](disabledValidationFeatures),
  )

proc newVkViewport*(
    x: float32,
    y: float32,
    width: float32,
    height: float32,
    minDepth: float32,
    maxDepth: float32,
): VkViewport =
  result = VkViewport(
    x: x, y: y, width: width, height: height, minDepth: minDepth, maxDepth: maxDepth
  )

proc newVkWaylandSurfaceCreateInfoKHR*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
    pNext: pointer = nil,
    flags: VkWaylandSurfaceCreateFlagsKHR = 0.VkWaylandSurfaceCreateFlagsKHR,
    display: ptr wl_display,
    surface: ptr wl_surface,
): VkWaylandSurfaceCreateInfoKHR =
  result = VkWaylandSurfaceCreateInfoKHR(
    sType: sType, pNext: pNext, flags: flags, display: display, surface: surface
  )

proc newVkWriteDescriptorSet*(
    sType: VkStructureType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    pNext: pointer = nil,
    dstSet: VkDescriptorSet,
    dstBinding: uint32,
    dstArrayElement: uint32,
    descriptorCount: uint32,
    descriptorType: VkDescriptorType,
    pImageInfo: ptr VkDescriptorImageInfo,
    pBufferInfo: ptr VkDescriptorBufferInfo,
    pTexelBufferView: ptr VkBufferView,
): VkWriteDescriptorSet =
  result = VkWriteDescriptorSet(
    sType: sType,
    pNext: pNext,
    dstSet: dstSet,
    dstBinding: dstBinding,
    dstArrayElement: dstArrayElement,
    descriptorCount: descriptorCount,
    descriptorType: descriptorType,
    pImageInfo: pImageInfo,
    pBufferInfo: pBufferInfo,
    pTexelBufferView: pTexelBufferView,
  )
