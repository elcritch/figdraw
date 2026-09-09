## Context-owned Vulkan entry points. No process-global dispatch is changed.
## Convenience overloads are adapted from planetis-m/vulkan's wrapper.nim.

# MIT License
#
# Copyright (c) 2019 Leonardo Mariscal
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import pkg/vulkan
import pkg/vulkan/wrapper except checkVkResult
export wrapper except checkVkResult

template checkVkResult*(call: untyped) =
  # Allocation/submission failures must remain checked in danger builds too.
  let status = call
  if status != VkSuccess:
    raiseVkError(astToStr(call) & " returned " & $status, status)

const VulkanDynLib* =
  when defined(windows):
    "vulkan-1.dll"
  elif defined(macosx):
    "libMoltenVK.dylib"
  else:
    "libvulkan.so.1"

proc vkGetInstanceProcAddrNative*(
  instance: VkInstance, pName: cstring
): pointer {.stdcall, dynlib: VulkanDynLib, importc: "vkGetInstanceProcAddr".}

type VulkanDispatch* = ref object
  vkAcquireNextImageKHR*: typeof(vkAcquireNextImageKHR)
  vkAllocateCommandBuffers*: typeof(vkAllocateCommandBuffers)
  vkAllocateDescriptorSets*: typeof(vkAllocateDescriptorSets)
  vkAllocateMemory*: typeof(vkAllocateMemory)
  vkBeginCommandBuffer*: typeof(vkBeginCommandBuffer)
  vkBindBufferMemory*: typeof(vkBindBufferMemory)
  vkBindImageMemory*: typeof(vkBindImageMemory)
  vkCmdBeginRenderPass*: typeof(vkCmdBeginRenderPass)
  vkCmdBindDescriptorSets*: typeof(vkCmdBindDescriptorSets)
  vkCmdBindIndexBuffer*: typeof(vkCmdBindIndexBuffer)
  vkCmdBindPipeline*: typeof(vkCmdBindPipeline)
  vkCmdBindVertexBuffers*: typeof(vkCmdBindVertexBuffers)
  vkCmdClearAttachments*: typeof(vkCmdClearAttachments)
  vkCmdCopyBuffer*: typeof(vkCmdCopyBuffer)
  vkCmdCopyBufferToImage*: typeof(vkCmdCopyBufferToImage)
  vkCmdCopyImage*: typeof(vkCmdCopyImage)
  vkCmdCopyImageToBuffer*: typeof(vkCmdCopyImageToBuffer)
  vkCmdDraw*: typeof(vkCmdDraw)
  vkCmdDrawIndexed*: typeof(vkCmdDrawIndexed)
  vkCmdEndRenderPass*: typeof(vkCmdEndRenderPass)
  vkCmdPipelineBarrier*: typeof(vkCmdPipelineBarrier)
  vkCmdSetScissor*: typeof(vkCmdSetScissor)
  vkCmdSetViewport*: typeof(vkCmdSetViewport)
  vkCreateBuffer*: typeof(vkCreateBuffer)
  vkCreateCommandPool*: typeof(vkCreateCommandPool)
  vkCreateDebugUtilsMessengerEXT*: typeof(vkCreateDebugUtilsMessengerEXT)
  vkCreateDescriptorPool*: typeof(vkCreateDescriptorPool)
  vkCreateDescriptorSetLayout*: typeof(vkCreateDescriptorSetLayout)
  vkCreateDevice*: typeof(vkCreateDevice)
  vkCreateFence*: typeof(vkCreateFence)
  vkCreateFramebuffer*: typeof(vkCreateFramebuffer)
  vkCreateGraphicsPipelines*: typeof(vkCreateGraphicsPipelines)
  vkCreateImage*: typeof(vkCreateImage)
  vkCreateImageView*: typeof(vkCreateImageView)
  vkCreateInstance*: typeof(vkCreateInstance)
  vkCreateMetalSurfaceEXT*: typeof(vkCreateMetalSurfaceEXT)
  vkCreatePipelineLayout*: typeof(vkCreatePipelineLayout)
  vkCreateRenderPass*: typeof(vkCreateRenderPass)
  vkCreateSampler*: typeof(vkCreateSampler)
  vkCreateSemaphore*: typeof(vkCreateSemaphore)
  vkCreateShaderModule*: typeof(vkCreateShaderModule)
  vkCreateSwapchainKHR*: typeof(vkCreateSwapchainKHR)
  vkCreateWaylandSurfaceKHR*: typeof(vkCreateWaylandSurfaceKHR)
  vkCreateWin32SurfaceKHR*: typeof(vkCreateWin32SurfaceKHR)
  vkDestroyBuffer*: typeof(vkDestroyBuffer)
  vkDestroyCommandPool*: typeof(vkDestroyCommandPool)
  vkDestroyDebugUtilsMessengerEXT*: typeof(vkDestroyDebugUtilsMessengerEXT)
  vkDestroyDescriptorPool*: typeof(vkDestroyDescriptorPool)
  vkDestroyDescriptorSetLayout*: typeof(vkDestroyDescriptorSetLayout)
  vkDestroyDevice*: typeof(vkDestroyDevice)
  vkDestroyFence*: typeof(vkDestroyFence)
  vkDestroyFramebuffer*: typeof(vkDestroyFramebuffer)
  vkDestroyImage*: typeof(vkDestroyImage)
  vkDestroyImageView*: typeof(vkDestroyImageView)
  vkDestroyInstance*: typeof(vkDestroyInstance)
  vkDestroyPipeline*: typeof(vkDestroyPipeline)
  vkDestroyPipelineLayout*: typeof(vkDestroyPipelineLayout)
  vkDestroyRenderPass*: typeof(vkDestroyRenderPass)
  vkDestroySampler*: typeof(vkDestroySampler)
  vkDestroySemaphore*: typeof(vkDestroySemaphore)
  vkDestroyShaderModule*: typeof(vkDestroyShaderModule)
  vkDestroySurfaceKHR*: typeof(vkDestroySurfaceKHR)
  vkDestroySwapchainKHR*: typeof(vkDestroySwapchainKHR)
  vkDeviceWaitIdle*: typeof(vkDeviceWaitIdle)
  vkEndCommandBuffer*: typeof(vkEndCommandBuffer)
  vkEnumerateDeviceExtensionProperties*: typeof(vkEnumerateDeviceExtensionProperties)
  vkEnumerateInstanceExtensionProperties*:
    typeof(vkEnumerateInstanceExtensionProperties)
  vkEnumerateInstanceLayerProperties*: typeof(vkEnumerateInstanceLayerProperties)
  vkEnumerateInstanceVersion*: typeof(vkEnumerateInstanceVersion)
  vkEnumeratePhysicalDevices*: typeof(vkEnumeratePhysicalDevices)
  vkFreeDescriptorSets*: typeof(vkFreeDescriptorSets)
  vkFreeMemory*: typeof(vkFreeMemory)
  vkGetBufferMemoryRequirements*: typeof(vkGetBufferMemoryRequirements)
  vkGetDeviceQueue*: typeof(vkGetDeviceQueue)
  vkGetImageMemoryRequirements*: typeof(vkGetImageMemoryRequirements)
  vkGetPhysicalDeviceMemoryProperties*: typeof(vkGetPhysicalDeviceMemoryProperties)
  vkGetPhysicalDeviceProperties*: typeof(vkGetPhysicalDeviceProperties)
  vkGetPhysicalDeviceQueueFamilyProperties*:
    typeof(vkGetPhysicalDeviceQueueFamilyProperties)
  vkGetPhysicalDeviceSurfaceCapabilitiesKHR*:
    typeof(vkGetPhysicalDeviceSurfaceCapabilitiesKHR)
  vkGetPhysicalDeviceSurfaceFormatsKHR*: typeof(vkGetPhysicalDeviceSurfaceFormatsKHR)
  vkGetPhysicalDeviceSurfacePresentModesKHR*:
    typeof(vkGetPhysicalDeviceSurfacePresentModesKHR)
  vkGetPhysicalDeviceSurfaceSupportKHR*: typeof(vkGetPhysicalDeviceSurfaceSupportKHR)
  vkGetSwapchainImagesKHR*: typeof(vkGetSwapchainImagesKHR)
  vkMapMemory*: typeof(vkMapMemory)
  vkQueuePresentKHR*: typeof(vkQueuePresentKHR)
  vkQueueSubmit*: typeof(vkQueueSubmit)
  vkResetCommandBuffer*: typeof(vkResetCommandBuffer)
  vkResetDescriptorPool*: typeof(vkResetDescriptorPool)
  vkResetFences*: typeof(vkResetFences)
  vkUnmapMemory*: typeof(vkUnmapMemory)
  vkUpdateDescriptorSets*: typeof(vkUpdateDescriptorSets)
  vkWaitForFences*: typeof(vkWaitForFences)

proc loadInstance*(vk: VulkanDispatch, instance: VkInstance) =
  ## Extension entry points may be nil when their extension is not enabled.
  for name, entry in fieldPairs(vk[]):
    entry = cast[typeof(entry)](vkGetInstanceProcAddrNative(instance, name.cstring))

proc newVulkanDispatch*(): VulkanDispatch =
  result = VulkanDispatch()
  result.loadInstance(VkInstance(0))

proc mapMemory*(
    vk: VulkanDispatch,
    device: VkDevice,
    memory: VkDeviceMemory,
    offset, size: VkDeviceSize,
    flags: VkMemoryMapFlags,
): pointer =
  result = nil
  checkVkResult vk.vkMapMemory(device, memory, offset, size, flags, result.addr)

proc enumerateInstanceLayerProperties*(vk: VulkanDispatch): seq[VkLayerProperties] =
  result = @[]
  var layerCount: uint32 = 0
  var res = VkIncomplete
  while res == VkIncomplete:
    res = vk.vkEnumerateInstanceLayerProperties(layerCount.addr, nil)
    if res == VkSuccess and layerCount > 0:
      result.setLen(layerCount)
      res = vk.vkEnumerateInstanceLayerProperties(layerCount.addr, result[0].addr)
      if res == VkSuccess and layerCount < uint32(result.len):
        result.setLen(layerCount)
    elif res == VkSuccess:
      break
  checkVkResult res

proc createInstance*(
    vk: VulkanDispatch,
    instanceCreateInfo: VkInstanceCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkInstance =
  checkVkResult vk.vkCreateInstance(instanceCreateInfo.addr, allocator, result.addr)

proc enumeratePhysicalDevices*(
    vk: VulkanDispatch, instance: VkInstance
): seq[VkPhysicalDevice] =
  result = @[]
  var physicalDeviceCount: uint32 = 0
  var res = VkIncomplete
  while res == VkIncomplete:
    res = vk.vkEnumeratePhysicalDevices(instance, physicalDeviceCount.addr, nil)
    if res == VkSuccess and physicalDeviceCount > 0:
      result.setLen(physicalDeviceCount)
      res = vk.vkEnumeratePhysicalDevices(
        instance, physicalDeviceCount.addr, result[0].addr
      )
      if res == VkSuccess and physicalDeviceCount < uint32(result.len):
        result.setLen(physicalDeviceCount)
    elif res == VkSuccess:
      break
  checkVkResult res

proc getQueueFamilyProperties*(
    vk: VulkanDispatch, physicalDevice: VkPhysicalDevice
): seq[VkQueueFamilyProperties] =
  result = @[]
  var queueFamilyCount: uint32 = 0
  vk.vkGetPhysicalDeviceQueueFamilyProperties(
    physicalDevice, queueFamilyCount.addr, nil
  )
  result.setLen(queueFamilyCount)
  if queueFamilyCount > 0:
    vk.vkGetPhysicalDeviceQueueFamilyProperties(
      physicalDevice, queueFamilyCount.addr, result[0].addr
    )

proc getPhysicalDeviceMemoryProperties*(
    vk: VulkanDispatch, physicalDevice: VkPhysicalDevice
): VkPhysicalDeviceMemoryProperties =
  vk.vkGetPhysicalDeviceMemoryProperties(physicalDevice, result.addr)

proc getPhysicalDeviceProperties*(
    vk: VulkanDispatch, physicalDevice: VkPhysicalDevice
): VkPhysicalDeviceProperties =
  vk.vkGetPhysicalDeviceProperties(physicalDevice, result.addr)

proc createDevice*(
    vk: VulkanDispatch,
    physicalDevice: VkPhysicalDevice,
    deviceCreateInfo: VkDeviceCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkDevice =
  checkVkResult vk.vkCreateDevice(
    physicalDevice, deviceCreateInfo.addr, allocator, result.addr
  )

proc getDeviceQueue*(
    vk: VulkanDispatch, device: VkDevice, queueFamilyIndex: uint32, queueIndex: uint32
): VkQueue =
  vk.vkGetDeviceQueue(device, queueFamilyIndex, queueIndex, result.addr)

proc createBuffer*(
    vk: VulkanDispatch,
    device: VkDevice,
    bufferCreateInfo: VkBufferCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkBuffer =
  checkVkResult vk.vkCreateBuffer(device, bufferCreateInfo.addr, allocator, result.addr)

proc getBufferMemoryRequirements*(
    vk: VulkanDispatch, device: VkDevice, buffer: VkBuffer
): VkMemoryRequirements =
  vk.vkGetBufferMemoryRequirements(device, buffer, result.addr)

proc allocateMemory*(
    vk: VulkanDispatch,
    device: VkDevice,
    allocateInfo: VkMemoryAllocateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkDeviceMemory =
  checkVkResult vk.vkAllocateMemory(device, allocateInfo.addr, allocator, result.addr)

proc bindBufferMemory*(
    vk: VulkanDispatch,
    device: VkDevice,
    buffer: VkBuffer,
    memory: VkDeviceMemory,
    memoryOffset: VkDeviceSize,
) =
  checkVkResult vk.vkBindBufferMemory(device, buffer, memory, memoryOffset)

proc createDescriptorSetLayout*(
    vk: VulkanDispatch,
    device: VkDevice,
    createInfo: VkDescriptorSetLayoutCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkDescriptorSetLayout =
  checkVkResult vk.vkCreateDescriptorSetLayout(
    device, createInfo.addr, allocator, result.addr
  )

proc createDescriptorPool*(
    vk: VulkanDispatch,
    device: VkDevice,
    createInfo: VkDescriptorPoolCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkDescriptorPool =
  checkVkResult vk.vkCreateDescriptorPool(
    device, createInfo.addr, allocator, result.addr
  )

proc allocateDescriptorSets*(
    vk: VulkanDispatch, device: VkDevice, allocateInfo: VkDescriptorSetAllocateInfo
): VkDescriptorSet =
  var descriptorSet: VkDescriptorSet
  checkVkResult vk.vkAllocateDescriptorSets(
    device, allocateInfo.addr, descriptorSet.addr
  )
  result = descriptorSet

proc updateDescriptorSets*(
    vk: VulkanDispatch,
    device: VkDevice,
    descriptorWrites: openarray[VkWriteDescriptorSet],
    descriptorCopies: openarray[VkCopyDescriptorSet],
) =
  vk.vkUpdateDescriptorSets(
    device,
    descriptorWrites.len.uint32,
    if descriptorWrites.len == 0:
      nil
    else:
      cast[ptr VkWriteDescriptorSet](descriptorWrites),
    descriptorCopies.len.uint32,
    if descriptorCopies.len == 0:
      nil
    else:
      cast[ptr VkCopyDescriptorSet](descriptorCopies),
  )

proc createShaderModule*(
    vk: VulkanDispatch,
    device: VkDevice,
    createInfo: VkShaderModuleCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkShaderModule =
  checkVkResult vk.vkCreateShaderModule(device, createInfo.addr, allocator, result.addr)

proc createPipelineLayout*(
    vk: VulkanDispatch,
    device: VkDevice,
    createInfo: VkPipelineLayoutCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkPipelineLayout =
  checkVkResult vk.vkCreatePipelineLayout(
    device, createInfo.addr, allocator, result.addr
  )

proc createCommandPool*(
    vk: VulkanDispatch,
    device: VkDevice,
    createInfo: VkCommandPoolCreateInfo,
    allocator: ptr VkAllocationCallbacks = nil,
): VkCommandPool =
  checkVkResult vk.vkCreateCommandPool(device, createInfo.addr, allocator, result.addr)

proc allocateCommandBuffers*(
    vk: VulkanDispatch, device: VkDevice, allocateInfo: VkCommandBufferAllocateInfo
): VkCommandBuffer =
  checkVkResult vk.vkAllocateCommandBuffers(device, allocateInfo.addr, result.addr)

proc unmapMemory*(vk: VulkanDispatch, device: VkDevice, memory: VkDeviceMemory) =
  vk.vkUnmapMemory(device, memory)

proc destroyDescriptorPool*(
    vk: VulkanDispatch,
    device: VkDevice,
    descriptorPool: VkDescriptorPool,
    allocator: ptr VkAllocationCallbacks = nil,
) =
  if descriptorPool != 0.VkDescriptorPool:
    vk.vkDestroyDescriptorPool(device, descriptorPool, allocator)

proc destroyDescriptorSetLayout*(
    vk: VulkanDispatch,
    device: VkDevice,
    descriptorSetLayout: VkDescriptorSetLayout,
    allocator: ptr VkAllocationCallbacks = nil,
) =
  if descriptorSetLayout != 0.VkDescriptorSetLayout:
    vk.vkDestroyDescriptorSetLayout(device, descriptorSetLayout, allocator)

proc destroyDevice*(
    vk: VulkanDispatch, device: VkDevice, allocator: ptr VkAllocationCallbacks = nil
) =
  if device != 0.VkDevice:
    vk.vkDestroyDevice(device, allocator)

proc destroyInstance*(
    vk: VulkanDispatch, instance: VkInstance, allocator: ptr VkAllocationCallbacks = nil
) =
  if instance != 0.VkInstance:
    vk.vkDestroyInstance(instance, allocator)

proc destroyShaderModule*(
    vk: VulkanDispatch,
    device: VkDevice,
    shaderModule: VkShaderModule,
    allocator: ptr VkAllocationCallbacks = nil,
) =
  if shaderModule != 0.VkShaderModule:
    vk.vkDestroyShaderModule(device, shaderModule, allocator)
