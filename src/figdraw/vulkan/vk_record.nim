## Vulkan readback helpers shared by `vulkan_context.nim`.
##
## These are templates so they expand inside `vulkan_context` and can access
## that module's private context fields, constants, and helper imports.

template vkRecordEnsureReadbackBuffer*(ctx: untyped, bytes: untyped) =
  if ctx.gpu.readback.isInitialized() and ctx.gpu.readbackBytes >= bytes:
    return

  ctx.gpu.readback.reset()

  var alloc = initGpuBuffer(
    device = ctx.gpu.device,
    physicalDevice = ctx.gpu.physicalDevice,
    size = bytes,
    usage = VkBufferUsageFlags{TransferDstBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.gpu.readback.reset(alloc.release())
  ctx.gpu.readbackBytes = bytes

template vkRecordSwapchainReadback*(ctx: untyped) =
  if not ctx.gpu.swapchainTransferSrcSupported:
    return
  if ctx.gpu.swapchainImages.len == 0:
    return

  let width = int32(ctx.gpu.swapchainExtent.width)
  let height = int32(ctx.gpu.swapchainExtent.height)
  if width <= 0 or height <= 0:
    return

  let readbackBytes = VkDeviceSize(width * height * 4)
  ctx.ensureReadbackBuffer(readbackBytes)

  let swapchainImage = ctx.gpu.swapchainImages[ctx.gpu.acquiredImageIndex.int]
  var imageToTransfer = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
    dstAccessMask: VkAccessFlags{TransferReadBit},
    oldLayout: VkImageLayout.PresentSrcKhr,
    newLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: swapchainImage,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  vkCmdPipelineBarrier(
    ctx.gpu.commandBuffer,
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    VkPipelineStageFlags{TransferBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    imageToTransfer.addr,
  )

  var copyRegion = VkBufferImageCopy(
    bufferOffset: 0.VkDeviceSize,
    bufferRowLength: 0,
    bufferImageHeight: 0,
    imageSubresource: newVkImageSubresourceLayers(
      aspectMask = VkImageAspectFlags{ColorBit},
      mipLevel = 0,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
    imageOffset: newVkOffset3D(x = 0, y = 0, z = 0),
    imageExtent: newVkExtent3D(
      width = ctx.gpu.swapchainExtent.width,
      height = ctx.gpu.swapchainExtent.height,
      depth = 1,
    ),
  )
  vkCmdCopyImageToBuffer(
    ctx.gpu.commandBuffer,
    swapchainImage,
    VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    ctx.gpu.readback[].buffer,
    1,
    copyRegion.addr,
  )

  var readbackBarrier = VkBufferMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{TransferWriteBit},
    dstAccessMask: VkAccessFlags{HostReadBit},
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    buffer: ctx.gpu.readback[].buffer,
    offset: 0.VkDeviceSize,
    size: readbackBytes,
  )
  vkCmdPipelineBarrier(
    ctx.gpu.commandBuffer,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{HostBit},
    0.VkDependencyFlags,
    0,
    nil,
    1,
    readbackBarrier.addr,
    0,
    nil,
  )

  var imageToPresent = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{TransferReadBit},
    dstAccessMask: 0.VkAccessFlags,
    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    newLayout: VkImageLayout.PresentSrcKhr,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: swapchainImage,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  vkCmdPipelineBarrier(
    ctx.gpu.commandBuffer,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{BottomOfPipeBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    imageToPresent.addr,
  )

  ctx.gpu.readbackWidth = width
  ctx.gpu.readbackHeight = height
  ctx.gpu.readbackReady = true

template vkReadPixels*(ctx: untyped, frame: untyped, readFront: untyped): untyped =
  when not UseVulkanReadback:
    discard readFront
    raise newException(
      ValueError,
      "Vulkan readPixels is disabled; build with -d:figdraw.vulkanReadback=on",
    )
  else:
    discard readFront
    if not ctx.gpu.gpuReady:
      raise newException(ValueError, "Vulkan context is not initialized")
    if not ctx.gpu.readback.isInitialized() or not ctx.gpu.readbackReady:
      raise newException(ValueError, "No Vulkan frame has been rendered yet")
    if ctx.gpu.readbackWidth <= 0 or ctx.gpu.readbackHeight <= 0:
      raise newException(ValueError, "Vulkan readback dimensions are invalid")

    checkVkResult vkWaitForFences(
      ctx.gpu.device, 1, ctx.gpu.inFlightFence.addr, VkBool32(VkTrue), high(uint64)
    )

    let texW = ctx.gpu.readbackWidth.int
    let texH = ctx.gpu.readbackHeight.int

    var x = frame.x.int
    var y = frame.y.int
    var w = frame.w.int
    var h = frame.h.int
    if w <= 0 or h <= 0:
      x = 0
      y = 0
      w = texW
      h = texH

    x = clamp(x, 0, texW)
    y = clamp(y, 0, texH)
    w = clamp(w, 0, texW - x)
    h = clamp(h, 0, texH - y)

    if w <= 0 or h <= 0:
      result = newImage(1, 1)
      return

    let mapped = cast[ptr UncheckedArray[uint8]](mapMemory(
      ctx.gpu.device,
      ctx.gpu.readback[].memory,
      0.VkDeviceSize,
      ctx.gpu.readbackBytes,
      0.VkMemoryMapFlags,
    ))
    if mapped.isNil:
      raise newException(ValueError, "Failed to map Vulkan readback memory")
    defer:
      unmapMemory(ctx.gpu.device, ctx.gpu.readback[].memory)

    result = newImage(w, h)
    let stride = texW * 4
    let bgrFormat =
      case ctx.gpu.swapchainFormat
      of VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_B8G8R8A8_SRGB: true
      else: false

    for row in 0 ..< h:
      let srcRow = y + row
      var src = srcRow * stride + x * 4
      for col in 0 ..< w:
        let dst = row * w + col
        let b = mapped[src + 0]
        let g = mapped[src + 1]
        let r = mapped[src + 2]
        let a = mapped[src + 3]
        if bgrFormat:
          result.data[dst] = rgbx(r, g, b, a)
        else:
          result.data[dst] = rgbx(b, g, r, a)
        src += 4
