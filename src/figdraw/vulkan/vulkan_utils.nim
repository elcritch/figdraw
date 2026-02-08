import std/[hashes, math, strformat]

import pkg/chronicles
import pkg/vulkan
import pkg/vulkan/wrapper

import ../commons

logScope:
  scope = "vulkan"

type
  QueueFamilyIndices* = object
    graphicsFamily*: uint32
    graphicsFound*: bool
    presentFamily*: uint32
    presentFound*: bool

  SwapChainSupportDetails* = object
    capabilities*: VkSurfaceCapabilitiesKHR
    formats*: seq[VkSurfaceFormatKHR]
    presentModes*: seq[VkPresentModeKHR]

when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
  type VkXlibSurfaceCreateInfoKHRNative* {.bycopy.} = object
    sType*: VkStructureType
    pNext*: pointer
    flags*: VkXlibSurfaceCreateFlagsKHR
    dpy*: pointer
    window*: culong

  type VkCreateXlibSurfaceKHRNativeProc* = proc(
    instance: VkInstance,
    pCreateInfo: ptr VkXlibSurfaceCreateInfoKHRNative,
    pAllocator: ptr VkAllocationCallbacks,
    pSurface: ptr VkSurfaceKHR,
  ): VkResult {.cdecl.}

  type VkXcbSurfaceCreateInfoKHRNative* {.bycopy.} = object
    sType*: VkStructureType
    pNext*: pointer
    flags*: VkXcbSurfaceCreateFlagsKHR
    connection*: pointer
    window*: uint32

  type VkCreateXcbSurfaceKHRNativeProc* = proc(
    instance: VkInstance,
    pCreateInfo: ptr VkXcbSurfaceCreateInfoKHRNative,
    pAllocator: ptr VkAllocationCallbacks,
    pSurface: ptr VkSurfaceKHR,
  ): VkResult {.cdecl.}

  const VulkanDynLib* =
    when defined(windows):
      "vulkan-1.dll"
    elif defined(macosx):
      "libMoltenVK.dylib"
    else:
      "libvulkan.so.1"

  proc vkGetInstanceProcAddrNative*(
    instance: VkInstance, pName: cstring
  ): pointer {.cdecl, dynlib: VulkanDynLib, importc: "vkGetInstanceProcAddr".}

  proc XGetXCBConnection*(
    display: pointer
  ): pointer {.cdecl, dynlib: "libX11-xcb.so.1", importc.}

proc findGraphicsQueueFamily*(device: VkPhysicalDevice): int =
  let families = getQueueFamilyProperties(device)
  for i, family in families:
    if family.queueCount > 0 and VkQueueFlagBits.GraphicsBit in family.queueFlags:
      return i
  result = -1

proc findPresentQueueFamily*(device: VkPhysicalDevice, surface: VkSurfaceKHR): int =
  let families = getQueueFamilyProperties(device)
  for i, family in families:
    if family.queueCount == 0:
      continue
    var supported: VkBool32
    discard
      vkGetPhysicalDeviceSurfaceSupportKHR(device, i.uint32, surface, supported.addr)
    if supported.ord == VkTrue:
      return i
  result = -1

proc checkDeviceExtensionSupport*(
    physicalDevice: VkPhysicalDevice, requiredExtensions: seq[string]
): bool =
  if requiredExtensions.len == 0:
    return true

  var extCount: uint32
  discard vkEnumerateDeviceExtensionProperties(physicalDevice, nil, extCount.addr, nil)
  if extCount == 0:
    return false

  var availableExts = newSeq[VkExtensionProperties](extCount)
  discard vkEnumerateDeviceExtensionProperties(
    physicalDevice, nil, extCount.addr, availableExts[0].addr
  )

  for required in requiredExtensions:
    var found = false
    for ext in availableExts:
      if $cast[cstring](ext.extensionName.addr) == required:
        found = true
        break
    if not found:
      return false

  result = true

proc querySwapChainSupport*(
    physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR
): SwapChainSupportDetails =
  discard vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    physicalDevice, surface, result.capabilities.addr
  )

  var formatCount: uint32
  discard
    vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, formatCount.addr, nil)
  if formatCount != 0:
    result.formats.setLen(formatCount)
    discard vkGetPhysicalDeviceSurfaceFormatsKHR(
      physicalDevice, surface, formatCount.addr, result.formats[0].addr
    )

  var presentModeCount: uint32
  discard vkGetPhysicalDeviceSurfacePresentModesKHR(
    physicalDevice, surface, presentModeCount.addr, nil
  )
  if presentModeCount != 0:
    result.presentModes.setLen(presentModeCount)
    discard vkGetPhysicalDeviceSurfacePresentModesKHR(
      physicalDevice, surface, presentModeCount.addr, result.presentModes[0].addr
    )

proc chooseSwapSurfaceFormat*(
    availableFormats: seq[VkSurfaceFormatKHR]
): VkSurfaceFormatKHR =
  for format in availableFormats:
    if format.format == VK_FORMAT_B8G8R8A8_UNORM and
        format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
      return format

  for format in availableFormats:
    if format.format == VK_FORMAT_R8G8B8A8_UNORM and
        format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
      return format

  result = availableFormats[0]

proc chooseSwapPresentMode*(
    availablePresentModes: seq[VkPresentModeKHR]
): VkPresentModeKHR =
  for mode in availablePresentModes:
    if mode == VK_PRESENT_MODE_MAILBOX_KHR:
      return mode
  VK_PRESENT_MODE_FIFO_KHR

proc chooseSwapExtent*(
    capabilities: VkSurfaceCapabilitiesKHR, width, height: int32
): VkExtent2D =
  if capabilities.currentExtent.width != 0xFFFFFFFF'u32:
    return capabilities.currentExtent

  result.width = width.uint32
  result.height = height.uint32
  result.width = max(
    capabilities.minImageExtent.width,
    min(capabilities.maxImageExtent.width, result.width),
  )
  result.height = max(
    capabilities.minImageExtent.height,
    min(capabilities.maxImageExtent.height, result.height),
  )

proc findQueueFamilies*(
    physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR, requirePresent: bool
): QueueFamilyIndices =
  let graphics = findGraphicsQueueFamily(physicalDevice)
  if graphics < 0:
    return
  result.graphicsFamily = graphics.uint32
  result.graphicsFound = true

  if requirePresent:
    let present = findPresentQueueFamily(physicalDevice, surface)
    if present < 0:
      return
    result.presentFamily = present.uint32
    result.presentFound = true
  else:
    result.presentFamily = result.graphicsFamily
    result.presentFound = true

proc physicalDeviceName*(physicalDevice: VkPhysicalDevice): string =
  let props = getPhysicalDeviceProperties(physicalDevice)
  $cast[cstring](props.deviceName.addr)

proc vulkanApiVersion*(version: uint32): string =
  &"{vkVersionMajor(version)}.{vkVersionMinor(version)}.{vkVersionPatch(version)}"

proc detectLoaderApiVersion*(): uint32 =
  result = vkApiVersion1_0.uint32
  if vkEnumerateInstanceVersion.isNil:
    debug "vkEnumerateInstanceVersion unavailable; assuming Vulkan 1.0 loader"
    return

  var loaderApi = vkApiVersion1_0.uint32
  let res = vkEnumerateInstanceVersion(loaderApi.addr)
  if res == VkSuccess:
    result = loaderApi
    debug "Detected Vulkan loader API version",
      apiVersion = vulkanApiVersion(loaderApi), rawApiVersion = loaderApi
  else:
    debug "Failed to query Vulkan loader API version",
      result = $res, fallbackApiVersion = vulkanApiVersion(result)

proc queryInstanceExtensionNames*(): seq[string] =
  if vkEnumerateInstanceExtensionProperties.isNil:
    debug "vkEnumerateInstanceExtensionProperties unavailable"
    return @[]

  var count: uint32
  let firstRes = vkEnumerateInstanceExtensionProperties(nil, count.addr, nil)
  if firstRes != VkSuccess:
    debug "Failed to enumerate Vulkan instance extensions (count)", result = $firstRes
    return @[]

  if count == 0:
    return @[]

  var props = newSeq[VkExtensionProperties](count.int)
  let secondRes = vkEnumerateInstanceExtensionProperties(nil, count.addr, props[0].addr)
  if secondRes != VkSuccess:
    debug "Failed to enumerate Vulkan instance extensions (values)", result = $secondRes
    return @[]

  for ext in props:
    result.add($cast[cstring](ext.extensionName.addr))

proc queryInstanceLayerNames*(): seq[string] =
  try:
    for layer in enumerateInstanceLayerProperties():
      result.add($cast[cstring](layer.layerName.addr))
  except VulkanError as exc:
    debug "Failed to enumerate Vulkan instance layers", error = exc.msg
    return @[]

proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

proc toKey*(h: Hash): Hash =
  h

proc findMemoryType*(
    physicalDevice: VkPhysicalDevice,
    typeFilter: uint32,
    properties: VkMemoryPropertyFlags,
): uint32 =
  let memoryProperties = getPhysicalDeviceMemoryProperties(physicalDevice)
  for i in 0 ..< memoryProperties.memoryTypeCount.int:
    let memoryType = memoryProperties.memoryTypes[i]
    if (typeFilter and (1'u32 shl i.uint32)) != 0'u32 and
        memoryType.propertyFlags >= properties:
      return i.uint32
  raise newException(ValueError, "Failed to find Vulkan memory type")
