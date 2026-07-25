import std/unittest

import figdraw/commons

when UseVulkanBackend:
  import pkg/vulkan
  import figdraw/vulkan/vulkan_utils

  proc surfaceSupport(
      minImages = 2'u32,
      maxImages = 0'u32,
      usage = VkImageUsageFlags{ColorAttachmentBit, TransferSrcBit},
  ): SwapChainSupportDetails =
    SwapChainSupportDetails(
      capabilities: VkSurfaceCapabilitiesKHR(
        minImageCount: minImages,
        maxImageCount: maxImages,
        currentExtent: newVkExtent2D(width = 0xFFFFFFFF'u32, height = 0xFFFFFFFF'u32),
        minImageExtent: newVkExtent2D(width = 16, height = 16),
        maxImageExtent: newVkExtent2D(width = 4096, height = 4096),
        supportedCompositeAlpha: VkCompositeAlphaFlagsKHR{OpaqueBit, PreMultipliedBit},
        supportedUsageFlags: usage,
      ),
      formats: @[
        VkSurfaceFormatKHR(
          format: VK_FORMAT_B8G8R8A8_UNORM,
          colorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        )
      ],
      presentModes: @[VK_PRESENT_MODE_FIFO_KHR, VK_PRESENT_MODE_MAILBOX_KHR],
    )

  suite "vulkan swapchain configuration":
    test "auto profile adapts to software drivers":
      let software = VulkanDriverInfo(
        deviceName: "llvmpipe (LLVM 19.1.7)", deviceType: VK_PHYSICAL_DEVICE_TYPE_CPU
      )
      let hardware = VulkanDriverInfo(
        deviceName: "Example Discrete GPU",
        deviceType: VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU,
      )

      check chooseSwapchainProfile(vspAuto, software) == vspCompatibility
      check chooseSwapchainProfile(vspAuto, hardware) == vspLowLatency
      check chooseSwapchainProfile(vspThroughput, software) == vspThroughput

    test "compatibility profile uses mandatory FIFO and minimum image count":
      let support = surfaceSupport()
      let driver = VulkanDriverInfo(
        deviceName: "Example GPU", deviceType: VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
      )

      let config = chooseSwapchainConfig(support, 800, 600, vspCompatibility, driver)

      check config.profile == vspCompatibility
      check config.presentMode == VK_PRESENT_MODE_FIFO_KHR
      check config.imageCount == 2
      check config.extent.width == 800
      check config.extent.height == 600
      check config.transferSrcEnabled
      check TransferSrcBit in config.imageUsage

    test "throughput profile clamps image count to the surface maximum":
      let support = surfaceSupport(minImages = 2, maxImages = 3)
      let driver = VulkanDriverInfo(
        deviceName: "Example GPU", deviceType: VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
      )

      let config = chooseSwapchainConfig(support, 800, 600, vspThroughput, driver)

      check config.profile == vspThroughput
      check config.presentMode == VK_PRESENT_MODE_MAILBOX_KHR
      check config.imageCount == 3

    test "custom preferences select supported format and present mode":
      var support = surfaceSupport(usage = VkImageUsageFlags{ColorAttachmentBit})
      support.formats = @[
        VkSurfaceFormatKHR(
          format: VK_FORMAT_UNDEFINED, colorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
        )
      ]
      support.presentModes.add(VK_PRESENT_MODE_IMMEDIATE_KHR)
      var preferences = swapchainPreferences(vspCompatibility)
      preferences.preferredFormats = @[
        VkSurfaceFormatKHR(
          format: VK_FORMAT_R8G8B8A8_UNORM,
          colorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        )
      ]
      preferences.preferredPresentModes = @[VK_PRESENT_MODE_IMMEDIATE_KHR]
      preferences.extraImageCount = 1

      let config =
        chooseSwapchainConfig(support, 800, 600, preferences, vspCompatibility)

      check config.surfaceFormat.format == VK_FORMAT_R8G8B8A8_UNORM
      check config.presentMode == VK_PRESENT_MODE_IMMEDIATE_KHR
      check config.imageCount == 3
      check not config.transferSrcEnabled
      check TransferSrcBit notin config.imageUsage
else:
  suite "vulkan swapchain configuration":
    test "vulkan backend not enabled":
      check true
