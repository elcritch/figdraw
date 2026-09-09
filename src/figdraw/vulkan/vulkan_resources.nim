## Destructor-backed owners for Vulkan resources with bound device memory.
##
## These owners deliberately store the logical device handle rather than the
## whole renderer context. A context must therefore drop all owners before it
## destroys the device.

import pkg/vulkan
import ./vulkan_dispatch

type
  VulkanBufferObj = object
    vk: VulkanDispatch
    device: VkDevice
    handle*: VkBuffer
    allocation*: VkDeviceMemory
    size*: VkDeviceSize
    mapped*: pointer

  VulkanBuffer* = ref VulkanBufferObj ## Owns a buffer and the device memory bound to it.

  VulkanImageObj = object
    vk: VulkanDispatch
    device: VkDevice
    handle*: VkImage
    allocation*: VkDeviceMemory
    view*: VkImageView

  VulkanImage* = ref VulkanImageObj
    ## Owns an image, its bound memory, and its default image view.

type
  VulkanUpload* = object
    buffer*: VulkanBuffer
    offset*, size*: VkDeviceSize
    data*: pointer

  VulkanUploadBlock* = object
    buffer*: VulkanBuffer
    used*: VkDeviceSize

const
  vkNullDevice = VkDevice(0)
  vkNullBuffer = VkBuffer(0)
  vkNullImage = VkImage(0)
  vkNullImageView = VkImageView(0)
  vkNullMemory = VkDeviceMemory(0)

proc close*(buffer: var VulkanBufferObj) {.raises: [].} =
  # The generated Vulkan proc variables lack effect annotations, but these C
  # destruction entry points cannot raise Nim exceptions.
  {.cast(raises: []).}:
    if buffer.device != vkNullDevice:
      if buffer.mapped != nil:
        buffer.vk.vkUnmapMemory(buffer.device, buffer.allocation)
        buffer.mapped = nil
      if buffer.handle != vkNullBuffer:
        buffer.vk.vkDestroyBuffer(buffer.device, buffer.handle, nil)
      if buffer.allocation != vkNullMemory:
        buffer.vk.vkFreeMemory(buffer.device, buffer.allocation, nil)
  buffer.handle = vkNullBuffer
  buffer.allocation = vkNullMemory
  buffer.size = 0.VkDeviceSize
  buffer.device = vkNullDevice

proc close*(image: var VulkanImageObj) {.raises: [].} =
  # The generated Vulkan proc variables lack effect annotations, but these C
  # destruction entry points cannot raise Nim exceptions.
  {.cast(raises: []).}:
    if image.device != vkNullDevice:
      if image.view != vkNullImageView:
        image.vk.vkDestroyImageView(image.device, image.view, nil)
      if image.handle != vkNullImage:
        image.vk.vkDestroyImage(image.device, image.handle, nil)
      if image.allocation != vkNullMemory:
        image.vk.vkFreeMemory(image.device, image.allocation, nil)
  image.view = vkNullImageView
  image.handle = vkNullImage
  image.allocation = vkNullMemory
  image.device = vkNullDevice

proc `=destroy`(buffer: var VulkanBufferObj) =
  buffer.close()

proc `=destroy`(image: var VulkanImageObj) =
  image.close()

proc newVulkanBuffer*(
    vk: VulkanDispatch, device: VkDevice, size: VkDeviceSize
): VulkanBuffer =
  VulkanBuffer(vk: vk, device: device, size: size)

proc newVulkanImage*(vk: VulkanDispatch, device: VkDevice): VulkanImage =
  VulkanImage(vk: vk, device: device)

func isNilOrEmpty*(buffer: VulkanBuffer): bool =
  buffer.isNil or buffer.handle == vkNullBuffer

func isNilOrEmpty*(image: VulkanImage): bool =
  image.isNil or image.handle == vkNullImage
