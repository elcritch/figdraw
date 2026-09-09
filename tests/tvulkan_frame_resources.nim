import std/[unittest, os]
import figdraw/commons

when UseVulkanBackend:
  # Exercise private recording/retirement invariants without a window system.
  include ../src/figdraw/vulkan/vulkan_context

  var copiedBuffer: VkBuffer
  var copiedOffset: VkDeviceSize
  var originalCopy: typeof(vkCmdCopyBufferToImage)

  proc observeCopy(
      cmd: VkCommandBuffer,
      buffer: VkBuffer,
      image: VkImage,
      layout: VkImageLayout,
      count: uint32,
      regions: ptr VkBufferImageCopy,
  ) {.stdcall.} =
    copiedBuffer = buffer
    copiedOffset = regions.bufferOffset
    originalCopy(cmd, buffer, image, layout, count, regions)

  proc captureUpload(ctx: VulkanContext): VulkanBuffer =
    result = ctx.createBuffer(
      4.VkDeviceSize,
      VkBufferUsageFlags{TransferDstBit},
      VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
    )
    var region = VkBufferCopy(srcOffset: copiedOffset, size: 4.VkDeviceSize)
    ctx.vk.vkCmdCopyBuffer(
      ctx.commandBuffer, copiedBuffer, result.handle, 1, region.addr
    )
    var barrier = VkBufferMemoryBarrier(
      sType: VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      srcAccessMask: VkAccessFlags{TransferWriteBit},
      dstAccessMask: VkAccessFlags{HostReadBit},
      srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      buffer: result.handle,
      size: 4.VkDeviceSize,
    )
    ctx.vk.vkCmdPipelineBarrier(
      ctx.commandBuffer,
      VkPipelineStageFlags{TransferBit},
      VkPipelineStageFlags{HostBit},
      0.VkDependencyFlags,
      0,
      nil,
      1,
      barrier.addr,
      0,
      nil,
    )

  proc readPixel(ctx: VulkanContext, buffer: VulkanBuffer): array[4, uint8] =
    let mapped = ctx.vk.mapMemory(
      ctx.device, buffer.allocation, 0.VkDeviceSize, 4.VkDeviceSize, 0.VkMemoryMapFlags
    )
    copyMem(result.addr, mapped, 4)
    ctx.vk.unmapMemory(ctx.device, buffer.allocation)

  suite "Vulkan atlas packing":
    test "Vulkan failures remain exceptions in every build mode":
      expect VulkanError:
        checkVkResult VkErrorOutOfHostMemory

    test "exact width fits and growth preserves existing images":
      let ctx = newContext(atlasSize = 64, maxQuads = 8)
      let red = newImage(56, 8)
      red.fill(rgba(255, 0, 0, 255))
      ctx.putImage(1.Hash, red)
      check ctx.atlasSize == 64
      let before = ctx.entries[1.Hash]
      ctx.putImage(2.Hash, newImage(80, 8))
      check ctx.atlasSize == 128
      check ctx.hasImage(1.Hash)
      check ctx.entries[1.Hash] == before / 2.0'f32
      check ctx.atlasPixels[4, 4] == rgba(255, 0, 0, 255).rgbx
      let sizeBefore = ctx.atlasSize
      expect ValueError:
        ctx.resetImageAtlas(high(int))
      check ctx.atlasSize == sizeBefore
      check ctx.hasImage(1.Hash)

  suite "Vulkan frame resources":
    test "uploads, uniforms, descriptors and retired atlases remain independent":
      let ctx = newContext(atlasSize = 64, maxQuads = 8)
      defer:
        ctx.destroyGpu()
        check ctx.validationErrorCount() == 0
      var available = true
      try:
        ctx.ensureGpuRuntime()
      except CatchableError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        available = false
      if not available:
        skip()
      else:
        let globalSubmit = vkQueueSubmit
        let beginInfo = newVkCommandBufferBeginInfo(pInheritanceInfo = nil)
        checkVkResult ctx.vk.vkBeginCommandBuffer(ctx.commandBuffer, beginInfo.addr)
        ctx.commandRecording = true
        originalCopy = ctx.vk.vkCmdCopyBufferToImage
        ctx.vk.vkCmdCopyBufferToImage = observeCopy
        ctx.atlasPixels.fill(rgba(255, 0, 0, 255))
        ctx.recordAtlasUpload(ctx.commandBuffer)
        var first = ctx.captureUpload()
        ctx.atlasPixels.fill(rgba(0, 0, 255, 255))
        ctx.recordAtlasUpload(ctx.commandBuffer)
        var second = ctx.captureUpload()
        ctx.vk.vkCmdCopyBufferToImage = originalCopy

        let blurA = ctx.writeBlurUniforms(vec2(0.01'f32, 0), 2.0'f32)
        let blurB = ctx.writeBlurUniforms(vec2(0.01'f32, 0), 12.0'f32)
        check cast[ptr BlurUniforms](blurA.data).blurRadius == 2.0'f32
        check cast[ptr BlurUniforms](blurB.data).blurRadius == 12.0'f32
        check blurA.offset.uint64 mod ctx.uniformAlignment.uint64 == 0
        check blurB.offset.uint64 mod ctx.uniformAlignment.uint64 == 0
        let descriptorA = ctx.allocateFrameDescriptorSet(ctx.descriptorSetLayout)
        let descriptorB = ctx.allocateFrameDescriptorSet(ctx.descriptorSetLayout)
        check descriptorA != descriptorB
        # Cross a descriptor-pool boundary as a real heavily clipped frame would.
        for i in 0 ..< 140:
          discard ctx.allocateFrameDescriptorSet(ctx.descriptorSetLayout)
        check ctx.frameDescriptorPools.len == 2

        let oldImage = ctx.atlasImage.handle
        ctx.resetImageAtlas(128)
        check ctx.atlasImage.handle != oldImage
        check ctx.frameImages.len == 1
        check ctx.frameImages[0].handle == oldImage
        # All earlier atlas upload commands must still be executable.
        checkVkResult ctx.vk.vkEndCommandBuffer(ctx.commandBuffer)
        let submitInfo = newVkSubmitInfo(
          waitSemaphores = [],
          waitDstStageMask = [],
          commandBuffers = [ctx.commandBuffer],
          signalSemaphores = [],
        )
        checkVkResult ctx.vk.vkResetFences(ctx.device, 1, ctx.inFlightFence.addr)
        checkVkResult ctx.vk.vkQueueSubmit(
          ctx.queue, 1, submitInfo.addr, ctx.inFlightFence
        )
        checkVkResult ctx.vk.vkWaitForFences(
          ctx.device, 1, ctx.inFlightFence.addr, VkBool32(VkTrue), high(uint64)
        )
        check ctx.readPixel(first) == [255'u8, 0, 0, 255]
        check ctx.readPixel(second) == [0'u8, 0, 255, 255]
        first = nil
        second = nil
        ctx.commandRecording = false
        ctx.recycleFrameResources()
        check ctx.frameImages.len == 0
        check ctx.uploadBlocks[0].used == 0.VkDeviceSize
        check ctx.descriptorSetsUsed == 0

        let parentSubmit = ctx.vk.vkQueueSubmit
        let popup = newContext(atlasSize = 32, maxQuads = 8)
        popup.ensureGpuRuntime()
        check popup.instance != ctx.instance
        check popup.device != ctx.device
        check popup.vk != ctx.vk
        popup.destroyGpu()
        check ctx.vk.vkQueueSubmit == parentSubmit
        check vkQueueSubmit == globalSubmit
        checkVkResult ctx.vk.vkDeviceWaitIdle(ctx.device)
else:
  suite "Vulkan frame resources":
    test "Vulkan backend not enabled":
      skip()
