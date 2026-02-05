import std/[hashes, math, strformat, tables]

import pkg/chroma
import pkg/chronicles
import pkg/pixie as px
import pkg/vulkan
import pkg/vulkan/wrapper

import ../commons
import ../common/formatflippy
import ../fignodes
import ../utils/drawextras

export drawextras

logScope:
  scope = "vulkan"

proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

const
  quadLimit = 10_921
  frameCopyCompSpv = staticRead("shaders/frame_copy.comp.spv")

type SdfMode* {.pure.} = enum
  ## Subset of `sdfy/sdfytypes.SDFMode` with stable numeric values.
  sdfModeAtlas = 0
  sdfModeClipAA = 3
  sdfModeDropShadow = 7
  sdfModeDropShadowAA = 8
  sdfModeInsetShadow = 9
  sdfModeInsetShadowAnnular = 10
  sdfModeAnnular = 11
  sdfModeAnnularAA = 12
  sdfModeMsdf = 13
  sdfModeMtsdf = 14
  sdfModeMsdfAnnular = 15
  sdfModeMtsdfAnnular = 16

type PresentTargetKind = enum
  presentTargetNone
  presentTargetXlib
  presentTargetWin32
  presentTargetMetal

when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
  type VkXlibSurfaceCreateInfoKHRNative {.bycopy.} = object
    sType: VkStructureType
    pNext: pointer
    flags: VkXlibSurfaceCreateFlagsKHR
    dpy: pointer
    window: culong

  type VkCreateXlibSurfaceKHRNativeProc = proc(
      instance: VkInstance,
      pCreateInfo: ptr VkXlibSurfaceCreateInfoKHRNative,
      pAllocator: ptr VkAllocationCallbacks,
      pSurface: ptr VkSurfaceKHR,
  ): VkResult {.stdcall.}

  const VulkanDynLib =
    when defined(windows):
      "vulkan-1.dll"
    elif defined(macosx):
      "libMoltenVK.dylib"
    else:
      "libvulkan.so.1"

  proc vkGetInstanceProcAddrNative(
      instance: VkInstance, pName: cstring
  ): pointer {.cdecl, dynlib: VulkanDynLib, importc: "vkGetInstanceProcAddr".}

type QueueFamilyIndices = object
  graphicsFamily: uint32
  graphicsFound: bool
  presentFamily: uint32
  presentFound: bool

type SwapChainSupportDetails = object
  capabilities: VkSurfaceCapabilitiesKHR
  formats: seq[VkSurfaceFormatKHR]
  presentModes: seq[VkPresentModeKHR]

type Context* = ref object
  atlasSize: int
  atlasMargin: int
  maxQuads: int
  mat*: Mat4
  mats: seq[Mat4]
  entries*: Table[Hash, Rect]
  images: Table[Hash, px.Image]
  proj*: Mat4
  frameSize: Vec2
  frameBegun, maskBegun: bool
  maskDepth: int
  pixelate*: bool
  pixelScale*: float32
  aaFactor: float32

  canvas: px.Image
  drawCtx: px.Context
  lastFrame: px.Image

  instance: VkInstance
  physicalDevice: VkPhysicalDevice
  device: VkDevice
  queue: VkQueue
  queueFamily: uint32
  presentQueue: VkQueue
  presentQueueFamily: uint32
  commandPool: VkCommandPool

  descriptorSetLayout: VkDescriptorSetLayout
  descriptorPool: VkDescriptorPool
  descriptorSet: VkDescriptorSet
  pipelineLayout: VkPipelineLayout
  pipeline: VkPipeline
  shaderModule: VkShaderModule

  inBuffer: VkBuffer
  outBuffer: VkBuffer
  inMemory: VkDeviceMemory
  outMemory: VkDeviceMemory
  bufferBytes: VkDeviceSize

  presentTargetKind: PresentTargetKind
  presentXlibDisplay: pointer
  presentXlibWindow: uint64
  presentWin32Hinstance: pointer
  presentWin32Hwnd: pointer
  presentMetalLayer: pointer

  surface: VkSurfaceKHR
  swapchain: VkSwapchainKHR
  swapchainImages: seq[VkImage]
  swapchainFormat: VkFormat
  swapchainExtent: VkExtent2D
  swapchainOutOfDate: bool
  presentReady: bool
  presentFrameCount: uint64

  imageAvailableSemaphore: VkSemaphore
  renderFinishedSemaphore: VkSemaphore
  inFlightFence: VkFence
  presentCommandBuffer: VkCommandBuffer

  uploadBuffer: VkBuffer
  uploadMemory: VkDeviceMemory
  uploadBytes: VkDeviceSize

  gpuReady: bool

const
  vkNullInstance = VkInstance(0)
  vkNullPhysicalDevice = VkPhysicalDevice(0)
  vkNullDevice = VkDevice(0)
  vkNullQueue = VkQueue(0)
  vkNullCommandPool = VkCommandPool(0)
  vkNullCommandBuffer = VkCommandBuffer(0)
  vkNullSurface = VkSurfaceKHR(0)
  vkNullSwapchain = VkSwapchainKHR(0)
  vkNullSemaphore = VkSemaphore(0)
  vkNullFence = VkFence(0)
  vkNullBuffer = VkBuffer(0)
  vkNullMemory = VkDeviceMemory(0)
  vkNullDescriptorSetLayout = VkDescriptorSetLayout(0)
  vkNullDescriptorPool = VkDescriptorPool(0)
  vkNullDescriptorSet = VkDescriptorSet(0)
  vkNullPipelineLayout = VkPipelineLayout(0)
  vkNullPipeline = VkPipeline(0)
  vkNullShaderModule = VkShaderModule(0)

proc toKey*(h: Hash): Hash =
  h

proc hasImage*(ctx: Context, key: Hash): bool =
  key in ctx.entries

proc destroyGpu(ctx: Context)
proc createSwapchain(ctx: Context, width, height: int32)
proc ensureSwapchain(ctx: Context, width, height: int32)
proc presentFrame(ctx: Context)

proc hasPresentTarget(ctx: Context): bool =
  ctx.presentTargetKind != presentTargetNone

proc instanceExtensions(ctx: Context): seq[cstring] =
  if not ctx.hasPresentTarget():
    return @[]

  result = @[VkKhrSurfaceExtensionName.cstring]
  case ctx.presentTargetKind
  of presentTargetXlib:
    result.add(VkKhrXlibSurfaceExtensionName.cstring)
  of presentTargetWin32:
    result.add(VkKhrWin32SurfaceExtensionName.cstring)
  of presentTargetMetal:
    result.add(VkExtMetalSurfaceExtensionName.cstring)
  of presentTargetNone:
    discard

proc findGraphicsQueueFamily(device: VkPhysicalDevice): int =
  let families = getQueueFamilyProperties(device)

  for i, family in families:
    if family.queueCount > 0 and VkQueueFlagBits.GraphicsBit in family.queueFlags and
        VkQueueFlagBits.ComputeBit in family.queueFlags:
      return i

  for i, family in families:
    if family.queueCount > 0 and VkQueueFlagBits.GraphicsBit in family.queueFlags:
      return i

  for i, family in families:
    if family.queueCount > 0 and VkQueueFlagBits.ComputeBit in family.queueFlags:
      return i

  result = -1

proc findPresentQueueFamily(device: VkPhysicalDevice, surface: VkSurfaceKHR): int =
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

proc checkDeviceExtensionSupport(
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

proc querySwapChainSupport(
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

proc chooseSwapSurfaceFormat(
    availableFormats: seq[VkSurfaceFormatKHR]
): VkSurfaceFormatKHR =
  for format in availableFormats:
    if format.format == VK_FORMAT_R8G8B8A8_UNORM and
        format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
      return format

  for format in availableFormats:
    if format.format == VK_FORMAT_B8G8R8A8_UNORM and
        format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
      return format

  result = availableFormats[0]

proc chooseSwapPresentMode(
    availablePresentModes: seq[VkPresentModeKHR]
): VkPresentModeKHR =
  for mode in availablePresentModes:
    if mode == VK_PRESENT_MODE_MAILBOX_KHR:
      return mode
  VK_PRESENT_MODE_FIFO_KHR

proc chooseSwapExtent(
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

proc findQueueFamilies(
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

proc physicalDeviceName(physicalDevice: VkPhysicalDevice): string =
  let props = getPhysicalDeviceProperties(physicalDevice)
  $cast[cstring](props.deviceName.addr)

proc swizzleRgbaToBgra(dst, src: ptr uint8, byteCount: int) =
  let srcArr = cast[ptr UncheckedArray[uint8]](src)
  let dstArr = cast[ptr UncheckedArray[uint8]](dst)
  var i = 0
  while i + 3 < byteCount:
    dstArr[i + 0] = srcArr[i + 2]
    dstArr[i + 1] = srcArr[i + 1]
    dstArr[i + 2] = srcArr[i + 0]
    dstArr[i + 3] = srcArr[i + 3]
    i += 4

proc createPresentSurface(ctx: Context) =
  if not ctx.hasPresentTarget() or ctx.instance == vkNullInstance:
    return
  if ctx.surface != vkNullSurface:
    return

  case ctx.presentTargetKind
  of presentTargetXlib:
    when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
      let fnPtr = vkGetInstanceProcAddrNative(ctx.instance, "vkCreateXlibSurfaceKHR")
      if fnPtr.isNil:
        raise newException(
          ValueError, "vkCreateXlibSurfaceKHR is unavailable on this Vulkan loader"
        )
      let vkCreateXlibSurfaceKHRNative = cast[VkCreateXlibSurfaceKHRNativeProc](fnPtr)
      var createInfo = VkXlibSurfaceCreateInfoKHRNative(
        sType: VkStructureType.XlibSurfaceCreateInfoKHR,
        pNext: nil,
        flags: 0.VkXlibSurfaceCreateFlagsKHR,
        dpy: ctx.presentXlibDisplay,
        window: culong(ctx.presentXlibWindow),
      )
      checkVkResult vkCreateXlibSurfaceKHRNative(
        ctx.instance, createInfo.addr, nil, ctx.surface.addr
      )
    else:
      raise newException(ValueError, "Xlib Vulkan surface is unsupported on this OS")
  of presentTargetWin32:
    when defined(windows):
      loadVK_KHR_win32_surface()
      let createInfo = newVkWin32SurfaceCreateInfoKHR(
        hinstance = cast[HINSTANCE](ctx.presentWin32Hinstance),
        hwnd = cast[HWND](ctx.presentWin32Hwnd),
      )
      checkVkResult vkCreateWin32SurfaceKHR(
        ctx.instance, createInfo.addr, nil, ctx.surface.addr
      )
    else:
      raise newException(ValueError, "Win32 Vulkan surface is unsupported on this OS")
  of presentTargetMetal:
    when defined(macosx):
      loadVK_EXT_metal_surface()
      let createInfo = newVkMetalSurfaceCreateInfoEXT(
        pLayer = cast[ptr CAMetalLayer](ctx.presentMetalLayer)
      )
      checkVkResult vkCreateMetalSurfaceEXT(
        ctx.instance, createInfo.addr, nil, ctx.surface.addr
      )
    else:
      raise newException(ValueError, "Metal Vulkan surface is unsupported on this OS")
  of presentTargetNone:
    discard

proc colorRgba8(color: Color): px.ColorRGBA =
  color.rgba()

proc resetDrawCtx(ctx: Context, clearMain: bool, clearColor: Color) =
  let w = max(1, ctx.frameSize.x.int)
  let h = max(1, ctx.frameSize.y.int)
  if ctx.canvas.isNil or ctx.canvas.width != w or ctx.canvas.height != h:
    ctx.canvas = px.newImage(w, h)

  if clearMain:
    ctx.canvas.fill(clearColor.colorRgba8)
  else:
    ctx.canvas.fill(px.rgba(0, 0, 0, 0))

  ctx.drawCtx = px.newContext(ctx.canvas)

proc findMemoryType(
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

proc createStorageBuffer(
    ctx: Context, bytes: VkDeviceSize
): tuple[buffer: VkBuffer, memory: VkDeviceMemory] =
  let bufferInfo = newVkBufferCreateInfo(
    size = bytes,
    usage = VkBufferUsageFlags{StorageBufferBit, TransferSrcBit, TransferDstBit},
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = [],
  )
  result.buffer = createBuffer(ctx.device, bufferInfo)

  let req = getBufferMemoryRequirements(ctx.device, result.buffer)
  let alloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex = findMemoryType(
      ctx.physicalDevice,
      req.memoryTypeBits,
      VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
    ),
  )
  result.memory = allocateMemory(ctx.device, alloc)
  bindBufferMemory(ctx.device, result.buffer, result.memory, 0.VkDeviceSize)

proc updateBufferDescriptors(ctx: Context) =
  var inInfo = newVkDescriptorBufferInfo(
    buffer = ctx.inBuffer, offset = 0.VkDeviceSize, range = ctx.bufferBytes
  )
  var outInfo = newVkDescriptorBufferInfo(
    buffer = ctx.outBuffer, offset = 0.VkDeviceSize, range = ctx.bufferBytes
  )

  let writes = [
    newVkWriteDescriptorSet(
      dstSet = ctx.descriptorSet,
      dstBinding = 0,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.StorageBuffer,
      pImageInfo = nil,
      pBufferInfo = inInfo.addr,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.descriptorSet,
      dstBinding = 1,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.StorageBuffer,
      pImageInfo = nil,
      pBufferInfo = outInfo.addr,
      pTexelBufferView = nil,
    ),
  ]
  updateDescriptorSets(ctx.device, writes, [])

proc ensureGpuBuffers(ctx: Context, bytes: VkDeviceSize) =
  if ctx.bufferBytes == bytes and ctx.inBuffer != vkNullBuffer and
      ctx.outBuffer != vkNullBuffer:
    return

  if ctx.inBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.inBuffer)
    ctx.inBuffer = vkNullBuffer
  if ctx.outBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.outBuffer)
    ctx.outBuffer = vkNullBuffer
  if ctx.inMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.inMemory)
    ctx.inMemory = vkNullMemory
  if ctx.outMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.outMemory)
    ctx.outMemory = vkNullMemory

  ctx.bufferBytes = bytes
  if bytes == 0.VkDeviceSize:
    return

  let inputAlloc = ctx.createStorageBuffer(bytes)
  let outputAlloc = ctx.createStorageBuffer(bytes)
  ctx.inBuffer = inputAlloc.buffer
  ctx.inMemory = inputAlloc.memory
  ctx.outBuffer = outputAlloc.buffer
  ctx.outMemory = outputAlloc.memory
  ctx.updateBufferDescriptors()

proc ensureUploadBuffer(ctx: Context, bytes: VkDeviceSize) =
  if ctx.uploadBytes == bytes and ctx.uploadBuffer != vkNullBuffer:
    return

  if ctx.uploadBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.uploadBuffer)
    ctx.uploadBuffer = vkNullBuffer
  if ctx.uploadMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.uploadMemory)
    ctx.uploadMemory = vkNullMemory

  ctx.uploadBytes = bytes
  if bytes == 0.VkDeviceSize:
    return

  let bufferInfo = newVkBufferCreateInfo(
    size = bytes,
    usage = VkBufferUsageFlags{TransferSrcBit},
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = [],
  )
  ctx.uploadBuffer = createBuffer(ctx.device, bufferInfo)
  let req = getBufferMemoryRequirements(ctx.device, ctx.uploadBuffer)
  let alloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex = findMemoryType(
      ctx.physicalDevice,
      req.memoryTypeBits,
      VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
    ),
  )
  ctx.uploadMemory = allocateMemory(ctx.device, alloc)
  bindBufferMemory(ctx.device, ctx.uploadBuffer, ctx.uploadMemory, 0.VkDeviceSize)

proc destroySwapchain(ctx: Context) =
  if ctx.swapchain != vkNullSwapchain:
    vkDestroySwapchainKHR(ctx.device, ctx.swapchain, nil)
    ctx.swapchain = vkNullSwapchain
  ctx.swapchainImages.setLen(0)
  ctx.swapchainFormat = VK_FORMAT_UNDEFINED
  ctx.swapchainExtent = VkExtent2D(width: 0'u32, height: 0'u32)

proc createSwapchain(ctx: Context, width, height: int32) =
  if ctx.surface == vkNullSurface:
    return

  let support = querySwapChainSupport(ctx.physicalDevice, ctx.surface)
  if support.formats.len == 0 or support.presentModes.len == 0:
    raise newException(
      ValueError, "Vulkan surface has no swapchain formats or present modes"
    )

  let
    surfaceFormat = chooseSwapSurfaceFormat(support.formats)
    presentMode = chooseSwapPresentMode(support.presentModes)
    extent = chooseSwapExtent(support.capabilities, width, height)

  var imageCount = support.capabilities.minImageCount + 1
  if support.capabilities.maxImageCount > 0 and
      imageCount > support.capabilities.maxImageCount:
    imageCount = support.capabilities.maxImageCount

  let queueFamilyIndices =
    if ctx.queueFamily != ctx.presentQueueFamily:
      @[ctx.queueFamily, ctx.presentQueueFamily]
    else:
      @[]

  var createInfo = newVkSwapchainCreateInfoKHR(
    surface = ctx.surface,
    minImageCount = imageCount,
    imageFormat = surfaceFormat.format,
    imageColorSpace = surfaceFormat.colorSpace,
    imageExtent = extent,
    imageArrayLayers = 1,
    imageUsage = VkImageUsageFlags{TransferDstBit},
    imageSharingMode =
      if queueFamilyIndices.len > 0:
        VK_SHARING_MODE_CONCURRENT
      else:
        VK_SHARING_MODE_EXCLUSIVE,
    queueFamilyIndices = queueFamilyIndices,
    preTransform = support.capabilities.currentTransform,
    compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    presentMode = presentMode,
    clipped = VkBool32(VkTrue),
    oldSwapchain = ctx.swapchain,
  )

  var swapchain: VkSwapchainKHR
  checkVkResult vkCreateSwapchainKHR(ctx.device, createInfo.addr, nil, swapchain.addr)

  if ctx.swapchain != vkNullSwapchain:
    vkDestroySwapchainKHR(ctx.device, ctx.swapchain, nil)
  ctx.swapchain = swapchain

  var actualCount = imageCount
  discard vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, actualCount.addr, nil)
  ctx.swapchainImages.setLen(actualCount)
  if actualCount > 0:
    discard vkGetSwapchainImagesKHR(
      ctx.device, ctx.swapchain, actualCount.addr, ctx.swapchainImages[0].addr
    )

  ctx.swapchainFormat = surfaceFormat.format
  ctx.swapchainExtent = extent
  ctx.swapchainOutOfDate = false
  info "Created Vulkan swapchain",
    width = int(ctx.swapchainExtent.width),
    height = int(ctx.swapchainExtent.height),
    imageCount = ctx.swapchainImages.len,
    format = $ctx.swapchainFormat

proc ensureSwapchain(ctx: Context, width, height: int32) =
  if not ctx.presentReady or width <= 0 or height <= 0:
    return

  let needsRecreate =
    ctx.swapchain == vkNullSwapchain or ctx.swapchainOutOfDate or
    ctx.swapchainExtent.width != width.uint32 or
    ctx.swapchainExtent.height != height.uint32
  if not needsRecreate:
    return

  info "Recreating Vulkan swapchain",
    width = width, height = height, outOfDate = ctx.swapchainOutOfDate
  if ctx.device != vkNullDevice:
    discard vkDeviceWaitIdle(ctx.device)
  ctx.createSwapchain(width, height)

proc ensureGpuRuntime(ctx: Context) =
  if ctx.gpuReady:
    return

  vkPreload()

  let appInfo = newVkApplicationInfo(
    pApplicationName = "figdraw-vulkan",
    applicationVersion = vkMakeVersion(0, 0, 1, 0),
    pEngineName = "figdraw",
    engineVersion = vkMakeVersion(0, 0, 1, 0),
    apiVersion = vkApiVersion1_1,
  )
  let instanceInfo = newVkInstanceCreateInfo(
    pApplicationInfo = appInfo.addr,
    pEnabledLayerNames = [],
    pEnabledExtensionNames = ctx.instanceExtensions(),
  )
  ctx.instance = createInstance(instanceInfo)

  vkInit(ctx.instance, load1_2 = false, load1_3 = false)

  if ctx.hasPresentTarget():
    loadVK_KHR_surface()
    ctx.createPresentSurface()

  let devices = enumeratePhysicalDevices(ctx.instance)
  if devices.len == 0:
    raise newException(ValueError, "No Vulkan physical devices found")

  var wantPresent = ctx.hasPresentTarget()
  var selectedQueues: QueueFamilyIndices
  for device in devices:
    let devName = physicalDeviceName(device)
    let queues = findQueueFamilies(device, ctx.surface, requirePresent = wantPresent)
    if not queues.graphicsFound or not queues.presentFound:
      debug "Skipping Vulkan device: missing required queue families",
        device = devName,
        wantPresent = wantPresent,
        graphicsFound = queues.graphicsFound,
        presentFound = queues.presentFound
      continue

    if wantPresent:
      let hasSwapchain = checkDeviceExtensionSupport(
        device, @[VkKhrSwapchainExtensionName]
      )
      if not hasSwapchain:
        debug "Skipping Vulkan device: missing VK_KHR_swapchain", device = devName
        continue
      let support = querySwapChainSupport(device, ctx.surface)
      if support.formats.len == 0 or support.presentModes.len == 0:
        debug "Skipping Vulkan device: surface has no usable swapchain support",
          device = devName,
          formatCount = support.formats.len,
          presentModeCount = support.presentModes.len
        continue

    ctx.physicalDevice = device
    selectedQueues = queues
    info "Selected Vulkan physical device",
      device = devName,
      graphicsQueue = queues.graphicsFamily,
      presentQueue = queues.presentFamily,
      wantPresent = wantPresent
    break

  if ctx.physicalDevice == vkNullPhysicalDevice and wantPresent:
    warn "No Vulkan present-capable physical device found; falling back to offscreen mode"
    wantPresent = false
    for device in devices:
      let devName = physicalDeviceName(device)
      let queues = findQueueFamilies(device, ctx.surface, requirePresent = false)
      if not queues.graphicsFound:
        debug "Skipping Vulkan device (offscreen fallback): missing graphics queue",
          device = devName
        continue
      ctx.physicalDevice = device
      selectedQueues = queues
      info "Selected Vulkan physical device for offscreen fallback",
        device = devName,
        graphicsQueue = queues.graphicsFamily
      break

  if ctx.physicalDevice == vkNullPhysicalDevice:
    raise newException(ValueError, "No suitable Vulkan physical device found")

  ctx.queueFamily = selectedQueues.graphicsFamily
  ctx.presentQueueFamily =
    if wantPresent: selectedQueues.presentFamily else: selectedQueues.graphicsFamily

  var queueCreateInfos =
    @[
      newVkDeviceQueueCreateInfo(
        queueFamilyIndex = ctx.queueFamily, queuePriorities = [1.0'f32]
      )
    ]
  if ctx.presentQueueFamily != ctx.queueFamily:
    queueCreateInfos.add(
      newVkDeviceQueueCreateInfo(
        queueFamilyIndex = ctx.presentQueueFamily, queuePriorities = [1.0'f32]
      )
    )

  let deviceExtensions =
    if wantPresent:
      @[VkKhrSwapchainExtensionName.cstring]
    else:
      @[]
  let deviceInfo = newVkDeviceCreateInfo(
    queueCreateInfos = queueCreateInfos,
    pEnabledLayerNames = [],
    pEnabledExtensionNames = deviceExtensions,
    enabledFeatures = [],
  )
  ctx.device = createDevice(ctx.physicalDevice, deviceInfo)
  ctx.queue = getDeviceQueue(ctx.device, ctx.queueFamily, 0)
  ctx.presentQueue =
    if wantPresent:
      getDeviceQueue(ctx.device, ctx.presentQueueFamily, 0)
    else:
      ctx.queue

  if wantPresent:
    loadVK_KHR_swapchain()

  let poolInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = ctx.queueFamily,
    flags = VkCommandPoolCreateFlags{ResetCommandBufferBit},
  )
  ctx.commandPool = createCommandPool(ctx.device, poolInfo)

  let bindings = [
    newVkDescriptorSetLayoutBinding(
      binding = 0,
      descriptorType = VkDescriptorType.StorageBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{ComputeBit},
      pImmutableSamplers = nil,
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 1,
      descriptorType = VkDescriptorType.StorageBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{ComputeBit},
      pImmutableSamplers = nil,
    ),
  ]
  let setLayoutInfo = newVkDescriptorSetLayoutCreateInfo(bindings = bindings)
  ctx.descriptorSetLayout = createDescriptorSetLayout(ctx.device, setLayoutInfo)

  let poolSizes = [
    newVkDescriptorPoolSize(
      `type` = VkDescriptorType.StorageBuffer, descriptorCount = 2
    )
  ]
  let descPoolInfo = newVkDescriptorPoolCreateInfo(maxSets = 1, poolSizes = poolSizes)
  ctx.descriptorPool = createDescriptorPool(ctx.device, descPoolInfo)

  let setAllocInfo = newVkDescriptorSetAllocateInfo(
    descriptorPool = ctx.descriptorPool, setLayouts = [ctx.descriptorSetLayout]
  )
  ctx.descriptorSet = allocateDescriptorSets(ctx.device, setAllocInfo)

  let shaderInfo = newVkShaderModuleCreateInfo(code = frameCopyCompSpv)
  ctx.shaderModule = createShaderModule(ctx.device, shaderInfo)

  let stageInfo = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.ComputeBit,
    module = ctx.shaderModule,
    pName = "main",
    pSpecializationInfo = nil,
  )

  let pushConstantRange = newVkPushConstantRange(
    stageFlags = VkShaderStageFlags{ComputeBit},
    offset = 0,
    size = uint32(sizeof(uint32)),
  )

  let pipelineLayoutInfo = newVkPipelineLayoutCreateInfo(
    setLayouts = [ctx.descriptorSetLayout], pushConstantRanges = [pushConstantRange]
  )
  ctx.pipelineLayout = createPipelineLayout(ctx.device, pipelineLayoutInfo)

  let computeInfo = newVkComputePipelineCreateInfo(
    stage = stageInfo,
    layout = ctx.pipelineLayout,
    basePipelineHandle = 0.VkPipeline,
    basePipelineIndex = -1,
  )
  ctx.pipeline = createComputePipelines(ctx.device, 0.VkPipelineCache, [computeInfo])

  if wantPresent:
    let semaphoreInfo = newVkSemaphoreCreateInfo()
    checkVkResult vkCreateSemaphore(
      ctx.device, semaphoreInfo.addr, nil, ctx.imageAvailableSemaphore.addr
    )
    checkVkResult vkCreateSemaphore(
      ctx.device, semaphoreInfo.addr, nil, ctx.renderFinishedSemaphore.addr
    )
    let fenceInfo = newVkFenceCreateInfo(flags = VkFenceCreateFlags{SignaledBit})
    checkVkResult vkCreateFence(ctx.device, fenceInfo.addr, nil, ctx.inFlightFence.addr)

    let cmdAlloc = newVkCommandBufferAllocateInfo(
      commandPool = ctx.commandPool,
      level = VkCommandBufferLevel.Primary,
      commandBufferCount = 1,
    )
    ctx.presentCommandBuffer = allocateCommandBuffers(ctx.device, cmdAlloc)

    let initialW = max(1, ctx.frameSize.x.int32)
    let initialH = max(1, ctx.frameSize.y.int32)
    ctx.createSwapchain(initialW, initialH)
    ctx.presentReady = true
  else:
    if ctx.surface != vkNullSurface:
      vkDestroySurfaceKHR(ctx.instance, ctx.surface, nil)
      ctx.surface = vkNullSurface

  ctx.gpuReady = true
  info "Initialized Vulkan compute pipeline",
    queueFamily = ctx.queueFamily, present = ctx.presentReady

proc recordPresentCopy(
    commandBuffer: VkCommandBuffer,
    image: VkImage,
    extent: VkExtent2D,
    srcBuffer: VkBuffer,
) =
  let beginInfo = newVkCommandBufferBeginInfo(pInheritanceInfo = nil)
  checkVkResult vkBeginCommandBuffer(commandBuffer, beginInfo.addr)

  var barrierToTransfer = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    srcAccessMask: 0.VkAccessFlags,
    dstAccessMask: VkAccessFlags{TransferWriteBit},
    oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: image,
    subresourceRange: VkImageSubresourceRange(
      aspectMask: VkImageAspectFlags{ColorBit},
      baseMipLevel: 0,
      levelCount: 1,
      baseArrayLayer: 0,
      layerCount: 1,
    ),
  )

  vkCmdPipelineBarrier(
    commandBuffer,
    VkPipelineStageFlags{TopOfPipeBit},
    VkPipelineStageFlags{TransferBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    barrierToTransfer.addr,
  )

  var region = VkBufferImageCopy(
    bufferOffset: 0.VkDeviceSize,
    bufferRowLength: 0,
    bufferImageHeight: 0,
    imageSubresource: VkImageSubresourceLayers(
      aspectMask: VkImageAspectFlags{ColorBit},
      mipLevel: 0,
      baseArrayLayer: 0,
      layerCount: 1,
    ),
    imageOffset: VkOffset3D(x: 0, y: 0, z: 0),
    imageExtent: VkExtent3D(width: extent.width, height: extent.height, depth: 1),
  )

  vkCmdCopyBufferToImage(
    commandBuffer, srcBuffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1,
    region.addr,
  )

  var barrierToPresent = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    srcAccessMask: VkAccessFlags{TransferWriteBit},
    dstAccessMask: VkAccessFlags{MemoryReadBit},
    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    newLayout: VkImageLayout.PresentSrcKhr,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: image,
    subresourceRange: VkImageSubresourceRange(
      aspectMask: VkImageAspectFlags{ColorBit},
      baseMipLevel: 0,
      levelCount: 1,
      baseArrayLayer: 0,
      layerCount: 1,
    ),
  )

  vkCmdPipelineBarrier(
    commandBuffer,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{BottomOfPipeBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    barrierToPresent.addr,
  )

  checkVkResult vkEndCommandBuffer(commandBuffer)

proc presentFrame(ctx: Context) =
  if not ctx.presentReady or ctx.canvas.isNil:
    return

  inc ctx.presentFrameCount
  let width = ctx.canvas.width.int32
  let height = ctx.canvas.height.int32
  if width <= 0 or height <= 0:
    return
  if ctx.presentFrameCount <= 5 or (ctx.presentFrameCount mod 240'u64) == 0'u64:
    info "presentFrame begin",
      frame = ctx.presentFrameCount,
      width = width,
      height = height,
      outOfDate = ctx.swapchainOutOfDate

  ctx.ensureSwapchain(width, height)
  if ctx.swapchain == vkNullSwapchain:
    warn "No Vulkan swapchain available for present", frame = ctx.presentFrameCount
    return

  let bytes = VkDeviceSize(width * height * 4)
  let outBytes = cast[ptr UncheckedArray[uint8]](
    mapMemory(ctx.device, ctx.outMemory, 0.VkDeviceSize, bytes, 0.VkMemoryMapFlags)
  )
  if ctx.presentFrameCount <= 5:
    info "present source pixel RGBA",
      frame = ctx.presentFrameCount,
      r = int(outBytes[0]),
      g = int(outBytes[1]),
      b = int(outBytes[2]),
      a = int(outBytes[3])
  unmapMemory(ctx.device, ctx.outMemory)

  var srcBuffer = ctx.outBuffer
  if ctx.swapchainFormat == VK_FORMAT_B8G8R8A8_UNORM:
    ctx.ensureUploadBuffer(bytes)
    let src = cast[ptr uint8](mapMemory(
      ctx.device, ctx.outMemory, 0.VkDeviceSize, bytes, 0.VkMemoryMapFlags
    ))
    let dst = cast[ptr uint8](mapMemory(
      ctx.device, ctx.uploadMemory, 0.VkDeviceSize, bytes, 0.VkMemoryMapFlags
    ))
    swizzleRgbaToBgra(dst, src, int(bytes))
    if ctx.presentFrameCount <= 5:
      let uploadBytes = cast[ptr UncheckedArray[uint8]](dst)
      info "present upload pixel BGRA",
        frame = ctx.presentFrameCount,
        b = int(uploadBytes[0]),
        g = int(uploadBytes[1]),
        r = int(uploadBytes[2]),
        a = int(uploadBytes[3])
    unmapMemory(ctx.device, ctx.uploadMemory)
    unmapMemory(ctx.device, ctx.outMemory)
    srcBuffer = ctx.uploadBuffer

  let waitResult = vkWaitForFences(
    ctx.device, 1, ctx.inFlightFence.addr, VkBool32(VkTrue), 250_000_000'u64
  )
  if waitResult == VkTimeout:
    warn "vkWaitForFences timed out",
      frame = ctx.presentFrameCount, width = width, height = height
    return
  checkVkResult waitResult
  checkVkResult vkResetFences(ctx.device, 1, ctx.inFlightFence.addr)

  var imageIndex: uint32 = 0
  let acquireResult = vkAcquireNextImageKHR(
    ctx.device,
    ctx.swapchain,
    250_000_000'u64,
    ctx.imageAvailableSemaphore,
    VkFence(0),
    imageIndex.addr,
  )
  if acquireResult == VkTimeout:
    warn "vkAcquireNextImageKHR timed out", frame = ctx.presentFrameCount
    return
  elif acquireResult == VkNotReady:
    warn "vkAcquireNextImageKHR returned not-ready", frame = ctx.presentFrameCount
    return
  elif acquireResult == VkErrorOutOfDateKhr:
    ctx.swapchainOutOfDate = true
    warn "vkAcquireNextImageKHR returned out-of-date", frame = ctx.presentFrameCount
    return
  elif acquireResult == VkSuboptimalKhr:
    warn "vkAcquireNextImageKHR returned suboptimal", frame = ctx.presentFrameCount
  checkVkResult acquireResult

  if ctx.presentCommandBuffer == vkNullCommandBuffer:
    warn "No Vulkan present command buffer allocated", frame = ctx.presentFrameCount
    return

  var commandBuffer = ctx.presentCommandBuffer
  checkVkResult vkResetCommandBuffer(commandBuffer, 0.VkCommandBufferResetFlags)
  recordPresentCopy(
    commandBuffer, ctx.swapchainImages[imageIndex.int], ctx.swapchainExtent, srcBuffer
  )

  let submitInfo = newVkSubmitInfo(
    waitSemaphores = [ctx.imageAvailableSemaphore],
    waitDstStageMask = [VkPipelineStageFlags{TransferBit}],
    commandBuffers = [commandBuffer],
    signalSemaphores = [ctx.renderFinishedSemaphore],
  )
  checkVkResult vkQueueSubmit(ctx.queue, 1, submitInfo.addr, ctx.inFlightFence)

  let presentInfo = newVkPresentInfoKHR(
    waitSemaphores = [ctx.renderFinishedSemaphore],
    swapchains = [ctx.swapchain],
    imageIndices = [imageIndex],
    results = @[],
  )
  let presentResult = vkQueuePresentKHR(ctx.presentQueue, presentInfo.addr)
  if presentResult in [VkErrorOutOfDateKhr, VkSuboptimalKhr]:
    ctx.swapchainOutOfDate = true
    warn "vkQueuePresentKHR needs swapchain recreate",
      frame = ctx.presentFrameCount, result = $presentResult
  elif presentResult != VkSuccess:
    checkVkResult presentResult
  elif ctx.presentFrameCount <= 5 or (ctx.presentFrameCount mod 240'u64) == 0'u64:
    info "presentFrame submitted",
      frame = ctx.presentFrameCount,
      imageIndex = imageIndex,
      width = int(ctx.swapchainExtent.width),
      height = int(ctx.swapchainExtent.height)


proc runGpuCopy(ctx: Context) =
  if not ctx.gpuReady or ctx.canvas.isNil:
    return

  let pixelCount = ctx.canvas.width * ctx.canvas.height
  let bytes = VkDeviceSize(pixelCount * 4)
  ctx.ensureGpuBuffers(bytes)
  if bytes == 0.VkDeviceSize:
    return

  let mappedIn = mapMemory(
    ctx.device, ctx.inMemory, 0.VkDeviceSize, ctx.bufferBytes, 0.VkMemoryMapFlags
  )
  copyMem(mappedIn, ctx.canvas.data[0].addr, int(ctx.bufferBytes))
  unmapMemory(ctx.device, ctx.inMemory)

  let cmdAlloc = newVkCommandBufferAllocateInfo(
    commandPool = ctx.commandPool,
    level = VkCommandBufferLevel.Primary,
    commandBufferCount = 1,
  )
  var commandBuffer = allocateCommandBuffers(ctx.device, cmdAlloc)

  let beginInfo = newVkCommandBufferBeginInfo(
    flags = VkCommandBufferUsageFlags{OneTimeSubmitBit}, pInheritanceInfo = nil
  )
  beginCommandBuffer(commandBuffer, beginInfo)
  cmdBindPipeline(commandBuffer, VkPipelineBindPoint.Compute, ctx.pipeline)
  cmdBindDescriptorSets(
    commandBuffer,
    VkPipelineBindPoint.Compute,
    ctx.pipelineLayout,
    0,
    [ctx.descriptorSet],
    [],
  )

  var pushCount = uint32(pixelCount)
  vkCmdPushConstants(
    commandBuffer,
    ctx.pipelineLayout,
    VkShaderStageFlags{ComputeBit},
    0,
    uint32(sizeof(uint32)),
    pushCount.addr,
  )

  let groupCount = uint32((pixelCount + 63) div 64)
  cmdDispatch(commandBuffer, max(1'u32, groupCount), 1, 1)
  endCommandBuffer(commandBuffer)

  let submitInfo = newVkSubmitInfo(
    waitSemaphores = [],
    waitDstStageMask = [],
    commandBuffers = [commandBuffer],
    signalSemaphores = [],
  )
  queueSubmit(ctx.queue, [submitInfo], VkFence(0))
  checkVkResult vkQueueWaitIdle(ctx.queue)

  vkFreeCommandBuffers(ctx.device, ctx.commandPool, 1, commandBuffer.addr)

  ctx.lastFrame = px.newImage(ctx.canvas.width, ctx.canvas.height)
  let mappedOut = mapMemory(
    ctx.device, ctx.outMemory, 0.VkDeviceSize, ctx.bufferBytes, 0.VkMemoryMapFlags
  )
  copyMem(ctx.lastFrame.data[0].addr, mappedOut, int(ctx.bufferBytes))
  unmapMemory(ctx.device, ctx.outMemory)

proc destroyGpu(ctx: Context) =
  if ctx.isNil:
    return

  if ctx.device != vkNullDevice:
    discard vkDeviceWaitIdle(ctx.device)

  if ctx.inBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.inBuffer)
    ctx.inBuffer = vkNullBuffer
  if ctx.outBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.outBuffer)
    ctx.outBuffer = vkNullBuffer
  if ctx.inMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.inMemory)
    ctx.inMemory = vkNullMemory
  if ctx.outMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.outMemory)
    ctx.outMemory = vkNullMemory

  if ctx.uploadBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.uploadBuffer)
    ctx.uploadBuffer = vkNullBuffer
  if ctx.uploadMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.uploadMemory)
    ctx.uploadMemory = vkNullMemory

  if ctx.imageAvailableSemaphore != vkNullSemaphore:
    vkDestroySemaphore(ctx.device, ctx.imageAvailableSemaphore, nil)
    ctx.imageAvailableSemaphore = vkNullSemaphore
  if ctx.renderFinishedSemaphore != vkNullSemaphore:
    vkDestroySemaphore(ctx.device, ctx.renderFinishedSemaphore, nil)
    ctx.renderFinishedSemaphore = vkNullSemaphore
  if ctx.inFlightFence != vkNullFence:
    vkDestroyFence(ctx.device, ctx.inFlightFence, nil)
    ctx.inFlightFence = vkNullFence

  if ctx.presentCommandBuffer != vkNullCommandBuffer and
      ctx.commandPool != vkNullCommandPool:
    vkFreeCommandBuffers(ctx.device, ctx.commandPool, 1, ctx.presentCommandBuffer.addr)
    ctx.presentCommandBuffer = vkNullCommandBuffer

  ctx.destroySwapchain()

  if ctx.pipeline != vkNullPipeline:
    destroyPipeline(ctx.device, ctx.pipeline)
    ctx.pipeline = vkNullPipeline
  if ctx.pipelineLayout != vkNullPipelineLayout:
    destroyPipelineLayout(ctx.device, ctx.pipelineLayout)
    ctx.pipelineLayout = vkNullPipelineLayout
  if ctx.shaderModule != vkNullShaderModule:
    destroyShaderModule(ctx.device, ctx.shaderModule)
    ctx.shaderModule = vkNullShaderModule

  if ctx.descriptorPool != vkNullDescriptorPool:
    destroyDescriptorPool(ctx.device, ctx.descriptorPool)
    ctx.descriptorPool = vkNullDescriptorPool
  if ctx.descriptorSetLayout != vkNullDescriptorSetLayout:
    destroyDescriptorSetLayout(ctx.device, ctx.descriptorSetLayout)
    ctx.descriptorSetLayout = vkNullDescriptorSetLayout

  if ctx.commandPool != vkNullCommandPool:
    destroyCommandPool(ctx.device, ctx.commandPool)
    ctx.commandPool = vkNullCommandPool

  if ctx.device != vkNullDevice:
    destroyDevice(ctx.device)
    ctx.device = vkNullDevice
  if ctx.surface != vkNullSurface:
    vkDestroySurfaceKHR(ctx.instance, ctx.surface, nil)
    ctx.surface = vkNullSurface
  if ctx.instance != vkNullInstance:
    destroyInstance(ctx.instance)
    ctx.instance = vkNullInstance

  ctx.physicalDevice = vkNullPhysicalDevice
  ctx.queue = vkNullQueue
  ctx.presentQueue = vkNullQueue
  ctx.bufferBytes = 0.VkDeviceSize
  ctx.uploadBytes = 0.VkDeviceSize
  ctx.presentReady = false
  ctx.swapchainOutOfDate = false
  ctx.gpuReady = false

proc setFillColor(ctx: Context, color: Color) =
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.fillStyle = color.colorRgba8

proc setStrokeColor(ctx: Context, color: Color) =
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.strokeStyle = color.colorRgba8

proc clampRadii(
    rect: Rect, radii: array[DirectionCorners, float32]
): array[DirectionCorners, float32] =
  let maxR = max(0.0'f32, min(rect.w, rect.h) / 2.0'f32)
  for corner in DirectionCorners:
    result[corner] = clamp(radii[corner], 0.0'f32, maxR)

proc drawShadow(
    ctx: Context,
    rect: Rect,
    shapeSize: Vec2,
    color: Color,
    radii: array[DirectionCorners, float32],
    blur: float32,
    spread: float32,
    inset: bool,
) =
  if rect.w <= 0 or rect.h <= 0 or color.a <= 0.0:
    return

  let
    imgW = max(1, rect.w.ceil.int)
    imgH = max(1, rect.h.ceil.int)
  var shadowImg = px.newImage(imgW, imgH)
  let shadowCtx = px.newContext(shadowImg)
  shadowCtx.fillStyle = color.colorRgba8

  let localRect = rect(0.0'f32, 0.0'f32, rect.w, rect.h)
  var shapeRect = localRect
  if shapeSize.x > 0 and shapeSize.y > 0:
    shapeRect = rect(
      (rect.w - shapeSize.x) * 0.5'f32,
      (rect.h - shapeSize.y) * 0.5'f32,
      shapeSize.x,
      shapeSize.y,
    )

  if spread != 0.0'f32:
    shapeRect = rect(
      shapeRect.x - spread,
      shapeRect.y - spread,
      shapeRect.w + spread * 2.0'f32,
      shapeRect.h + spread * 2.0'f32,
    )

  let rr = clampRadii(shapeRect, radii)
  shadowCtx.fillRoundedRect(
    shapeRect, rr[dcTopLeft], rr[dcTopRight], rr[dcBottomRight], rr[dcBottomLeft]
  )

  let blurAmount = max(0, blur.round.int)
  if blurAmount > 0:
    px.blur(shadowImg, blurAmount.float32)

  if inset:
    let clipPath = px.newPath()
    let clipR = clampRadii(rect, radii)
    clipPath.roundedRect(
      rect,
      clipR[dcTopLeft],
      clipR[dcTopRight],
      clipR[dcBottomRight],
      clipR[dcBottomLeft],
    )
    ctx.drawCtx.save()
    ctx.drawCtx.clip(clipPath)
    ctx.drawCtx.drawImage(shadowImg, rect.x, rect.y)
    ctx.drawCtx.restore()
  else:
    ctx.drawCtx.drawImage(shadowImg, rect.x, rect.y)

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0,
): Context =
  if maxQuads > quadLimit:
    raise newException(ValueError, &"Quads cannot exceed {quadLimit}")

  result = Context()
  result.atlasSize = atlasSize
  result.atlasMargin = atlasMargin
  result.maxQuads = maxQuads
  result.mat = mat4()
  result.mats = @[]
  result.entries = initTable[Hash, Rect]()
  result.images = initTable[Hash, px.Image]()
  result.pixelate = pixelate
  result.pixelScale = pixelScale.float32
  result.aaFactor = 1.2'f32
  result.instance = vkNullInstance
  result.physicalDevice = vkNullPhysicalDevice
  result.device = vkNullDevice
  result.queue = vkNullQueue
  result.presentQueue = vkNullQueue
  result.queueFamily = 0'u32
  result.presentQueueFamily = 0'u32
  result.commandPool = vkNullCommandPool
  result.descriptorSetLayout = vkNullDescriptorSetLayout
  result.descriptorPool = vkNullDescriptorPool
  result.descriptorSet = vkNullDescriptorSet
  result.pipelineLayout = vkNullPipelineLayout
  result.pipeline = vkNullPipeline
  result.shaderModule = vkNullShaderModule
  result.inBuffer = vkNullBuffer
  result.outBuffer = vkNullBuffer
  result.inMemory = vkNullMemory
  result.outMemory = vkNullMemory
  result.bufferBytes = 0.VkDeviceSize
  result.presentTargetKind = presentTargetNone
  result.presentXlibDisplay = nil
  result.presentXlibWindow = 0'u64
  result.presentWin32Hinstance = nil
  result.presentWin32Hwnd = nil
  result.presentMetalLayer = nil
  result.surface = vkNullSurface
  result.swapchain = vkNullSwapchain
  result.swapchainImages = @[]
  result.swapchainFormat = VK_FORMAT_UNDEFINED
  result.swapchainExtent = VkExtent2D(width: 0'u32, height: 0'u32)
  result.swapchainOutOfDate = false
  result.presentReady = false
  result.presentFrameCount = 0'u64
  result.imageAvailableSemaphore = vkNullSemaphore
  result.renderFinishedSemaphore = vkNullSemaphore
  result.inFlightFence = vkNullFence
  result.presentCommandBuffer = vkNullCommandBuffer
  result.uploadBuffer = vkNullBuffer
  result.uploadMemory = vkNullMemory
  result.uploadBytes = 0.VkDeviceSize

proc putImage*(ctx: Context, path: Hash, image: px.Image)

proc addImage*(ctx: Context, key: Hash, image: px.Image) =
  ctx.putImage(key, image)

proc putImage*(ctx: Context, path: Hash, image: px.Image) =
  ctx.images[path] = image
  ctx.entries[path] = rect(
    0.0'f32,
    0.0'f32,
    image.width.float32 / max(1, ctx.atlasSize).float32,
    image.height.float32 / max(1, ctx.atlasSize).float32,
  )

proc updateImage*(ctx: Context, path: Hash, image: px.Image) =
  if path notin ctx.entries:
    raise newException(KeyError, "px.Image key is not in context")
  ctx.images[path] = image

proc putFlippy*(ctx: Context, path: Hash, flippy: Flippy) =
  if flippy.mipmaps.len == 0:
    return
  ctx.putImage(path, flippy.mipmaps[0])

proc putImage*(ctx: Context, imgObj: ImgObj) =
  case imgObj.kind
  of FlippyImg:
    ctx.putFlippy(imgObj.id.Hash, imgObj.flippy)
  of PixieImg:
    ctx.putImage(imgObj.id.Hash, imgObj.pimg)

proc drawQuad*(
    ctx: Context,
    verts: array[4, Vec2],
    uvs: array[4, Vec2],
    colors: array[4, px.ColorRGBA],
) =
  discard uvs
  if ctx.drawCtx.isNil:
    return
  let path = px.newPath()
  path.moveTo(verts[0])
  path.lineTo(verts[1])
  path.lineTo(verts[2])
  path.lineTo(verts[3])
  path.closePath()
  ctx.drawCtx.fillStyle = colors[0]
  ctx.drawCtx.fill(path)

proc drawUvRect(ctx: Context, at, to: Vec2, imageId: Hash, color: Color) =
  if imageId notin ctx.images or ctx.drawCtx.isNil:
    return
  let img = ctx.images[imageId]

  # Pixie does not support per-image tint directly. Preserve alpha modulation.
  ctx.drawCtx.save()
  if color.a < 1.0'f32:
    ctx.drawCtx.globalAlpha = color.a
  ctx.drawCtx.drawImage(img, at.x, at.y, to.x - at.x, to.y - at.y)
  ctx.drawCtx.restore()

proc drawMsdfImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
) =
  discard pxRange
  discard sdThreshold
  discard strokeWeight
  ctx.drawUvRect(pos, pos + size, imageId, color)

proc drawMtsdfImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
) =
  discard pxRange
  discard sdThreshold
  discard strokeWeight
  ctx.drawUvRect(pos, pos + size, imageId, color)

proc setSdfGlobals*(ctx: Context, aaFactor: float32) =
  ctx.aaFactor = aaFactor

proc getImageRect(ctx: Context, imageId: Hash): Rect =
  if imageId notin ctx.entries:
    return rect(0, 0, 0, 0)
  ctx.entries[imageId]

proc drawImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  if imageId notin ctx.images:
    return
  let img = ctx.images[imageId]
  let wh = vec2(img.width.float32 * scale.float32, img.height.float32 * scale.float32)
  ctx.drawUvRect(pos, pos + wh, imageId, color)

proc drawImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ctx.drawUvRect(pos, pos + size, imageId, color)

proc drawImageAdj*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ctx.drawUvRect(pos, pos + size, imageId, color)

proc drawSprite*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  if imageId notin ctx.images:
    return
  let img = ctx.images[imageId]
  let size = vec2(img.width.float32 * scale.float32, img.height.float32 * scale.float32)
  ctx.drawUvRect(pos - size / 2.0'f32, pos + size / 2.0'f32, imageId, color)

proc drawSprite*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ctx.drawUvRect(pos - size / 2.0'f32, pos + size / 2.0'f32, imageId, color)

proc drawRect*(ctx: Context, rect: Rect, color: Color) =
  if ctx.drawCtx.isNil or rect.w <= 0 or rect.h <= 0 or color.a <= 0.0:
    return
  ctx.setFillColor(color)
  ctx.drawCtx.fillRect(rect)

proc drawRoundedRectSdf*(
    ctx: Context,
    rect: Rect,
    color: Color,
    radii: array[DirectionCorners, float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  if ctx.drawCtx.isNil or rect.w <= 0 or rect.h <= 0 or color.a <= 0.0:
    return

  let rr = clampRadii(rect, radii)
  case mode
  of sdfModeAnnular, sdfModeAnnularAA, sdfModeMsdfAnnular, sdfModeMtsdfAnnular:
    ctx.setStrokeColor(color)
    ctx.drawCtx.lineWidth = max(1.0'f32, factor)
    ctx.drawCtx.strokeRoundedRect(
      rect, rr[dcTopLeft], rr[dcTopRight], rr[dcBottomRight], rr[dcBottomLeft]
    )
  of sdfModeDropShadow, sdfModeDropShadowAA:
    ctx.drawShadow(
      rect = rect,
      shapeSize = shapeSize,
      color = color,
      radii = rr,
      blur = max(0.0'f32, factor),
      spread = spread,
      inset = false,
    )
  of sdfModeInsetShadow, sdfModeInsetShadowAnnular:
    ctx.drawShadow(
      rect = rect,
      shapeSize = shapeSize,
      color = color,
      radii = rr,
      blur = max(0.0'f32, factor),
      spread = spread,
      inset = true,
    )
  else:
    ctx.setFillColor(color)
    ctx.drawCtx.fillRoundedRect(
      rect, rr[dcTopLeft], rr[dcTopRight], rr[dcBottomRight], rr[dcBottomLeft]
    )

proc line*(ctx: Context, a: Vec2, b: Vec2, weight: float32, color: Color) =
  if ctx.drawCtx.isNil or color.a <= 0.0 or weight <= 0.0:
    return
  ctx.setStrokeColor(color)
  ctx.drawCtx.lineWidth = max(1.0'f32, weight)
  ctx.drawCtx.strokeSegment(segment(a, b))

proc linePolygon*(ctx: Context, poly: seq[Vec2], weight: float32, color: Color) =
  if poly.len < 2:
    return
  for i in 0 ..< poly.len:
    ctx.line(poly[i], poly[(i + 1) mod poly.len], weight, color)

proc clearMask*(ctx: Context) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."

proc beginMask*(ctx: Context) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  assert ctx.maskBegun == false, "ctx.beginMask has already been called."
  ctx.maskBegun = true
  inc ctx.maskDepth

proc endMask*(ctx: Context) =
  assert ctx.maskBegun == true, "ctx.maskBegun has not been called."
  ctx.maskBegun = false

proc popMask*(ctx: Context) =
  if ctx.maskDepth > 0:
    dec ctx.maskDepth

proc beginFrame*(
    ctx: Context,
    frameSize: Vec2,
    proj: Mat4,
    clearMain = false,
    clearMainColor: Color = whiteColor,
) =
  assert ctx.frameBegun == false, "ctx.beginFrame has already been called."
  ctx.frameBegun = true
  ctx.maskBegun = false
  ctx.maskDepth = 0
  ctx.frameSize = frameSize
  ctx.proj = proj
  ctx.ensureGpuRuntime()
  ctx.resetDrawCtx(clearMain, clearMainColor)

proc beginFrame*(
    ctx: Context, frameSize: Vec2, clearMain = false, clearMainColor: Color = whiteColor
) =
  beginFrame(
    ctx,
    frameSize,
    ortho[float32](0.0, frameSize.x, frameSize.y, 0, -1000.0, 1000.0),
    clearMain = clearMain,
    clearMainColor = clearMainColor,
  )

proc endFrame*(ctx: Context) =
  assert ctx.frameBegun == true, "ctx.beginFrame was not called first."
  assert ctx.maskDepth == 0, "Not all masks have been popped."
  ctx.frameBegun = false

  try:
    ctx.runGpuCopy()
  except CatchableError as e:
    # Keep rendering robust if Vulkan copy fails in constrained environments.
    warn "Vulkan compute copy failed; using CPU fallback", error = e.msg
    ctx.lastFrame = ctx.canvas.copy()

  try:
    ctx.presentFrame()
  except CatchableError as e:
    # Keep rendering robust if present fails (headless systems, minimized windows, etc).
    warn "Vulkan present failed", error = e.msg

proc translate*(ctx: Context, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.translate(v)

proc rotate*(ctx: Context, angle: float32) =
  ctx.mat = ctx.mat * rotateZ(angle)
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.rotate(angle)

proc scale*(ctx: Context, s: float32) =
  ctx.mat = ctx.mat * scale(vec3(s))
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.scale(vec2(s, s))

proc scale*(ctx: Context, s: Vec2) =
  ctx.mat = ctx.mat * scale(vec3(s.x, s.y, 1))
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.scale(s)

proc saveTransform*(ctx: Context) =
  ctx.mats.add(ctx.mat)
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.save()

proc restoreTransform*(ctx: Context) =
  if ctx.mats.len > 0:
    ctx.mat = ctx.mats.pop()
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.restore()

proc clearTransform*(ctx: Context) =
  ctx.mat = mat4()
  ctx.mats.setLen(0)
  if not ctx.drawCtx.isNil:
    ctx.drawCtx.resetTransform()

proc fromScreen*(ctx: Context, windowFrame: Vec2, v: Vec2): Vec2 =
  (ctx.mat.inverse() * vec3(v.x, windowFrame.y - v.y, 0)).xy

proc toScreen*(ctx: Context, windowFrame: Vec2, v: Vec2): Vec2 =
  result = (ctx.mat * vec3(v.x, v.y, 1)).xy
  result.y = -result.y + windowFrame.y

proc clearPresentTarget*(ctx: Context) =
  if ctx.gpuReady:
    ctx.destroyGpu()
  ctx.presentFrameCount = 0'u64
  ctx.presentTargetKind = presentTargetNone
  ctx.presentXlibDisplay = nil
  ctx.presentXlibWindow = 0'u64
  ctx.presentWin32Hinstance = nil
  ctx.presentWin32Hwnd = nil
  ctx.presentMetalLayer = nil

proc setPresentXlibTarget*(ctx: Context, display: pointer, window: uint64) =
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetXlib
  ctx.presentXlibDisplay = display
  ctx.presentXlibWindow = window

proc setPresentWin32Target*(ctx: Context, hinstance: pointer, hwnd: pointer) =
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetWin32
  ctx.presentWin32Hinstance = hinstance
  ctx.presentWin32Hwnd = hwnd

proc setPresentMetalLayer*(ctx: Context, layer: pointer) =
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetMetal
  ctx.presentMetalLayer = layer

proc readPixels*(
    ctx: Context, frame: Rect = rect(0, 0, 0, 0), readFront = true
): px.Image =
  discard readFront
  let src =
    if not ctx.lastFrame.isNil:
      ctx.lastFrame
    elif not ctx.canvas.isNil:
      ctx.canvas
    else:
      px.newImage(1, 1)

  var x = frame.x.int
  var y = frame.y.int
  var w = frame.w.int
  var h = frame.h.int

  if w <= 0 or h <= 0:
    x = 0
    y = 0
    w = src.width
    h = src.height

  x = clamp(x, 0, src.width)
  y = clamp(y, 0, src.height)
  w = clamp(w, 0, src.width - x)
  h = clamp(h, 0, src.height - y)

  result = px.newImage(w, h)
  for yy in 0 ..< h:
    for xx in 0 ..< w:
      result[xx, yy] = src[x + xx, y + yy]
