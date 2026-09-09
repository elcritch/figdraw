import std/[atomics, hashes, math, strformat, tables]

import pkg/pixie
import pkg/pixie/simd
import pkg/chroma
import pkg/chronicles
import pkg/vulkan
import ./vulkan_dispatch

import ../commons
import ../figbackend as figbackend
import ../common/formatflippy
import ../fignodes
import ../utils/drawextras
import ./vulkan_blur
import ./vulkan_resources
import ./vulkan_utils

export drawextras
export vulkan_utils

logScope:
  scope = "vulkan"

const
  UseVulkanValidation* {.booldefine: "figdraw.vulkanValidation".} = false
  quadLimit = 10_921
  sdfVertSpv = staticRead("shaders/sdf.vert.spv")
  sdfFragSpv = staticRead("shaders/sdf.frag.spv")
  blurVertSpv = staticRead("shaders/blur.vert.spv")
  blurFragSpv = staticRead("shaders/blur.frag.spv")

when defined(emscripten):
  type SdfModeData = float32
else:
  type SdfModeData = uint16

type SdfMode* = figbackend.SdfMode

type RectMaskKind = enum
  rmkFast
  rmkMask

type RectMask = object
  kind: RectMaskKind
  params: Vec4
  radii: Vec4
  matX: Vec4
  matY: Vec4

type PresentTargetKind* = enum
  presentTargetNone
  presentTargetXlib
  presentTargetWayland
  presentTargetWin32
  presentTargetMetal

when defined(linux) or defined(bsd):
  type LinuxSurfaceKind = enum
    linuxSurfaceXlib
    linuxSurfaceXcb

type
  VSUniforms = object
    proj: Mat4

  FSUniforms = object
    windowFrame: Vec2
    aaFactor: float32
    maskTexEnabled: uint32

  BlurUniforms = object
    texelStep: Vec2
    blurRadius: float32
    pad0: float32

  Vertex = object
    pos: array[2, float32]
    uv: array[2, float32]
    color: array[4, uint8]
    fillMidColor: array[4, uint8]
    fillStopColor: array[4, uint8]
    sdfParams: array[4, float32]
    sdfRadii: array[4, float32]
    sdfMode: uint16
    sdfPad: uint16
    sdfFactors: array[2, float32]
    rectMaskParams: array[4, float32]
    rectMaskRadii: array[4, float32]
    rectMaskMatX: array[4, float32]
    rectMaskMatY: array[4, float32]

  RetiredSwapchain = object
    swapchain: VkSwapchainKHR
    views: seq[VkImageView]
    framebuffers: seq[VkFramebuffer]
    semaphores: seq[VkSemaphore]
    replacementSwapchain: VkSwapchainKHR
    replacementImage: int
    awaitingFrameFence: bool

  VulkanContext* = ref object of figbackend.BackendContext
    atlasSize: int
    initialAtlasSize: int
    atlasMargin: int
    quadCount: int
    maxQuads: int
    mat*: Mat4
    mats: seq[Mat4]
    entries*: Table[Hash, Rect]
    atlasEntryMeta: Table[Hash, AtlasEntryMeta]
    heights: seq[uint16]
    proj*: Mat4
    frameSize: Vec2
    frameBegun: bool
    maskBegun: bool
    maskDepth: int
    pendingMaskRect: Rect
    pendingMaskValid: bool
    clipRects: seq[Rect]
    pixelate*: bool
    pixelScale*: float32
    aaFactor: float32
    textLcdFilteringEnabled: bool
    textSubpixelPositioningEnabled: bool
    textSubpixelGlyphVariantsEnabled: bool
    textSubpixelShift: float32

    positions: seq[float32]
    colors: seq[uint8]
    fillMidColors: seq[uint8]
    fillStopColors: seq[uint8]
    uvs: seq[float32]
    sdfParams: seq[float32]
    sdfRadii: seq[float32]
    sdfModeAttr: seq[SdfModeData]
    sdfFactors: seq[float32]
    rectMaskParams: seq[float32]
    rectMaskRadii: seq[float32]
    rectMaskMatX: seq[float32]
    rectMaskMatY: seq[float32]
    rectMaskStack: seq[RectMask]
    batchHasRectMask: bool
    indices: seq[uint16]
    vertexScratch: seq[Vertex]

    atlasPixels: Image
    atlasDirty: bool
    atlasLayoutReady: bool

    vk: VulkanDispatch
    instance: VkInstance
    debugMessenger: VkDebugUtilsMessengerEXT
    validationErrors: Atomic[int]
    physicalDevice: VkPhysicalDevice
    device: VkDevice
    queue: VkQueue
    queueFamily: uint32
    presentQueue: VkQueue
    presentQueueFamily: uint32

    presentTargetKind: PresentTargetKind
    instanceSurfaceHint: PresentTargetKind
    presentXlibDisplay: pointer
    presentXlibWindow: uint64
    presentWaylandDisplay: pointer
    presentWaylandSurface: pointer
    presentWin32Hinstance: pointer
    presentWin32Hwnd: pointer
    presentMetalLayer: pointer
    when defined(linux) or defined(bsd):
      linuxSurfaceKind: LinuxSurfaceKind

    surface: VkSurfaceKHR
    surfaceOwnedByContext: bool
    swapchain: VkSwapchainKHR
    swapchainImages: seq[VkImage]
    swapchainViews: seq[VkImageView]
    swapchainFramebuffers: seq[VkFramebuffer]
    retiredSwapchains: seq[RetiredSwapchain]
    swapchainFormat: VkFormat
    swapchainExtent: VkExtent2D
    swapchainRequestedWidth: int32
    swapchainRequestedHeight: int32
    swapchainOutOfDate: bool
    swapchainTransferSrcSupported: bool
    requestedSwapchainProfile: VulkanSwapchainProfile
    activeSwapchainProfile: VulkanSwapchainProfile
    driverInfo: VulkanDriverInfo
    presentReady: bool

    renderPass: VkRenderPass
    descriptorSetLayout: VkDescriptorSetLayout
    descriptorSet: VkDescriptorSet
    pipelineLayout: VkPipelineLayout
    pipeline: VkPipeline
    vertShader: VkShaderModule
    fragShader: VkShaderModule

    commandPool: VkCommandPool
    commandBuffer: VkCommandBuffer
    imageAvailableSemaphore: VkSemaphore
    renderFinishedSemaphores: seq[VkSemaphore]
    inFlightFence: VkFence
    acquiredImageIndex: uint32
    commandRecording: bool
    renderPassBegun: bool
    frameNeedsClear: bool
    frameClearColor: Color
    readbackBuffer: VulkanBuffer
    readbackBytes: VkDeviceSize
    readbackWidth: int32
    readbackHeight: int32
    readbackReady: bool

    atlasImage: VulkanImage
    backdropImage: VulkanImage
    backdropBlurTempImage: VulkanImage
    backdropLayoutReady: bool
    backdropBlurTempLayoutReady: bool
    backdropWidth: int32
    backdropHeight: int32
    backdropFormat: VkFormat
    backdropBlurFramebuffer: VkFramebuffer
    backdropBlurTempFramebuffer: VkFramebuffer
    blurRenderPass: VkRenderPass
    blurDescriptorSetLayout: VkDescriptorSetLayout
    blurDescriptorSets: array[2, VkDescriptorSet]
    blurPipelineLayout: VkPipelineLayout
    blurPipeline: VkPipeline
    blurVertShader: VkShaderModule
    blurFragShader: VkShaderModule
    atlasSampler: VkSampler

    uploadBlocks: seq[VulkanUploadBlock]
    uploadBlockIndex: int
    uniformAlignment: VkDeviceSize
    frameImages: seq[VulkanImage]
    frameDescriptorPools: seq[VkDescriptorPool]
    descriptorPoolIndex: int
    descriptorSetsUsed: int
    indexBuffer: VulkanBuffer
    indexBufferBytes: VkDeviceSize

    gpuReady: bool

const
  vkNullInstance = VkInstance(0)
  vkNullPhysicalDevice = VkPhysicalDevice(0)
  vkNullDevice = VkDevice(0)
  vkNullQueue = VkQueue(0)
  vkNullSurface = VkSurfaceKHR(0)
  vkNullSwapchain = VkSwapchainKHR(0)
  vkNullRenderPass = VkRenderPass(0)
  vkNullFramebuffer = VkFramebuffer(0)
  vkNullImageView = VkImageView(0)
  vkNullSampler = VkSampler(0)
  vkNullBuffer = VkBuffer(0)
  vkNullMemory = VkDeviceMemory(0)
  vkNullDescriptorSetLayout = VkDescriptorSetLayout(0)
  vkNullDescriptorPool = VkDescriptorPool(0)
  vkNullDescriptorSet = VkDescriptorSet(0)
  vkNullPipelineLayout = VkPipelineLayout(0)
  vkNullPipeline = VkPipeline(0)
  vkNullShaderModule = VkShaderModule(0)
  vkNullCommandPool = VkCommandPool(0)
  vkNullCommandBuffer = VkCommandBuffer(0)
  vkNullSemaphore = VkSemaphore(0)
  vkNullFence = VkFence(0)

when UseVulkanValidation:
  proc printValidation(message: cstring): cint {.importc: "puts", header: "<stdio.h>".}

  proc validationCallback(
      severity: VkDebugUtilsMessageSeverityFlagBitsEXT,
      messageTypes: VkDebugUtilsMessageTypeFlagsEXT,
      data: ptr VkDebugUtilsMessengerCallbackDataEXT,
      userData: pointer,
  ): VkBool32 {.cdecl.} =
    # The layer can call from a driver thread; avoid Nim allocation in the callback.
    if severity == VkDebugUtilsMessageSeverityFlagBitsEXT.ErrorBit:
      discard cast[ptr Atomic[int]](userData)[].fetchAdd(1)
    if data != nil and data.pMessage != nil:
      discard printValidation(data.pMessage)
    VkBool32(VkFalse)

proc validationErrorCount*(ctx: VulkanContext): int =
  ## Number of validation errors reported for this context, including teardown.
  ctx.validationErrors.load()

proc ensureInstance*(ctx: VulkanContext)

proc hasPresentTarget(ctx: VulkanContext): bool =
  ctx.presentTargetKind != presentTargetNone

method hasImage*(ctx: VulkanContext, key: Hash): bool =
  key in ctx.entries

proc tryGetImageRect(ctx: VulkanContext, imageId: Hash, rect: var Rect): bool
proc updateDescriptorSet(ctx: VulkanContext, vsUpload, fsUpload: VulkanUpload)
proc updateBlurDescriptorSet(
  ctx: VulkanContext,
  descriptorSet: VkDescriptorSet,
  srcView: VkImageView,
  uniformUpload: VulkanUpload,
)

proc recreateBlurFramebuffers(ctx: VulkanContext)
proc createImageView(
  ctx: VulkanContext, image: VkImage, format: VkFormat, aspectMask: VkImageAspectFlags
): VkImageView

proc createBuffer(
    ctx: VulkanContext,
    size: VkDeviceSize,
    usage: VkBufferUsageFlags,
    properties: VkMemoryPropertyFlags,
): VulkanBuffer =
  result = newVulkanBuffer(ctx.vk, ctx.device, size)
  let bufferInfo = newVkBufferCreateInfo(
    size = size,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = [],
  )
  result.handle = ctx.vk.createBuffer(ctx.device, bufferInfo)

  let req = ctx.vk.getBufferMemoryRequirements(ctx.device, result.handle)
  let alloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex =
      findMemoryType(ctx.vk, ctx.physicalDevice, req.memoryTypeBits, properties),
  )
  result.allocation = ctx.vk.allocateMemory(ctx.device, alloc)
  ctx.vk.bindBufferMemory(ctx.device, result.handle, result.allocation, 0.VkDeviceSize)

proc allocateFrameUpload(
    ctx: VulkanContext, bytes: VkDeviceSize, alignment = 4.VkDeviceSize
): VulkanUpload =
  # All slices remain immutable until the frame fence has completed.
  while ctx.uploadBlockIndex < ctx.uploadBlocks.len:
    let blockIndex = ctx.uploadBlockIndex
    let offset = (
      (
        (ctx.uploadBlocks[blockIndex].used.uint64 + alignment.uint64 - 1) div
        alignment.uint64
      ) * alignment.uint64
    ).VkDeviceSize
    let buffer = ctx.uploadBlocks[blockIndex].buffer
    if offset + bytes <= buffer.size:
      ctx.uploadBlocks[blockIndex].used = offset + bytes
      return VulkanUpload(
        buffer: buffer,
        offset: offset,
        size: bytes,
        data: cast[pointer](cast[uint](buffer.mapped) + offset.uint),
      )
    inc ctx.uploadBlockIndex
  let buffer = ctx.createBuffer(
    max(bytes, (4 * 1024 * 1024).VkDeviceSize),
    VkBufferUsageFlags{TransferSrcBit, VertexBufferBit, UniformBufferBit},
    VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  buffer.mapped = ctx.vk.mapMemory(
    ctx.device, buffer.allocation, 0.VkDeviceSize, buffer.size, 0.VkMemoryMapFlags
  )
  ctx.uploadBlocks.add(VulkanUploadBlock(buffer: buffer, used: bytes))
  VulkanUpload(buffer: buffer, size: bytes, data: buffer.mapped)

proc allocateFrameDescriptorSet(
    ctx: VulkanContext, layout: VkDescriptorSetLayout
): VkDescriptorSet =
  const setsPerPool = 128
  if ctx.descriptorSetsUsed == setsPerPool:
    inc ctx.descriptorPoolIndex
    ctx.descriptorSetsUsed = 0
  if ctx.descriptorPoolIndex == ctx.frameDescriptorPools.len:
    let sizes = [
      newVkDescriptorPoolSize(
        `type` = VkDescriptorType.UniformBuffer, descriptorCount = setsPerPool * 2
      ),
      newVkDescriptorPoolSize(
        `type` = VkDescriptorType.CombinedImageSampler,
        descriptorCount = setsPerPool * 3,
      ),
    ]
    ctx.frameDescriptorPools.add(
      ctx.vk.createDescriptorPool(
        ctx.device,
        newVkDescriptorPoolCreateInfo(maxSets = setsPerPool, poolSizes = sizes),
      )
    )
  result = ctx.vk.allocateDescriptorSets(
    ctx.device,
    newVkDescriptorSetAllocateInfo(
      descriptorPool = ctx.frameDescriptorPools[ctx.descriptorPoolIndex],
      setLayouts = [layout],
    ),
  )
  inc ctx.descriptorSetsUsed

proc writeBlurUniforms(
    ctx: VulkanContext, texelStep: Vec2, blurRadius: float32
): VulkanUpload =
  result =
    ctx.allocateFrameUpload(sizeof(BlurUniforms).VkDeviceSize, ctx.uniformAlignment)
  var uniforms = BlurUniforms(texelStep: texelStep, blurRadius: blurRadius)
  copyMem(result.data, uniforms.addr, sizeof(uniforms))

proc createPresentSurface(ctx: VulkanContext) =
  if not ctx.hasPresentTarget() or ctx.instance == vkNullInstance:
    return
  if ctx.surface != vkNullSurface:
    return

  case ctx.presentTargetKind
  of presentTargetXlib:
    when defined(linux) or defined(bsd):
      case ctx.linuxSurfaceKind
      of linuxSurfaceXcb:
        let fnPtr = vkGetInstanceProcAddrNative(ctx.instance, "vkCreateXcbSurfaceKHR")
        if fnPtr.isNil:
          raise newException(ValueError, "vkCreateXcbSurfaceKHR unavailable")
        let xcbConn = XGetXCBConnection(ctx.presentXlibDisplay)
        if xcbConn.isNil:
          raise newException(
            ValueError, "XGetXCBConnection returned nil for Vulkan XCB surface"
          )
        let vkCreateXcbSurfaceKHRNative = cast[VkCreateXcbSurfaceKHRNativeProc](fnPtr)
        var createInfo = VkXcbSurfaceCreateInfoKHRNative(
          sType: VkStructureType.XcbSurfaceCreateInfoKHR,
          pNext: nil,
          flags: 0.VkXcbSurfaceCreateFlagsKHR,
          connection: xcbConn,
          window: uint32(ctx.presentXlibWindow),
        )
        debug "Creating Vulkan XCB surface",
          window = ctx.presentXlibWindow, xcbConnection = cast[uint64](xcbConn)
        checkVkResult vkCreateXcbSurfaceKHRNative(
          ctx.instance, createInfo.addr, nil, ctx.surface.addr
        )
        ctx.surfaceOwnedByContext = true
      of linuxSurfaceXlib:
        let fnPtr = vkGetInstanceProcAddrNative(ctx.instance, "vkCreateXlibSurfaceKHR")
        if fnPtr.isNil:
          raise newException(ValueError, "vkCreateXlibSurfaceKHR unavailable")
        let vkCreateXlibSurfaceKHRNative = cast[VkCreateXlibSurfaceKHRNativeProc](fnPtr)
        var createInfo = VkXlibSurfaceCreateInfoKHRNative(
          sType: VkStructureType.XlibSurfaceCreateInfoKHR,
          pNext: nil,
          flags: 0.VkXlibSurfaceCreateFlagsKHR,
          dpy: ctx.presentXlibDisplay,
          window: culong(ctx.presentXlibWindow),
        )
        debug "Creating Vulkan XLIB surface",
          window = ctx.presentXlibWindow,
          xlibDisplay = cast[uint64](ctx.presentXlibDisplay)
        checkVkResult vkCreateXlibSurfaceKHRNative(
          ctx.instance, createInfo.addr, nil, ctx.surface.addr
        )
        ctx.surfaceOwnedByContext = true
    else:
      raise newException(ValueError, "Xlib Vulkan surface unsupported on this OS")
  of presentTargetWayland:
    when defined(linux) or defined(bsd):
      let createInfo = newVkWaylandSurfaceCreateInfoKHR(
        display = cast[ptr wl_display](ctx.presentWaylandDisplay),
        surface = cast[ptr wl_surface](ctx.presentWaylandSurface),
      )
      checkVkResult ctx.vk.vkCreateWaylandSurfaceKHR(
        ctx.instance, createInfo.unsafeAddr, nil, ctx.surface.addr
      )
      ctx.surfaceOwnedByContext = true
    else:
      raise newException(ValueError, "Wayland Vulkan surface unsupported on this OS")
  of presentTargetWin32:
    when defined(windows):
      let createInfo = newVkWin32SurfaceCreateInfoKHR(
        hinstance = cast[HINSTANCE](cast[uint](ctx.presentWin32Hinstance)),
        hwnd = cast[HWND](cast[uint](ctx.presentWin32Hwnd)),
      )
      checkVkResult ctx.vk.vkCreateWin32SurfaceKHR(
        ctx.instance, createInfo.addr, nil, ctx.surface.addr
      )
      ctx.surfaceOwnedByContext = true
    else:
      raise newException(ValueError, "Win32 Vulkan surface unsupported on this OS")
  of presentTargetMetal:
    when defined(macosx):
      let createInfo = newVkMetalSurfaceCreateInfoEXT(
        pLayer = cast[ptr CAMetalLayer](ctx.presentMetalLayer)
      )
      checkVkResult ctx.vk.vkCreateMetalSurfaceEXT(
        ctx.instance, createInfo.addr, nil, ctx.surface.addr
      )
      ctx.surfaceOwnedByContext = true
    else:
      raise newException(ValueError, "Metal Vulkan surface unsupported on this OS")
  of presentTargetNone:
    discard

proc createImage(
    ctx: VulkanContext,
    width, height: uint32,
    format: VkFormat,
    tiling: VkImageTiling,
    usage: VkImageUsageFlags,
    properties: VkMemoryPropertyFlags,
): VulkanImage =
  result = newVulkanImage(ctx.vk, ctx.device)
  let info = newVkImageCreateInfo(
    imageType = VK_IMAGE_TYPE_2D,
    format = format,
    extent = newVkExtent3D(width = width, height = height, depth = 1),
    mipLevels = 1,
    arrayLayers = 1,
    samples = VK_SAMPLE_COUNT_1_BIT,
    tiling = tiling,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = [],
    initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
  )
  checkVkResult ctx.vk.vkCreateImage(ctx.device, info.addr, nil, result.handle.addr)

  var req: VkMemoryRequirements
  ctx.vk.vkGetImageMemoryRequirements(ctx.device, result.handle, req.addr)
  let alloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex =
      findMemoryType(ctx.vk, ctx.physicalDevice, req.memoryTypeBits, properties),
  )
  checkVkResult ctx.vk.vkAllocateMemory(
    ctx.device, alloc.addr, nil, result.allocation.addr
  )
  checkVkResult ctx.vk.vkBindImageMemory(
    ctx.device, result.handle, result.allocation, 0.VkDeviceSize
  )
  result.view = ctx.createImageView(result.handle, format, VkImageAspectFlags{ColorBit})

proc createImageView(
    ctx: VulkanContext, image: VkImage, format: VkFormat, aspectMask: VkImageAspectFlags
): VkImageView =
  let info = newVkImageViewCreateInfo(
    image = image,
    viewType = VK_IMAGE_VIEW_TYPE_2D,
    format = format,
    components = newVkComponentMapping(
      VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
      VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
    ),
    subresourceRange = newVkImageSubresourceRange(
      aspectMask = aspectMask,
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  checkVkResult ctx.vk.vkCreateImageView(ctx.device, info.addr, nil, result.addr)

proc recreateBlurFramebuffers(ctx: VulkanContext) =
  vulkanBlurRecreateFramebuffers(ctx)

proc ensureBackdropImage(ctx: VulkanContext, width, height: int32) =
  let w = max(1'i32, width)
  let h = max(1'i32, height)
  let backdropFormat =
    if ctx.swapchainFormat != VK_FORMAT_UNDEFINED:
      ctx.swapchainFormat
    else:
      VK_FORMAT_B8G8R8A8_UNORM
  if not ctx.backdropImage.isNilOrEmpty and ctx.backdropImage.view != vkNullImageView and
      not ctx.backdropBlurTempImage.isNilOrEmpty and
      ctx.backdropBlurTempImage.view != vkNullImageView and ctx.backdropWidth == w and
      ctx.backdropHeight == h and ctx.backdropFormat == backdropFormat:
    return

  if ctx.backdropBlurFramebuffer != vkNullFramebuffer:
    ctx.vk.vkDestroyFramebuffer(ctx.device, ctx.backdropBlurFramebuffer, nil)
    ctx.backdropBlurFramebuffer = vkNullFramebuffer
  if ctx.backdropBlurTempFramebuffer != vkNullFramebuffer:
    ctx.vk.vkDestroyFramebuffer(ctx.device, ctx.backdropBlurTempFramebuffer, nil)
    ctx.backdropBlurTempFramebuffer = vkNullFramebuffer

  ctx.backdropBlurTempImage = nil
  ctx.backdropImage = nil

  let backdropAlloc = ctx.createImage(
    width = w.uint32,
    height = h.uint32,
    format = backdropFormat,
    tiling = VK_IMAGE_TILING_OPTIMAL,
    usage = VkImageUsageFlags{SampledBit, TransferDstBit, ColorAttachmentBit},
    properties = VkMemoryPropertyFlags{DeviceLocalBit},
  )
  let backdropTempAlloc = ctx.createImage(
    width = w.uint32,
    height = h.uint32,
    format = backdropFormat,
    tiling = VK_IMAGE_TILING_OPTIMAL,
    usage = VkImageUsageFlags{SampledBit, ColorAttachmentBit},
    properties = VkMemoryPropertyFlags{DeviceLocalBit},
  )
  ctx.backdropImage = backdropAlloc
  ctx.backdropBlurTempImage = backdropTempAlloc
  ctx.backdropLayoutReady = false
  ctx.backdropBlurTempLayoutReady = false
  ctx.backdropWidth = w
  ctx.backdropHeight = h
  ctx.backdropFormat = backdropFormat
  ctx.recreateBlurFramebuffers()

proc fullFrameRect(ctx: VulkanContext): Rect =
  rect(0.0'f32, 0.0'f32, ctx.frameSize.x, ctx.frameSize.y)

proc destroyRetiredSwapchain(ctx: VulkanContext, retired: RetiredSwapchain) =
  for fb in retired.framebuffers:
    if fb != vkNullFramebuffer:
      ctx.vk.vkDestroyFramebuffer(ctx.device, fb, nil)

  for view in retired.views:
    if view != vkNullImageView:
      ctx.vk.vkDestroyImageView(ctx.device, view, nil)

  for semaphore in retired.semaphores:
    ctx.vk.vkDestroySemaphore(ctx.device, semaphore, nil)

  if retired.swapchain != vkNullSwapchain:
    ctx.vk.vkDestroySwapchainKHR(ctx.device, retired.swapchain, nil)

proc destroyRetiredSwapchains(ctx: VulkanContext, onlyCompleted = false) =
  var remaining: seq[RetiredSwapchain]
  for retired in ctx.retiredSwapchains:
    if not onlyCompleted or retired.awaitingFrameFence:
      ctx.destroyRetiredSwapchain(retired)
    else:
      remaining.add(retired)
  ctx.retiredSwapchains = move(remaining)

proc retireSwapchain(ctx: VulkanContext) =
  # Reacquiring the first replacement presentation proves retirement, following
  # https://docs.vulkan.org/samples/latest/samples/api/swapchain_recreation/README.html
  if ctx.swapchain == vkNullSwapchain:
    return

  ctx.retiredSwapchains.add(
    RetiredSwapchain(
      swapchain: ctx.swapchain,
      views: ctx.swapchainViews,
      framebuffers: ctx.swapchainFramebuffers,
      semaphores: ctx.renderFinishedSemaphores,
      replacementImage: -1,
    )
  )
  ctx.swapchain = vkNullSwapchain
  ctx.renderFinishedSemaphores.setLen(0)
  ctx.swapchainFramebuffers.setLen(0)
  ctx.swapchainViews.setLen(0)
  ctx.swapchainImages.setLen(0)

proc destroySwapchain(ctx: VulkanContext) =
  for fb in ctx.swapchainFramebuffers:
    if fb != vkNullFramebuffer:
      ctx.vk.vkDestroyFramebuffer(ctx.device, fb, nil)
  ctx.swapchainFramebuffers.setLen(0)

  for view in ctx.swapchainViews:
    if view != vkNullImageView:
      ctx.vk.vkDestroyImageView(ctx.device, view, nil)
  ctx.swapchainViews.setLen(0)
  ctx.swapchainImages.setLen(0)

  for semaphore in ctx.renderFinishedSemaphores:
    ctx.vk.vkDestroySemaphore(ctx.device, semaphore, nil)
  ctx.renderFinishedSemaphores.setLen(0)

  if ctx.swapchain != vkNullSwapchain:
    ctx.vk.vkDestroySwapchainKHR(ctx.device, ctx.swapchain, nil)
    ctx.swapchain = vkNullSwapchain

proc destroyPipelineObjects(ctx: VulkanContext) =
  if ctx.backdropBlurFramebuffer != vkNullFramebuffer:
    ctx.vk.vkDestroyFramebuffer(ctx.device, ctx.backdropBlurFramebuffer, nil)
    ctx.backdropBlurFramebuffer = vkNullFramebuffer
  if ctx.backdropBlurTempFramebuffer != vkNullFramebuffer:
    ctx.vk.vkDestroyFramebuffer(ctx.device, ctx.backdropBlurTempFramebuffer, nil)
    ctx.backdropBlurTempFramebuffer = vkNullFramebuffer

  if ctx.blurPipeline != vkNullPipeline:
    ctx.vk.vkDestroyPipeline(ctx.device, ctx.blurPipeline, nil)
    ctx.blurPipeline = vkNullPipeline
  if ctx.blurPipelineLayout != vkNullPipelineLayout:
    ctx.vk.vkDestroyPipelineLayout(ctx.device, ctx.blurPipelineLayout, nil)
    ctx.blurPipelineLayout = vkNullPipelineLayout
  if ctx.blurRenderPass != vkNullRenderPass:
    ctx.vk.vkDestroyRenderPass(ctx.device, ctx.blurRenderPass, nil)
    ctx.blurRenderPass = vkNullRenderPass

  if ctx.pipeline != vkNullPipeline:
    ctx.vk.vkDestroyPipeline(ctx.device, ctx.pipeline, nil)
    ctx.pipeline = vkNullPipeline
  if ctx.pipelineLayout != vkNullPipelineLayout:
    ctx.vk.vkDestroyPipelineLayout(ctx.device, ctx.pipelineLayout, nil)
    ctx.pipelineLayout = vkNullPipelineLayout
  if ctx.renderPass != vkNullRenderPass:
    ctx.vk.vkDestroyRenderPass(ctx.device, ctx.renderPass, nil)
    ctx.renderPass = vkNullRenderPass

proc updateDescriptorSet(ctx: VulkanContext, vsUpload, fsUpload: VulkanUpload) =
  var vsInfo = newVkDescriptorBufferInfo(
    buffer = vsUpload.buffer.handle,
    offset = vsUpload.offset,
    range = VkDeviceSize(sizeof(VSUniforms)),
  )
  var fsInfo = newVkDescriptorBufferInfo(
    buffer = fsUpload.buffer.handle,
    offset = fsUpload.offset,
    range = VkDeviceSize(sizeof(FSUniforms)),
  )
  var atlasImageInfo = newVkDescriptorImageInfo(
    sampler = ctx.atlasSampler,
    imageView = ctx.atlasImage.view,
    imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
  )
  var backdropImageInfo = newVkDescriptorImageInfo(
    sampler = ctx.atlasSampler,
    imageView =
      if not ctx.backdropImage.isNilOrEmpty:
        ctx.backdropImage.view
      else:
        ctx.atlasImage.view,
    imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
  )

  let writes = [
    newVkWriteDescriptorSet(
      dstSet = ctx.descriptorSet,
      dstBinding = 0,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      pImageInfo = nil,
      pBufferInfo = vsInfo.addr,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.descriptorSet,
      dstBinding = 1,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      pImageInfo = nil,
      pBufferInfo = fsInfo.addr,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.descriptorSet,
      dstBinding = 2,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      pImageInfo = atlasImageInfo.addr,
      pBufferInfo = nil,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.descriptorSet,
      dstBinding = 3,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      pImageInfo = atlasImageInfo.addr,
      pBufferInfo = nil,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.descriptorSet,
      dstBinding = 4,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      pImageInfo = backdropImageInfo.addr,
      pBufferInfo = nil,
      pTexelBufferView = nil,
    ),
  ]
  ctx.vk.updateDescriptorSets(ctx.device, writes, [])

proc updateBlurDescriptorSet(
    ctx: VulkanContext,
    descriptorSet: VkDescriptorSet,
    srcView: VkImageView,
    uniformUpload: VulkanUpload,
) =
  vulkanBlurUpdateDescriptorSet(ctx, descriptorSet, srcView, uniformUpload)

proc createBlurPipeline(ctx: VulkanContext) =
  vulkanBlurCreatePipeline(ctx)

proc recreateAtlasGpu(ctx: VulkanContext) =
  if ctx.atlasSize >
      ctx.vk.getPhysicalDeviceProperties(ctx.physicalDevice).limits.maxImageDimension2D.int:
    raise newException(ValueError, "Vulkan atlas exceeds the device image limit")
  let atlasAlloc = ctx.createImage(
    width = ctx.atlasSize.uint32,
    height = ctx.atlasSize.uint32,
    format = VK_FORMAT_R8G8B8A8_UNORM,
    tiling = VK_IMAGE_TILING_OPTIMAL,
    usage = VkImageUsageFlags{SampledBit, TransferDstBit},
    properties = VkMemoryPropertyFlags{DeviceLocalBit},
  )
  if not ctx.atlasImage.isNil:
    ctx.frameImages.add(ctx.atlasImage)
  ctx.atlasImage = atlasAlloc
  ctx.atlasDirty = true
  ctx.atlasLayoutReady = false

proc createPipeline(ctx: VulkanContext) =
  ctx.destroyPipelineObjects()

  var colorAttachment = VkAttachmentDescription(
    flags: 0.VkAttachmentDescriptionFlags,
    format: ctx.swapchainFormat,
    samples: VK_SAMPLE_COUNT_1_BIT,
    loadOp: VK_ATTACHMENT_LOAD_OP_LOAD,
    storeOp: VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
  )
  var colorAttachmentRef = VkAttachmentReference(
    attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
  )
  var subpass = VkSubpassDescription(
    flags: 0.VkSubpassDescriptionFlags,
    pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
    inputAttachmentCount: 0,
    pInputAttachments: nil,
    colorAttachmentCount: 1,
    pColorAttachments: colorAttachmentRef.addr,
    pResolveAttachments: nil,
    pDepthStencilAttachment: nil,
    preserveAttachmentCount: 0,
    pPreserveAttachments: nil,
  )
  var dependency = VkSubpassDependency(
    srcSubpass: VK_SUBPASS_EXTERNAL,
    dstSubpass: 0,
    srcStageMask: VkPipelineStageFlags{ColorAttachmentOutputBit},
    dstStageMask: VkPipelineStageFlags{ColorAttachmentOutputBit},
    srcAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
    dstAccessMask: VkAccessFlags{ColorAttachmentReadBit, ColorAttachmentWriteBit},
    dependencyFlags: 0.VkDependencyFlags,
  )

  let renderPassInfo = newVkRenderPassCreateInfo(
    attachments = [colorAttachment], subpasses = [subpass], dependencies = [dependency]
  )
  checkVkResult ctx.vk.vkCreateRenderPass(
    ctx.device, renderPassInfo.addr, nil, ctx.renderPass.addr
  )

  if ctx.vertShader == vkNullShaderModule:
    let vertInfo = newVkShaderModuleCreateInfo(code = sdfVertSpv)
    ctx.vertShader = ctx.vk.createShaderModule(ctx.device, vertInfo)
  if ctx.fragShader == vkNullShaderModule:
    let fragInfo = newVkShaderModuleCreateInfo(code = sdfFragSpv)
    ctx.fragShader = ctx.vk.createShaderModule(ctx.device, fragInfo)

  let vertStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.VertexBit,
    module = ctx.vertShader,
    pName = "main",
    pSpecializationInfo = nil,
  )
  let fragStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.FragmentBit,
    module = ctx.fragShader,
    pName = "main",
    pSpecializationInfo = nil,
  )

  let bindingDesc = VkVertexInputBindingDescription(
    binding: 0, stride: uint32(sizeof(Vertex)), inputRate: VK_VERTEX_INPUT_RATE_VERTEX
  )

  let attrDescs = [
    VkVertexInputAttributeDescription(
      location: 0,
      binding: 0,
      format: VK_FORMAT_R32G32_SFLOAT,
      offset: uint32(offsetOf(Vertex, pos)),
    ),
    VkVertexInputAttributeDescription(
      location: 1,
      binding: 0,
      format: VK_FORMAT_R32G32_SFLOAT,
      offset: uint32(offsetOf(Vertex, uv)),
    ),
    VkVertexInputAttributeDescription(
      location: 2,
      binding: 0,
      format: VK_FORMAT_R8G8B8A8_UNORM,
      offset: uint32(offsetOf(Vertex, color)),
    ),
    VkVertexInputAttributeDescription(
      location: 3,
      binding: 0,
      format: VK_FORMAT_R8G8B8A8_UNORM,
      offset: uint32(offsetOf(Vertex, fillMidColor)),
    ),
    VkVertexInputAttributeDescription(
      location: 4,
      binding: 0,
      format: VK_FORMAT_R8G8B8A8_UNORM,
      offset: uint32(offsetOf(Vertex, fillStopColor)),
    ),
    VkVertexInputAttributeDescription(
      location: 5,
      binding: 0,
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfParams)),
    ),
    VkVertexInputAttributeDescription(
      location: 6,
      binding: 0,
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfRadii)),
    ),
    VkVertexInputAttributeDescription(
      location: 7,
      binding: 0,
      format: VK_FORMAT_R16_UINT,
      offset: uint32(offsetOf(Vertex, sdfMode)),
    ),
    VkVertexInputAttributeDescription(
      location: 8,
      binding: 0,
      format: VK_FORMAT_R32G32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfFactors)),
    ),
    VkVertexInputAttributeDescription(
      location: 9,
      binding: 0,
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, rectMaskParams)),
    ),
    VkVertexInputAttributeDescription(
      location: 10,
      binding: 0,
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, rectMaskRadii)),
    ),
    VkVertexInputAttributeDescription(
      location: 11,
      binding: 0,
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, rectMaskMatX)),
    ),
    VkVertexInputAttributeDescription(
      location: 12,
      binding: 0,
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, rectMaskMatY)),
    ),
  ]

  let vertexInputInfo = newVkPipelineVertexInputStateCreateInfo(
    vertexBindingDescriptions = [bindingDesc], vertexAttributeDescriptions = attrDescs
  )

  let inputAssembly = VkPipelineInputAssemblyStateCreateInfo(
    sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    pNext: nil,
    flags: 0.VkPipelineInputAssemblyStateCreateFlags,
    topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    primitiveRestartEnable: VkBool32(VkFalse),
  )

  let viewportState = VkPipelineViewportStateCreateInfo(
    sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    pNext: nil,
    flags: 0.VkPipelineViewportStateCreateFlags,
    viewportCount: 1,
    pViewports: nil,
    scissorCount: 1,
    pScissors: nil,
  )

  let rasterizer = VkPipelineRasterizationStateCreateInfo(
    sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    pNext: nil,
    flags: 0.VkPipelineRasterizationStateCreateFlags,
    depthClampEnable: VkBool32(VkFalse),
    rasterizerDiscardEnable: VkBool32(VkFalse),
    polygonMode: VK_POLYGON_MODE_FILL,
    cullMode: 0.VkCullModeFlags,
    frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VkBool32(VkFalse),
    depthBiasConstantFactor: 0,
    depthBiasClamp: 0,
    depthBiasSlopeFactor: 0,
    lineWidth: 1.0,
  )

  let multisampling = VkPipelineMultisampleStateCreateInfo(
    sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    pNext: nil,
    flags: 0.VkPipelineMultisampleStateCreateFlags,
    rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
    sampleShadingEnable: VkBool32(VkFalse),
    minSampleShading: 1.0,
    pSampleMask: nil,
    alphaToCoverageEnable: VkBool32(VkFalse),
    alphaToOneEnable: VkBool32(VkFalse),
  )

  let colorBlendAttachment = newVkPipelineColorBlendAttachmentState(
    blendEnable = VkBool32(VkTrue),
    srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
    dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
    colorBlendOp = VK_BLEND_OP_ADD,
    srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
    dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
    alphaBlendOp = VK_BLEND_OP_ADD,
    colorWriteMask = VkColorComponentFlags{RBit, GBit, BBit, ABit},
  )

  let colorBlending = VkPipelineColorBlendStateCreateInfo(
    sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    pNext: nil,
    flags: 0.VkPipelineColorBlendStateCreateFlags,
    logicOpEnable: VkBool32(VkFalse),
    logicOp: VK_LOGIC_OP_COPY,
    attachmentCount: 1,
    pAttachments: colorBlendAttachment.unsafeAddr,
    blendConstants: [0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32],
  )

  let dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR]
  let dynamicState = VkPipelineDynamicStateCreateInfo(
    sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    pNext: nil,
    flags: 0.VkPipelineDynamicStateCreateFlags,
    dynamicStateCount: dynamicStates.len.uint32,
    pDynamicStates: dynamicStates[0].unsafeAddr,
  )

  let pipelineLayoutInfo = newVkPipelineLayoutCreateInfo(
    setLayouts = [ctx.descriptorSetLayout], pushConstantRanges = []
  )
  ctx.pipelineLayout = ctx.vk.createPipelineLayout(ctx.device, pipelineLayoutInfo)

  let pipelineInfo = newVkGraphicsPipelineCreateInfo(
    stages = [vertStage, fragStage],
    pVertexInputState = unsafeAddr vertexInputInfo,
    pInputAssemblyState = unsafeAddr inputAssembly,
    pTessellationState = nil,
    pViewportState = unsafeAddr viewportState,
    pRasterizationState = unsafeAddr rasterizer,
    pMultisampleState = unsafeAddr multisampling,
    pDepthStencilState = nil,
    pColorBlendState = unsafeAddr colorBlending,
    pDynamicState = unsafeAddr dynamicState,
    layout = ctx.pipelineLayout,
    renderPass = ctx.renderPass,
    subpass = 0,
    basePipelineHandle = 0.VkPipeline,
    basePipelineIndex = -1,
  )
  checkVkResult ctx.vk.vkCreateGraphicsPipelines(
    ctx.device, 0.VkPipelineCache, 1, pipelineInfo.addr, nil, ctx.pipeline.addr
  )

proc createSwapchain(ctx: VulkanContext, width, height: int32) =
  if ctx.surface == vkNullSurface:
    return

  let support = querySwapChainSupport(ctx.vk, ctx.physicalDevice, ctx.surface)
  let config = chooseSwapchainConfig(
    support, width, height, ctx.requestedSwapchainProfile, ctx.driverInfo
  )

  let
    replacingSwapchain = ctx.swapchain != vkNullSwapchain
    oldSwapchain = ctx.swapchain
    pipelineNeedsRecreate =
      ctx.swapchainFormat != config.surfaceFormat.format or
      ctx.renderPass == vkNullRenderPass or ctx.pipeline == vkNullPipeline or
      ctx.pipelineLayout == vkNullPipelineLayout or
      ctx.blurRenderPass == vkNullRenderPass or ctx.blurPipeline == vkNullPipeline or
      ctx.blurPipelineLayout == vkNullPipelineLayout

  let queueFamilyIndices =
    if ctx.queueFamily != ctx.presentQueueFamily:
      @[ctx.queueFamily, ctx.presentQueueFamily]
    else:
      @[]

  ctx.swapchainTransferSrcSupported = config.transferSrcEnabled
  if not config.transferSrcEnabled:
    warn "Vulkan swapchain does not support transfer src; readPixels disabled"

  var createInfo = newVkSwapchainCreateInfoKHR(
    surface = ctx.surface,
    minImageCount = config.imageCount,
    imageFormat = config.surfaceFormat.format,
    imageColorSpace = config.surfaceFormat.colorSpace,
    imageExtent = config.extent,
    imageArrayLayers = 1,
    imageUsage = config.imageUsage,
    imageSharingMode =
      if queueFamilyIndices.len > 0:
        VK_SHARING_MODE_CONCURRENT
      else:
        VK_SHARING_MODE_EXCLUSIVE,
    queueFamilyIndices = queueFamilyIndices,
    preTransform = support.capabilities.currentTransform,
    compositeAlpha = config.compositeAlpha,
    presentMode = config.presentMode,
    clipped = VkBool32(VkTrue),
    oldSwapchain = oldSwapchain,
  )

  var newSwapchain: VkSwapchainKHR
  checkVkResult ctx.vk.vkCreateSwapchainKHR(
    ctx.device, createInfo.addr, nil, newSwapchain.addr
  )

  ctx.retireSwapchain()
  # If the replacement is itself resized before reacquisition, use a later
  # presentation on the new swapchain as the retirement witness.
  for retired in ctx.retiredSwapchains.mitems:
    if not retired.awaitingFrameFence:
      retired.replacementImage = -1
  ctx.swapchain = newSwapchain
  ctx.activeSwapchainProfile = config.profile

  var actualCount = config.imageCount
  discard
    ctx.vk.vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, actualCount.addr, nil)
  ctx.swapchainImages.setLen(actualCount)
  if actualCount > 0:
    discard ctx.vk.vkGetSwapchainImagesKHR(
      ctx.device, ctx.swapchain, actualCount.addr, ctx.swapchainImages[0].addr
    )

  ctx.renderFinishedSemaphores.setLen(actualCount)
  let semaphoreInfo = newVkSemaphoreCreateInfo()
  for semaphore in ctx.renderFinishedSemaphores.mitems:
    checkVkResult ctx.vk.vkCreateSemaphore(
      ctx.device, semaphoreInfo.addr, nil, semaphore.addr
    )

  ctx.swapchainViews.setLen(actualCount)
  for i in 0 ..< actualCount.int:
    ctx.swapchainViews[i] = ctx.createImageView(
      ctx.swapchainImages[i], config.surfaceFormat.format, VkImageAspectFlags{ColorBit}
    )

  ctx.swapchainFormat = config.surfaceFormat.format
  ctx.swapchainExtent = config.extent
  ctx.swapchainRequestedWidth = width
  ctx.swapchainRequestedHeight = height
  ctx.swapchainOutOfDate = false

  if pipelineNeedsRecreate:
    ctx.createPipeline()
    ctx.createBlurPipeline()

  ctx.swapchainFramebuffers.setLen(ctx.swapchainViews.len)
  for i in 0 ..< ctx.swapchainViews.len:
    let info = newVkFramebufferCreateInfo(
      renderPass = ctx.renderPass,
      attachments = [ctx.swapchainViews[i]],
      width = ctx.swapchainExtent.width,
      height = ctx.swapchainExtent.height,
      layers = 1,
    )
    checkVkResult ctx.vk.vkCreateFramebuffer(
      ctx.device, info.addr, nil, ctx.swapchainFramebuffers[i].addr
    )

  if replacingSwapchain:
    debug "Recreated Vulkan swapchain",
      width = int(ctx.swapchainExtent.width),
      height = int(ctx.swapchainExtent.height),
      imageCount = ctx.swapchainImages.len,
      format = $ctx.swapchainFormat,
      presentMode = $config.presentMode,
      profile = $config.profile
  else:
    info "Created Vulkan swapchain",
      width = int(ctx.swapchainExtent.width),
      height = int(ctx.swapchainExtent.height),
      imageCount = ctx.swapchainImages.len,
      format = $ctx.swapchainFormat,
      presentMode = $config.presentMode,
      profile = $config.profile

proc recycleFrameResources(ctx: VulkanContext) =
  ## Called only after the preceding graphics submission has finished.
  ctx.frameImages.setLen(0)
  for uploadBlock in ctx.uploadBlocks.mitems:
    uploadBlock.used = 0.VkDeviceSize
  ctx.uploadBlockIndex = 0
  for pool in ctx.frameDescriptorPools:
    checkVkResult ctx.vk.vkResetDescriptorPool(
      ctx.device, pool, 0.VkDescriptorPoolResetFlags
    )
  ctx.descriptorPoolIndex = 0
  ctx.descriptorSetsUsed = 0
  ctx.descriptorSet = vkNullDescriptorSet
  ctx.blurDescriptorSets = [vkNullDescriptorSet, vkNullDescriptorSet]

proc ensureSwapchain(ctx: VulkanContext, width, height: int32) =
  if not ctx.presentReady or width <= 0 or height <= 0:
    return

  let sizeChanged =
    ctx.swapchainRequestedWidth != width or ctx.swapchainRequestedHeight != height
  let needsRecreate =
    ctx.swapchain == vkNullSwapchain or ctx.swapchainOutOfDate or sizeChanged
  if not needsRecreate:
    return

  if ctx.device != vkNullDevice:
    discard ctx.vk.vkDeviceWaitIdle(ctx.device)
    ctx.recycleFrameResources()
    ctx.destroyRetiredSwapchains(onlyCompleted = true)
  ctx.createSwapchain(width, height)

proc ensureReadbackBuffer(ctx: VulkanContext, bytes: VkDeviceSize) =
  if not ctx.readbackBuffer.isNilOrEmpty and ctx.readbackBytes >= bytes:
    return

  ctx.readbackBuffer = nil

  let alloc = ctx.createBuffer(
    size = bytes,
    usage = VkBufferUsageFlags{TransferDstBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.readbackBuffer = alloc
  ctx.readbackBytes = bytes

proc recordAtlasUpload(ctx: VulkanContext, cmd: VkCommandBuffer) =
  let bytes = VkDeviceSize(ctx.atlasSize * ctx.atlasSize * 4)
  let upload = ctx.allocateFrameUpload(bytes)
  copyMem(upload.data, ctx.atlasPixels.data[0].addr, int(bytes))

  let atlasOldLayout =
    if ctx.atlasLayoutReady:
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    else:
      VK_IMAGE_LAYOUT_UNDEFINED
  let atlasSrcAccess =
    if ctx.atlasLayoutReady:
      VkAccessFlags{ShaderReadBit}
    else:
      0.VkAccessFlags
  let atlasSrcStage =
    if ctx.atlasLayoutReady:
      VkPipelineStageFlags{FragmentShaderBit}
    else:
      VkPipelineStageFlags{TopOfPipeBit}

  var barrierToTransfer = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: atlasSrcAccess,
    dstAccessMask: VkAccessFlags{TransferWriteBit},
    oldLayout: atlasOldLayout,
    newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.atlasImage.handle,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  ctx.vk.vkCmdPipelineBarrier(
    cmd,
    atlasSrcStage,
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
    bufferOffset: upload.offset,
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
      width = ctx.atlasSize.uint32, height = ctx.atlasSize.uint32, depth = 1
    ),
  )
  ctx.vk.vkCmdCopyBufferToImage(
    cmd, upload.buffer.handle, ctx.atlasImage.handle,
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, region.addr,
  )

  var barrierToRead = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{TransferWriteBit},
    dstAccessMask: VkAccessFlags{ShaderReadBit},
    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.atlasImage.handle,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  ctx.vk.vkCmdPipelineBarrier(
    cmd,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{FragmentShaderBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    barrierToRead.addr,
  )

  ctx.atlasDirty = false
  ctx.atlasLayoutReady = true

proc recordSwapchainReadback(ctx: VulkanContext) =
  if not ctx.swapchainTransferSrcSupported:
    return
  if ctx.swapchainImages.len == 0:
    return

  let width = int32(ctx.swapchainExtent.width)
  let height = int32(ctx.swapchainExtent.height)
  if width <= 0 or height <= 0:
    return

  let readbackBytes = VkDeviceSize(width * height * 4)
  ctx.ensureReadbackBuffer(readbackBytes)

  let swapchainImage = ctx.swapchainImages[ctx.acquiredImageIndex.int]
  var imageToTransfer = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
    dstAccessMask: VkAccessFlags{TransferReadBit},
    oldLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
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
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer,
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
      width = ctx.swapchainExtent.width, height = ctx.swapchainExtent.height, depth = 1
    ),
  )
  ctx.vk.vkCmdCopyImageToBuffer(
    ctx.commandBuffer, swapchainImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    ctx.readbackBuffer.handle, 1, copyRegion.addr,
  )

  var readbackBarrier = VkBufferMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{TransferWriteBit},
    dstAccessMask: VkAccessFlags{HostReadBit},
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    buffer: ctx.readbackBuffer.handle,
    offset: 0.VkDeviceSize,
    size: readbackBytes,
  )
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer,
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
    dstAccessMask: VkAccessFlags{ColorAttachmentReadBit, ColorAttachmentWriteBit},
    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    newLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
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
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    imageToPresent.addr,
  )

  ctx.readbackWidth = width
  ctx.readbackHeight = height
  ctx.readbackReady = true

proc createInstanceWithFallback(ctx: VulkanContext): VkInstance =
  if ctx.vk.isNil:
    ctx.vk = newVulkanDispatch()
  let loaderApiVersion = detectLoaderApiVersion(ctx.vk)
  let availableExts = queryInstanceExtensionNames(ctx.vk)
  let availableLayers = queryInstanceLayerNames(ctx.vk)

  var enabledExtNames: seq[string] = @[]
  var enabledLayers: seq[cstring]
  when UseVulkanValidation:
    if "VK_LAYER_KHRONOS_validation" notin availableLayers or
        VkExtDebugUtilsExtensionName notin availableExts:
      raise newException(
        ValueError,
        "Vulkan validation requested but the layer/debug-utils extension is unavailable",
      )
    enabledLayers.add("VK_LAYER_KHRONOS_validation")
    enabledExtNames.add(VkExtDebugUtilsExtensionName)
  let surfaceTargetKind =
    if ctx.presentTargetKind != presentTargetNone:
      ctx.presentTargetKind
    else:
      ctx.instanceSurfaceHint
  if surfaceTargetKind != presentTargetNone:
    enabledExtNames.add(VkKhrSurfaceExtensionName)
    case surfaceTargetKind
    of presentTargetXlib:
      when defined(linux) or defined(bsd):
        let hasXlib = VkKhrXlibSurfaceExtensionName in availableExts
        let hasXcb = VkKhrXcbSurfaceExtensionName in availableExts
        if hasXlib:
          ctx.linuxSurfaceKind = linuxSurfaceXlib
          enabledExtNames.add(VkKhrXlibSurfaceExtensionName)
        elif hasXcb:
          ctx.linuxSurfaceKind = linuxSurfaceXcb
          enabledExtNames.add(VkKhrXcbSurfaceExtensionName)
          warn "Vulkan XLIB surface extension unavailable; using XCB surface extension",
            selectedExtension = VkKhrXcbSurfaceExtensionName
        else:
          # Keep legacy default behavior for clearer downstream errors.
          ctx.linuxSurfaceKind = linuxSurfaceXlib
          enabledExtNames.add(VkKhrXlibSurfaceExtensionName)
          warn "Neither VK_KHR_xlib_surface nor VK_KHR_xcb_surface reported as available"
      else:
        enabledExtNames.add(VkKhrXlibSurfaceExtensionName)
    of presentTargetWayland:
      when defined(linux) or defined(bsd):
        if VkKhrWaylandSurfaceExtensionName in availableExts:
          enabledExtNames.add(VkKhrWaylandSurfaceExtensionName)
        else:
          raise newException(
            ValueError, "VK_KHR_wayland_surface extension is required but unavailable"
          )
      else:
        raise newException(ValueError, "Wayland Vulkan surface unsupported on this OS")
    of presentTargetWin32:
      enabledExtNames.add(VkKhrWin32SurfaceExtensionName)
    of presentTargetMetal:
      enabledExtNames.add(VkExtMetalSurfaceExtensionName)
    of presentTargetNone:
      discard

  var enabledExts: seq[cstring] = @[]
  for name in enabledExtNames:
    enabledExts.add(name.cstring)

  debug "Vulkan instance setup",
    loaderApiVersion = vulkanApiVersion(loaderApiVersion),
    requestedExtensions = enabledExtNames,
    availableExtensions = availableExts,
    availableExtensionsCount = availableExts.len,
    availableLayers = availableLayers,
    presentTarget = $surfaceTargetKind
  when defined(linux) or defined(bsd):
    debug "Selected Linux Vulkan surface extension mode",
      linuxSurfaceKind = $ctx.linuxSurfaceKind

  var attempts: seq[uint32] = @[]
  if loaderApiVersion >= vkApiVersion1_1:
    attempts.add(vkApiVersion1_1)
  attempts.add(vkApiVersion1_0)

  for apiVersion in attempts:
    let appInfo = newVkApplicationInfo(
      pApplicationName = "figdraw-vulkan",
      applicationVersion = vkMakeVersion(0, 0, 1, 0),
      pEngineName = "figdraw",
      engineVersion = vkMakeVersion(0, 0, 1, 0),
      apiVersion = apiVersion,
    )
    var instanceInfo = newVkInstanceCreateInfo(
      pApplicationInfo = appInfo.addr,
      pEnabledLayerNames = enabledLayers,
      pEnabledExtensionNames = enabledExts,
    )
    when UseVulkanValidation:
      let validationFeatures = newVkValidationFeaturesEXT(
        enabledValidationFeatures =
          [VkValidationFeatureEnableEXT.SynchronizationValidation],
        disabledValidationFeatures = [],
      )
      instanceInfo.pNext = validationFeatures.unsafeAddr
    try:
      debug "Creating Vulkan instance",
        requestedApiVersion = vulkanApiVersion(apiVersion),
        requestedExtensions = enabledExtNames
      return ctx.vk.createInstance(instanceInfo)
    except VulkanError as exc:
      if exc.res == VkErrorIncompatibleDriver and apiVersion != vkApiVersion1_0:
        warn "Vulkan instance creation failed; retrying with older API version",
          attemptedApiVersion = vulkanApiVersion(apiVersion), reason = exc.msg
        continue
      raise

  raise newException(
    ValueError, "Failed to create Vulkan instance (no compatible Vulkan API version)"
  )

proc applyClipScissor(ctx: VulkanContext) =
  if not ctx.commandRecording or ctx.swapchain == vkNullSwapchain or
      not ctx.renderPassBegun:
    return

  let clipRect =
    if ctx.clipRects.len > 0:
      ctx.clipRects[^1]
    else:
      ctx.fullFrameRect()

  let maxW = max(0'i32, ctx.swapchainExtent.width.int32)
  let maxH = max(0'i32, ctx.swapchainExtent.height.int32)

  var x0 = clamp(floor(clipRect.x).int32, 0'i32, maxW)
  var y0 = clamp(floor(clipRect.y).int32, 0'i32, maxH)
  var x1 = clamp(ceil(clipRect.x + clipRect.w).int32, 0'i32, maxW)
  var y1 = clamp(ceil(clipRect.y + clipRect.h).int32, 0'i32, maxH)
  if x1 < x0:
    x1 = x0
  if y1 < y0:
    y1 = y0

  var scissor = newVkRect2D(
    offset = newVkOffset2D(x = x0, y = y0),
    extent = newVkExtent2D(width = uint32(x1 - x0), height = uint32(y1 - y0)),
  )
  ctx.vk.vkCmdSetScissor(ctx.commandBuffer, 0, 1, scissor.addr)

proc transitionSwapchain(
    ctx: VulkanContext,
    oldLayout, newLayout: VkImageLayout,
    srcStage, dstStage: VkPipelineStageFlags,
    srcAccess, dstAccess: VkAccessFlags,
) =
  var barrier = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    srcAccessMask: srcAccess,
    dstAccessMask: dstAccess,
    oldLayout: oldLayout,
    newLayout: newLayout,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.swapchainImages[ctx.acquiredImageIndex.int],
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer, srcStage, dstStage, 0.VkDependencyFlags, 0, nil, 0, nil, 1,
    barrier.addr,
  )

proc beginRenderPassIfNeeded(ctx: VulkanContext) =
  if not ctx.commandRecording or ctx.swapchain == vkNullSwapchain or ctx.renderPassBegun:
    return

  let renderPassInfo = VkRenderPassBeginInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: nil,
    renderPass: ctx.renderPass,
    framebuffer: ctx.swapchainFramebuffers[ctx.acquiredImageIndex.int],
    renderArea:
      newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = ctx.swapchainExtent),
    clearValueCount: 0,
    pClearValues: nil,
  )
  ctx.vk.vkCmdBeginRenderPass(
    ctx.commandBuffer, renderPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE
  )
  ctx.renderPassBegun = true

  let viewport = newVkViewport(
    x = 0,
    y = 0,
    width = ctx.swapchainExtent.width.float32,
    height = ctx.swapchainExtent.height.float32,
    minDepth = 0,
    maxDepth = 1,
  )
  ctx.vk.vkCmdSetViewport(ctx.commandBuffer, 0, 1, viewport.addr)

  var fullScissor =
    newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = ctx.swapchainExtent)
  ctx.vk.vkCmdSetScissor(ctx.commandBuffer, 0, 1, fullScissor.addr)

  if ctx.frameNeedsClear:
    let clearValue = VkClearValue(
      color: VkClearColorValue(
        float32: [
          ctx.frameClearColor.r.float32, ctx.frameClearColor.g.float32,
          ctx.frameClearColor.b.float32, ctx.frameClearColor.a.float32,
        ]
      )
    )
    var clearAttachment = VkClearAttachment(
      aspectMask: VkImageAspectFlags{ColorBit},
      colorAttachment: 0,
      clearValue: clearValue,
    )
    var clearRect = VkClearRect(
      rect:
        newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = ctx.swapchainExtent),
      baseArrayLayer: 0,
      layerCount: 1,
    )
    ctx.vk.vkCmdClearAttachments(
      ctx.commandBuffer, 1, clearAttachment.addr, 1, clearRect.addr
    )
    ctx.frameNeedsClear = false

  if ctx.clipRects.len > 0:
    ctx.applyClipScissor()

proc ensureGpuRuntime(ctx: VulkanContext) =
  if ctx.gpuReady:
    return

  debug "Starting Vulkan runtime initialization",
    hasPresentTarget = ctx.hasPresentTarget(),
    presentTarget = $ctx.presentTargetKind,
    xlibDisplay = cast[uint64](ctx.presentXlibDisplay),
    xlibWindow = ctx.presentXlibWindow,
    win32Hinstance = cast[uint64](ctx.presentWin32Hinstance),
    win32Hwnd = cast[uint64](ctx.presentWin32Hwnd)

  ctx.ensureInstance()

  if ctx.hasPresentTarget():
    ctx.createPresentSurface()

  let devices = ctx.vk.enumeratePhysicalDevices(ctx.instance)
  debug "Enumerated Vulkan physical devices", deviceCount = devices.len
  if devices.len == 0:
    raise newException(ValueError, "No Vulkan physical devices found")

  var wantPresent = ctx.hasPresentTarget()
  var selectedQueues: QueueFamilyIndices
  for device in devices:
    let devName = physicalDeviceName(ctx.vk, device)
    let queues =
      findQueueFamilies(ctx.vk, device, ctx.surface, requirePresent = wantPresent)
    if not queues.graphicsFound or not queues.presentFound:
      debug "Skipping Vulkan physical device (queue requirements)",
        device = devName,
        graphicsFound = queues.graphicsFound,
        presentFound = queues.presentFound,
        requirePresent = wantPresent
      continue

    if wantPresent:
      let hasSwapchain =
        checkDeviceExtensionSupport(ctx.vk, device, @[VkKhrSwapchainExtensionName])
      debug "Vulkan physical device present support",
        device = devName,
        hasSwapchainExt = hasSwapchain,
        graphicsQueue = queues.graphicsFamily,
        presentQueue = queues.presentFamily
      if not hasSwapchain:
        continue
      let support = querySwapChainSupport(ctx.vk, device, ctx.surface)
      debug "Vulkan physical device swapchain support",
        device = devName,
        formatCount = support.formats.len,
        presentModeCount = support.presentModes.len
      if support.formats.len == 0 or support.presentModes.len == 0:
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
    debug "No Vulkan device met present requirements; retrying without present queue"
    wantPresent = false
    for device in devices:
      let queues =
        findQueueFamilies(ctx.vk, device, ctx.surface, requirePresent = false)
      if not queues.graphicsFound:
        debug "Skipping Vulkan physical device (no graphics queue)",
          device = physicalDeviceName(ctx.vk, device)
        continue
      ctx.physicalDevice = device
      selectedQueues = queues
      debug "Selected Vulkan physical device without present requirements",
        device = physicalDeviceName(ctx.vk, device),
        graphicsQueue = queues.graphicsFamily
      break

  if ctx.physicalDevice == vkNullPhysicalDevice:
    raise newException(ValueError, "No suitable Vulkan physical device found")

  ctx.uniformAlignment = max(
    1.VkDeviceSize,
    ctx.vk.getPhysicalDeviceProperties(ctx.physicalDevice).limits.minUniformBufferOffsetAlignment,
  )
  ctx.driverInfo = queryVulkanDriverInfo(ctx.vk, ctx.physicalDevice)
  ctx.activeSwapchainProfile =
    chooseSwapchainProfile(ctx.requestedSwapchainProfile, ctx.driverInfo)
  ctx.queueFamily = selectedQueues.graphicsFamily
  ctx.presentQueueFamily =
    if wantPresent: selectedQueues.presentFamily else: selectedQueues.graphicsFamily
  debug "Using Vulkan queue families",
    graphicsQueue = ctx.queueFamily,
    presentQueue = ctx.presentQueueFamily,
    wantPresent = wantPresent,
    driverVersion = ctx.driverInfo.driverVersion,
    vendorId = ctx.driverInfo.vendorId,
    swapchainProfile = $ctx.activeSwapchainProfile

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
  ctx.device = ctx.vk.createDevice(ctx.physicalDevice, deviceInfo)
  ctx.queue = ctx.vk.getDeviceQueue(ctx.device, ctx.queueFamily, 0)
  ctx.presentQueue =
    if wantPresent:
      ctx.vk.getDeviceQueue(ctx.device, ctx.presentQueueFamily, 0)
    else:
      ctx.queue

  let poolInfo = newVkCommandPoolCreateInfo(
    queueFamilyIndex = ctx.queueFamily,
    flags = VkCommandPoolCreateFlags{ResetCommandBufferBit},
  )
  ctx.commandPool = ctx.vk.createCommandPool(ctx.device, poolInfo)

  let cmdAlloc = newVkCommandBufferAllocateInfo(
    commandPool = ctx.commandPool,
    level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount = 1,
  )
  ctx.commandBuffer = ctx.vk.allocateCommandBuffers(ctx.device, cmdAlloc)

  let semaphoreInfo = newVkSemaphoreCreateInfo()
  checkVkResult ctx.vk.vkCreateSemaphore(
    ctx.device, semaphoreInfo.addr, nil, ctx.imageAvailableSemaphore.addr
  )
  let fenceInfo = newVkFenceCreateInfo(flags = VkFenceCreateFlags{SignaledBit})
  checkVkResult ctx.vk.vkCreateFence(
    ctx.device, fenceInfo.addr, nil, ctx.inFlightFence.addr
  )

  let setBindings = [
    newVkDescriptorSetLayoutBinding(
      binding = 0,
      descriptorType = VkDescriptorType.UniformBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{VertexBit},
      pImmutableSamplers = nil,
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{FragmentBit},
      pImmutableSamplers = nil,
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 2,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{FragmentBit},
      pImmutableSamplers = nil,
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 3,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{FragmentBit},
      pImmutableSamplers = nil,
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 4,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{FragmentBit},
      pImmutableSamplers = nil,
    ),
  ]
  ctx.descriptorSetLayout = ctx.vk.createDescriptorSetLayout(
    ctx.device, newVkDescriptorSetLayoutCreateInfo(bindings = setBindings)
  )

  let blurSetBindings = [
    newVkDescriptorSetLayoutBinding(
      binding = 0,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{FragmentBit},
      pImmutableSamplers = nil,
    ),
    newVkDescriptorSetLayoutBinding(
      binding = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      descriptorCount = 1,
      stageFlags = VkShaderStageFlags{FragmentBit},
      pImmutableSamplers = nil,
    ),
  ]
  ctx.blurDescriptorSetLayout = ctx.vk.createDescriptorSetLayout(
    ctx.device, newVkDescriptorSetLayoutCreateInfo(bindings = blurSetBindings)
  )

  let indexBytes = VkDeviceSize(sizeof(uint16) * ctx.indices.len)
  let indexAlloc = ctx.createBuffer(
    size = indexBytes,
    usage = VkBufferUsageFlags{IndexBufferBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.indexBuffer = indexAlloc
  ctx.indexBufferBytes = indexBytes

  let mappedIdx = cast[ptr uint8](ctx.vk.mapMemory(
    ctx.device, ctx.indexBuffer.allocation, 0.VkDeviceSize, indexBytes,
    0.VkMemoryMapFlags,
  ))
  copyMem(mappedIdx, ctx.indices[0].addr, int(indexBytes))
  ctx.vk.unmapMemory(ctx.device, ctx.indexBuffer.allocation)

  let samplerInfo = newVkSamplerCreateInfo(
    magFilter = (if ctx.pixelate: VK_FILTER_NEAREST else: VK_FILTER_LINEAR),
    minFilter = (if ctx.pixelate: VK_FILTER_NEAREST else: VK_FILTER_LINEAR),
    mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR,
    addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    mipLodBias = 0,
    anisotropyEnable = VkBool32(VkFalse),
    maxAnisotropy = 1,
    compareEnable = VkBool32(VkFalse),
    compareOp = VK_COMPARE_OP_ALWAYS,
    minLod = 0,
    maxLod = 0,
    borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK,
    unnormalizedCoordinates = VkBool32(VkFalse),
  )
  checkVkResult ctx.vk.vkCreateSampler(
    ctx.device, samplerInfo.addr, nil, ctx.atlasSampler.addr
  )

  ctx.recreateAtlasGpu()

  let initialW = max(1, ctx.frameSize.x.int32)
  let initialH = max(1, ctx.frameSize.y.int32)
  if wantPresent:
    ctx.createSwapchain(initialW, initialH)
    ctx.presentReady = true

  ctx.gpuReady = true

proc flush(ctx: VulkanContext) =
  if ctx.quadCount == 0:
    return
  if not ctx.commandRecording:
    # No active command buffer (e.g. no present-capable swapchain this frame):
    # drop queued quads so they don't accumulate into overflow asserts.
    ctx.quadCount = 0
    ctx.batchHasRectMask = false
    return
  if ctx.atlasDirty:
    if ctx.renderPassBegun:
      ctx.vk.vkCmdEndRenderPass(ctx.commandBuffer)
      ctx.renderPassBegun = false
    ctx.recordAtlasUpload(ctx.commandBuffer)
  ctx.beginRenderPassIfNeeded()

  let vertexCount = ctx.quadCount * 4
  for i in 0 ..< vertexCount:
    let v = addr ctx.vertexScratch[i]
    v.pos[0] = ctx.positions[i * 2 + 0]
    v.pos[1] = ctx.positions[i * 2 + 1]
    v.uv[0] = ctx.uvs[i * 2 + 0]
    v.uv[1] = ctx.uvs[i * 2 + 1]
    v.color[0] = ctx.colors[i * 4 + 0]
    v.color[1] = ctx.colors[i * 4 + 1]
    v.color[2] = ctx.colors[i * 4 + 2]
    v.color[3] = ctx.colors[i * 4 + 3]
    v.fillMidColor[0] = ctx.fillMidColors[i * 4 + 0]
    v.fillMidColor[1] = ctx.fillMidColors[i * 4 + 1]
    v.fillMidColor[2] = ctx.fillMidColors[i * 4 + 2]
    v.fillMidColor[3] = ctx.fillMidColors[i * 4 + 3]
    v.fillStopColor[0] = ctx.fillStopColors[i * 4 + 0]
    v.fillStopColor[1] = ctx.fillStopColors[i * 4 + 1]
    v.fillStopColor[2] = ctx.fillStopColors[i * 4 + 2]
    v.fillStopColor[3] = ctx.fillStopColors[i * 4 + 3]
    v.sdfParams[0] = ctx.sdfParams[i * 4 + 0]
    v.sdfParams[1] = ctx.sdfParams[i * 4 + 1]
    v.sdfParams[2] = ctx.sdfParams[i * 4 + 2]
    v.sdfParams[3] = ctx.sdfParams[i * 4 + 3]
    v.sdfRadii[0] = ctx.sdfRadii[i * 4 + 0]
    v.sdfRadii[1] = ctx.sdfRadii[i * 4 + 1]
    v.sdfRadii[2] = ctx.sdfRadii[i * 4 + 2]
    v.sdfRadii[3] = ctx.sdfRadii[i * 4 + 3]
    when defined(emscripten):
      v.sdfMode = uint16(ctx.sdfModeAttr[i])
    else:
      v.sdfMode = ctx.sdfModeAttr[i].uint16
    v.sdfPad = 0'u16
    v.sdfFactors[0] = ctx.sdfFactors[i * 2 + 0]
    v.sdfFactors[1] = ctx.sdfFactors[i * 2 + 1]
    if ctx.batchHasRectMask:
      v.rectMaskParams[0] = ctx.rectMaskParams[i * 4 + 0]
      v.rectMaskParams[1] = ctx.rectMaskParams[i * 4 + 1]
      v.rectMaskParams[2] = ctx.rectMaskParams[i * 4 + 2]
      v.rectMaskParams[3] = ctx.rectMaskParams[i * 4 + 3]
      v.rectMaskRadii[0] = ctx.rectMaskRadii[i * 4 + 0]
      v.rectMaskRadii[1] = ctx.rectMaskRadii[i * 4 + 1]
      v.rectMaskRadii[2] = ctx.rectMaskRadii[i * 4 + 2]
      v.rectMaskRadii[3] = ctx.rectMaskRadii[i * 4 + 3]
      v.rectMaskMatX[0] = ctx.rectMaskMatX[i * 4 + 0]
      v.rectMaskMatX[1] = ctx.rectMaskMatX[i * 4 + 1]
      v.rectMaskMatX[2] = ctx.rectMaskMatX[i * 4 + 2]
      v.rectMaskMatX[3] = ctx.rectMaskMatX[i * 4 + 3]
      v.rectMaskMatY[0] = ctx.rectMaskMatY[i * 4 + 0]
      v.rectMaskMatY[1] = ctx.rectMaskMatY[i * 4 + 1]
      v.rectMaskMatY[2] = ctx.rectMaskMatY[i * 4 + 2]
      v.rectMaskMatY[3] = ctx.rectMaskMatY[i * 4 + 3]
    else:
      v.rectMaskParams[0] = 0.0'f32
      v.rectMaskParams[1] = 0.0'f32
      v.rectMaskParams[2] = -1.0'f32
      v.rectMaskParams[3] = -1.0'f32
      v.rectMaskRadii[0] = 0.0'f32
      v.rectMaskRadii[1] = 0.0'f32
      v.rectMaskRadii[2] = 0.0'f32
      v.rectMaskRadii[3] = 0.0'f32
      v.rectMaskMatX[0] = 0.0'f32
      v.rectMaskMatX[1] = 0.0'f32
      v.rectMaskMatX[2] = 0.0'f32
      v.rectMaskMatX[3] = 0.0'f32
      v.rectMaskMatY[0] = 0.0'f32
      v.rectMaskMatY[1] = 0.0'f32
      v.rectMaskMatY[2] = 0.0'f32
      v.rectMaskMatY[3] = 0.0'f32

  let uploadBytes = VkDeviceSize(vertexCount * sizeof(Vertex))
  let vertexUpload = ctx.allocateFrameUpload(uploadBytes)
  copyMem(vertexUpload.data, ctx.vertexScratch[0].addr, int(uploadBytes))

  var vsu = VSUniforms(proj: ctx.proj)
  var fsu = FSUniforms(
    windowFrame: ctx.frameSize, aaFactor: ctx.aaFactor, maskTexEnabled: 0'u32
  )

  let vsUpload =
    ctx.allocateFrameUpload(sizeof(VSUniforms).VkDeviceSize, ctx.uniformAlignment)
  let fsUpload =
    ctx.allocateFrameUpload(sizeof(FSUniforms).VkDeviceSize, ctx.uniformAlignment)
  copyMem(vsUpload.data, vsu.addr, sizeof(vsu))
  copyMem(fsUpload.data, fsu.addr, sizeof(fsu))
  ctx.descriptorSet = ctx.allocateFrameDescriptorSet(ctx.descriptorSetLayout)
  ctx.updateDescriptorSet(vsUpload, fsUpload)

  ctx.vk.vkCmdBindPipeline(
    ctx.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipeline
  )

  let vbs = [vertexUpload.buffer.handle]
  let offs = [vertexUpload.offset]
  ctx.vk.vkCmdBindVertexBuffers(
    ctx.commandBuffer, 0, 1, vbs[0].unsafeAddr, offs[0].unsafeAddr
  )
  ctx.vk.vkCmdBindIndexBuffer(
    ctx.commandBuffer, ctx.indexBuffer.handle, 0.VkDeviceSize, VK_INDEX_TYPE_UINT16
  )
  ctx.vk.vkCmdBindDescriptorSets(
    ctx.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipelineLayout, 0, 1,
    ctx.descriptorSet.addr, 0, nil,
  )

  let indexCount = uint32(ctx.quadCount * 6)
  ctx.vk.vkCmdDrawIndexed(ctx.commandBuffer, indexCount, 1, 0, 0, 0)
  ctx.quadCount = 0
  ctx.batchHasRectMask = false

proc checkBatch(ctx: VulkanContext) =
  if not ctx.commandRecording:
    # Keep CPU-side batch empty when Vulkan recording is unavailable.
    ctx.quadCount = 0
    ctx.batchHasRectMask = false
    return
  if ctx.quadCount >= ctx.maxQuads:
    ctx.flush()

proc setVert2(buf: var seq[float32], i: int, v: Vec2) =
  buf[i * 2 + 0] = v.x
  buf[i * 2 + 1] = v.y

proc setVert4(buf: var seq[float32], i: int, v: Vec4) =
  buf[i * 4 + 0] = v.x
  buf[i * 4 + 1] = v.y
  buf[i * 4 + 2] = v.z
  buf[i * 4 + 3] = v.w

proc setVertColor(buf: var seq[uint8], i: int, color: ColorRGBA) =
  buf[i * 4 + 0] = color.r
  buf[i * 4 + 1] = color.g
  buf[i * 4 + 2] = color.b
  buf[i * 4 + 3] = color.a

proc setFillExtraColors(
    ctx: VulkanContext, offset: int, midColor, stopColor: ColorRGBA
) =
  ctx.fillMidColors.setVertColor(offset + 0, midColor)
  ctx.fillMidColors.setVertColor(offset + 1, midColor)
  ctx.fillMidColors.setVertColor(offset + 2, midColor)
  ctx.fillMidColors.setVertColor(offset + 3, midColor)
  ctx.fillStopColors.setVertColor(offset + 0, stopColor)
  ctx.fillStopColors.setVertColor(offset + 1, stopColor)
  ctx.fillStopColors.setVertColor(offset + 2, stopColor)
  ctx.fillStopColors.setVertColor(offset + 3, stopColor)

func roundedRadiiVec(radii: array[DirectionCorners, float32], halfExtents: Vec2): Vec4 =
  let maxRadius = min(halfExtents.x, halfExtents.y)
  let radiiClamped = [
    dcTopLeft: (
      if radii[dcTopLeft] <= 0.0'f32: 0.0'f32
      else: max(1.0'f32, min(radii[dcTopLeft], maxRadius)).round()
    ),
    dcTopRight: (
      if radii[dcTopRight] <= 0.0'f32: 0.0'f32
      else: max(1.0'f32, min(radii[dcTopRight], maxRadius)).round()
    ),
    dcBottomLeft: (
      if radii[dcBottomLeft] <= 0.0'f32: 0.0'f32
      else: max(1.0'f32, min(radii[dcBottomLeft], maxRadius)).round()
    ),
    dcBottomRight: (
      if radii[dcBottomRight] <= 0.0'f32: 0.0'f32
      else: max(1.0'f32, min(radii[dcBottomRight], maxRadius)).round()
    ),
  ]
  vec4(
    radiiClamped[dcTopRight],
    radiiClamped[dcBottomRight],
    radiiClamped[dcTopLeft],
    radiiClamped[dcBottomLeft],
  )

const
  SdfEllipseFlag = 128
  SdfRadiusQuantization = 4095.0'f32
  SdfRadiusQuantizationBase = 4096.0'f32
  SdfFillSolidOrVertex = 0
  SdfFillLinear3X = 1
  SdfFillLinear3Y = 2
  SdfFillLinear3DiagTLBR = 3
  SdfFillLinear3DiagBLTR = 4
  SdfFillModeShift = 256

func roundedRadius(radius, maximum: float32): float32 =
  if radius <= 0.0'f32:
    0.0'f32
  else:
    max(1.0'f32, min(radius, maximum)).round()

func packEllipticalRadius(rx, ry: float32, halfExtents: Vec2): float32 =
  let
    qx = round(
      clamp(rx / max(halfExtents.x, 0.000001'f32), 0.0'f32, 1.0'f32) *
        SdfRadiusQuantization
    )
    qy = round(
      clamp(ry / max(halfExtents.y, 0.000001'f32), 0.0'f32, 1.0'f32) *
        SdfRadiusQuantization
    )
  qx + qy * SdfRadiusQuantizationBase

func packCircularRadius(radius: float32): float32 =
  ## Negative values preserve a circular corner inside an otherwise elliptical
  ## primitive without consuming another vertex attribute.
  -(radius + 1.0'f32)

func roundedRadiiVec(
    radii: CornerRadii2D[float32], halfExtents: Vec2
): tuple[radii: Vec4, elliptical: bool] =
  var allCircular = true
  for corner in DirectionCorners:
    if radii.x[corner] != radii.y[corner]:
      allCircular = false

  if allCircular:
    return (roundedRadiiVec(radii.x, halfExtents), false)

  let radiiX = [
    dcTopLeft: roundedRadius(radii.x[dcTopLeft], halfExtents.x),
    dcTopRight: roundedRadius(radii.x[dcTopRight], halfExtents.x),
    dcBottomLeft: roundedRadius(radii.x[dcBottomLeft], halfExtents.x),
    dcBottomRight: roundedRadius(radii.x[dcBottomRight], halfExtents.x),
  ]
  let radiiY = [
    dcTopLeft: roundedRadius(radii.y[dcTopLeft], halfExtents.y),
    dcTopRight: roundedRadius(radii.y[dcTopRight], halfExtents.y),
    dcBottomLeft: roundedRadius(radii.y[dcBottomLeft], halfExtents.y),
    dcBottomRight: roundedRadius(radii.y[dcBottomRight], halfExtents.y),
  ]
  let circleMaxRadius = min(halfExtents.x, halfExtents.y)
  func encodeCorner(corner: DirectionCorners): float32 =
    let
      sameInputAxes = radii.x[corner] == radii.y[corner]
      circleRadius = roundedRadius(radii.x[corner], circleMaxRadius)
    if sameInputAxes:
      return packCircularRadius(circleRadius)
    if radiiX[corner] == radiiY[corner]:
      return packCircularRadius(radiiX[corner])
    packEllipticalRadius(radiiX[corner], radiiY[corner], halfExtents)
  (
    vec4(
      encodeCorner(dcTopRight),
      encodeCorner(dcBottomRight),
      encodeCorner(dcTopLeft),
      encodeCorner(dcBottomLeft),
    ),
    true,
  )

func linear3FillMode(axis: FillGradientAxis): int =
  case axis
  of fgaX: SdfFillLinear3X
  of fgaY: SdfFillLinear3Y
  of fgaDiagTLBR: SdfFillLinear3DiagTLBR
  of fgaDiagBLTR: SdfFillLinear3DiagBLTR

func encodeSdfMode(
    mode: SdfMode, fillMode: int, elliptical: bool = false
): SdfModeData =
  let packed =
    mode.int + (if elliptical: SdfEllipseFlag else: 0) + fillMode * SdfFillModeShift
  when SdfModeData is float32: packed.float32 else: packed.uint16

proc activeTextSubpixelShift(ctx: VulkanContext): float32 =
  if not ctx.textSubpixelPositioningEnabled:
    return 0.0'f32
  max(0.0'f32, min(ctx.textSubpixelShift, 0.999'f32))

func `*`*(m: Mat4, v: Vec2): Vec2 =
  (m * vec3(v.x, v.y, 0.0)).xy

proc makeRectMask(
    ctx: VulkanContext, maskRect: Rect, radii: CornerRadii2D[float32]
): RectMask =
  let
    halfExtents = maskRect.wh * 0.5'f32
    center = maskRect.xy + halfExtents
    invMat = ctx.mat.inverse()
    encodedRadii = roundedRadiiVec(radii, halfExtents)
  RectMask(
    kind: rmkFast,
    params: vec4(center.x, center.y, halfExtents.x, halfExtents.y),
    radii: encodedRadii.radii,
    matX: vec4(invMat[0, 0], invMat[1, 0], invMat[3, 0], 1.0'f32),
    matY: vec4(
      invMat[0, 1],
      invMat[1, 1],
      invMat[3, 1],
      if encodedRadii.elliptical: 1.0'f32 else: 0.0'f32,
    ),
  )

proc setRectMaskVert4(
    ctx: VulkanContext, offset: int, params, radii, matX, matY: Vec4
) =
  for i in 0 ..< 4:
    ctx.rectMaskParams.setVert4(offset + i, params)
    ctx.rectMaskRadii.setVert4(offset + i, radii)
    ctx.rectMaskMatX.setVert4(offset + i, matX)
    ctx.rectMaskMatY.setVert4(offset + i, matY)

proc setDisabledRectMaskVerts(ctx: VulkanContext, firstVertex, vertexCount: int) =
  let
    params = vec4(0.0'f32, 0.0'f32, -1.0'f32, -1.0'f32)
    zero4 = vec4(0.0'f32)
  for i in firstVertex ..< firstVertex + vertexCount:
    ctx.rectMaskParams.setVert4(i, params)
    ctx.rectMaskRadii.setVert4(i, zero4)
    ctx.rectMaskMatX.setVert4(i, zero4)
    ctx.rectMaskMatY.setVert4(i, zero4)

proc setRectMaskVert4(ctx: VulkanContext, offset: int) =
  if ctx.maskBegun:
    return

  var
    hasRectMask = false
    params = vec4(0.0'f32)
    radii = vec4(0.0'f32)
    matX = vec4(0.0'f32)
    matY = vec4(0.0'f32)

  if ctx.rectMaskStack.len > 0:
    for i in countdown(ctx.rectMaskStack.len - 1, 0):
      let rectMask = ctx.rectMaskStack[i]
      if rectMask.kind == rmkFast:
        hasRectMask = true
        params = rectMask.params
        radii = rectMask.radii
        matX = rectMask.matX
        matY = rectMask.matY
        break

  if hasRectMask:
    if not ctx.batchHasRectMask:
      ctx.setDisabledRectMaskVerts(0, offset)
      ctx.batchHasRectMask = true
    ctx.setRectMaskVert4(offset, params, radii, matX, matY)
  elif ctx.batchHasRectMask:
    ctx.setDisabledRectMaskVerts(offset, 4)

template setRectMaskVert4IfNeeded(ctx: VulkanContext, offset: int) =
  if not ctx.maskBegun and (ctx.batchHasRectMask or ctx.rectMaskStack.len > 0):
    ctx.setRectMaskVert4(offset)

proc copyIntoAtlas(atlas: Image, atX, atY: int, image: Image) =
  for y in 0 ..< image.height:
    let dstRow = (atY + y) * atlas.width + atX
    let srcRow = y * image.width
    copyMem(
      atlas.data[dstRow].addr,
      image.data[srcRow].unsafeAddr,
      image.width * sizeof(ColorRGBA),
    )

proc atlasSizeLimit(ctx: VulkanContext): int =
  # Bound CPU allocation before the device is initialized as well.
  result = 16_384
  if ctx.physicalDevice != vkNullPhysicalDevice:
    result = min(
      result,
      ctx.vk.getPhysicalDeviceProperties(ctx.physicalDevice).limits.maxImageDimension2D.int,
    )

proc checkedAtlasSize(ctx: VulkanContext, minimumSize: int): int =
  let limit = ctx.atlasSizeLimit()
  if minimumSize > limit:
    raise newException(ValueError, "Vulkan atlas exceeds maximum dimension " & $limit)
  result = ctx.initialAtlasSize
  while result < minimumSize:
    if result > limit div 2:
      raise newException(ValueError, "Vulkan atlas cannot grow beyond " & $limit)
    result *= 2

proc grow(ctx: VulkanContext) =
  let nextSize = ctx.checkedAtlasSize(ctx.atlasSize + 1)
  ctx.flush()
  let previousSize = ctx.atlasSize
  let pixels = newImage(nextSize, nextSize)
  copyIntoAtlas(pixels, 0, 0, ctx.atlasPixels)
  ctx.atlasPixels = pixels
  ctx.atlasSize = nextSize
  ctx.heights.setLen(nextSize)
  for bounds in ctx.entries.mvalues:
    bounds = bounds * (previousSize.float32 / nextSize.float32)
  ctx.atlasDirty = true
  ctx.atlasLayoutReady = false
  if ctx.gpuReady:
    ctx.recreateAtlasGpu()
  ctx.noteAtlasRebuilt()
  info "grow atlasSize", atlasSize = ctx.atlasSize

proc findEmptyRect(ctx: VulkanContext, width, height: int): Rect =
  if width <= 0 or height <= 0 or width > ctx.atlasSizeLimit() - ctx.atlasMargin * 2 or
      height > ctx.atlasSizeLimit() - ctx.atlasMargin * 2:
    raise newException(ValueError, "Image does not fit within the Vulkan atlas limit")
  let imgWidth = width + ctx.atlasMargin * 2
  let imgHeight = height + ctx.atlasMargin * 2

  var lowest = ctx.atlasSize
  var at = 0
  for i in 0 .. ctx.atlasSize - 1:
    let v = int(ctx.heights[i])
    if v < lowest:
      var fit = true
      for j in 0 ..< imgWidth:
        if i + j >= ctx.atlasSize:
          fit = false
          break
        if int(ctx.heights[i + j]) > v:
          fit = false
          break
      if fit:
        lowest = v
        at = i

  if lowest + imgHeight > ctx.atlasSize:
    ctx.grow()
    return ctx.findEmptyRect(width, height)

  for j in at .. at + imgWidth - 1:
    ctx.heights[j] = uint16(lowest + imgHeight)

  rect(
    float32(at + ctx.atlasMargin),
    float32(lowest + ctx.atlasMargin),
    float32(width),
    float32(height),
  )

method putImage*(ctx: VulkanContext, path: Hash, image: Image)

method addImage*(ctx: VulkanContext, key: Hash, image: Image) =
  ctx.putImage(key, image)

method putImage*(ctx: VulkanContext, path: Hash, image: Image) =
  let rect = ctx.findEmptyRect(image.width, image.height)
  ctx.entries[path] = rect / float(ctx.atlasSize)
  ctx.markGeneratedEntry(path)
  copyIntoAtlas(ctx.atlasPixels, int(rect.x), int(rect.y), image)
  ctx.atlasDirty = true

method updateImage*(ctx: VulkanContext, path: Hash, image: Image) =
  ctx.flush()
  let rect = ctx.entries[path]
  assert rect.w == image.width.float / float(ctx.atlasSize)
  assert rect.h == image.height.float / float(ctx.atlasSize)
  copyIntoAtlas(
    ctx.atlasPixels,
    int(rect.x * ctx.atlasSize.float),
    int(rect.y * ctx.atlasSize.float),
    image,
  )
  ctx.atlasDirty = true

proc putFlippy*(ctx: VulkanContext, path: Hash, flippy: Flippy) =
  if flippy.mipmaps.len == 0:
    return
  ctx.putImage(path, flippy.mipmaps[0])

method putImage*(ctx: VulkanContext, imgObj: ImgObj) =
  case imgObj.kind
  of FlippyImg:
    ctx.putFlippy(imgObj.id.Hash, imgObj.flippy)
  of PixieImg:
    ctx.putImage(imgObj.id.Hash, imgObj.pimg)
  ctx.markImageEntry(imgObj.id)

method clearImageAtlas*(ctx: VulkanContext) =
  ctx.resetImageAtlas(ctx.initialAtlasSize)

method resetImageAtlas*(ctx: VulkanContext, minimumSize: int) =
  let nextSize = ctx.checkedAtlasSize(max(ctx.initialAtlasSize, minimumSize))
  ctx.flush()
  ctx.atlasSize = nextSize
  ctx.entries.clear()
  ctx.atlasEntryMeta.clear()
  ctx.heights = newSeq[uint16](ctx.atlasSize)
  ctx.atlasPixels = newImage(ctx.atlasSize, ctx.atlasSize)
  ctx.atlasPixels.fill(rgba(0, 0, 0, 0))
  ctx.atlasDirty = true
  ctx.atlasLayoutReady = false
  if ctx.gpuReady:
    ctx.recreateAtlasGpu()
  ctx.noteAtlasRebuilt()

proc drawQuad*(
    ctx: VulkanContext,
    verts: array[4, Vec2],
    uvs: array[4, Vec2],
    colors: array[4, ColorRGBA],
) =
  ctx.checkBatch()
  assert ctx.quadCount < ctx.maxQuads

  let zero4 = vec4(0.0'f32)
  let offset = ctx.quadCount * 4
  ctx.positions.setVert2(offset + 0, verts[0])
  ctx.positions.setVert2(offset + 1, verts[1])
  ctx.positions.setVert2(offset + 2, verts[2])
  ctx.positions.setVert2(offset + 3, verts[3])

  ctx.uvs.setVert2(offset + 0, uvs[0])
  ctx.uvs.setVert2(offset + 1, uvs[1])
  ctx.uvs.setVert2(offset + 2, uvs[2])
  ctx.uvs.setVert2(offset + 3, uvs[3])

  ctx.colors.setVertColor(offset + 0, colors[0])
  ctx.colors.setVertColor(offset + 1, colors[1])
  ctx.colors.setVertColor(offset + 2, colors[2])
  ctx.colors.setVertColor(offset + 3, colors[3])
  ctx.setFillExtraColors(offset, rgba(0, 0, 0, 0), rgba(0, 0, 0, 0))

  ctx.sdfParams.setVert4(offset + 0, zero4)
  ctx.sdfParams.setVert4(offset + 1, zero4)
  ctx.sdfParams.setVert4(offset + 2, zero4)
  ctx.sdfParams.setVert4(offset + 3, zero4)

  ctx.sdfRadii.setVert4(offset + 0, zero4)
  ctx.sdfRadii.setVert4(offset + 1, zero4)
  ctx.sdfRadii.setVert4(offset + 2, zero4)
  ctx.sdfRadii.setVert4(offset + 3, zero4)

  let defaultFactors = vec2(0.0'f32, 0.0'f32)
  ctx.sdfFactors.setVert2(offset + 0, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 1, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 2, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 3, defaultFactors)

  when defined(emscripten):
    let modeVal = 0.0'f32
  else:
    let modeVal = 0'u16
  ctx.sdfModeAttr[offset + 0] = modeVal
  ctx.sdfModeAttr[offset + 1] = modeVal
  ctx.sdfModeAttr[offset + 2] = modeVal
  ctx.sdfModeAttr[offset + 3] = modeVal

  ctx.setRectMaskVert4IfNeeded(offset)
  inc ctx.quadCount

method drawFilledQuad*(
    ctx: VulkanContext, verts: array[4, Vec2], colors: array[4, ColorRGBA]
) =
  const imgKey = hash("rect")
  if imgKey notin ctx.entries:
    var image = newImage(4, 4)
    image.fill(rgba(255, 255, 255, 255))
    ctx.putImage(imgKey, image)

  let
    uv = ctx.entries[imgKey].xy + ctx.entries[imgKey].wh / 2.0'f32
    uvQuad = [uv, uv, uv, uv]

  let posQuad = [
    ceil(ctx.mat * verts[0]),
    ceil(ctx.mat * verts[1]),
    ceil(ctx.mat * verts[2]),
    ceil(ctx.mat * verts[3]),
  ]
  ctx.drawQuad(posQuad, uvQuad, colors)

proc drawUvRectAtlasSdf(
    ctx: VulkanContext,
    at, to: Vec2,
    uvAt, uvTo: Vec2,
    color: Color,
    mode: SdfMode,
    factors: Vec2,
    params: Vec4 = vec4(0.0'f32),
) =
  ctx.checkBatch()
  assert ctx.quadCount < ctx.maxQuads

  let
    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x, uvTo.y),
      vec2(uvTo.x, uvTo.y),
      vec2(uvTo.x, uvAt.y),
      vec2(uvAt.x, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.setVert2(offset + 0, posQuad[0])
  ctx.positions.setVert2(offset + 1, posQuad[1])
  ctx.positions.setVert2(offset + 2, posQuad[2])
  ctx.positions.setVert2(offset + 3, posQuad[3])

  ctx.uvs.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.setVert2(offset + 3, uvQuad[3])

  let rgba = color.rgba()
  ctx.colors.setVertColor(offset + 0, rgba)
  ctx.colors.setVertColor(offset + 1, rgba)
  ctx.colors.setVertColor(offset + 2, rgba)
  ctx.colors.setVertColor(offset + 3, rgba)
  ctx.setFillExtraColors(offset, rgba(0, 0, 0, 0), rgba(0, 0, 0, 0))
  ctx.setFillExtraColors(offset, rgba(0, 0, 0, 0), rgba(0, 0, 0, 0))

  ctx.sdfParams.setVert4(offset + 0, params)
  ctx.sdfParams.setVert4(offset + 1, params)
  ctx.sdfParams.setVert4(offset + 2, params)
  ctx.sdfParams.setVert4(offset + 3, params)

  let zero4 = vec4(0.0'f32)
  ctx.sdfRadii.setVert4(offset + 0, zero4)
  ctx.sdfRadii.setVert4(offset + 1, zero4)
  ctx.sdfRadii.setVert4(offset + 2, zero4)
  ctx.sdfRadii.setVert4(offset + 3, zero4)

  ctx.sdfFactors.setVert2(offset + 0, factors)
  ctx.sdfFactors.setVert2(offset + 1, factors)
  ctx.sdfFactors.setVert2(offset + 2, factors)
  ctx.sdfFactors.setVert2(offset + 3, factors)

  when defined(emscripten):
    let modeVal = mode.int.float32
  else:
    let modeVal = mode.int.uint16
  ctx.sdfModeAttr[offset + 0] = modeVal
  ctx.sdfModeAttr[offset + 1] = modeVal
  ctx.sdfModeAttr[offset + 2] = modeVal
  ctx.sdfModeAttr[offset + 3] = modeVal

  ctx.setRectMaskVert4IfNeeded(offset)
  inc ctx.quadCount

proc imageUvBounds(rect: Rect, flipY: bool): tuple[uvAt: Vec2, uvTo: Vec2]

method drawMsdfImage*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
    flipY: bool = false,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let (uvAt, uvTo) = imageUvBounds(rect, flipY)
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMsdfAnnular else: SdfMode.sdfModeMsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = uvAt,
    uvTo = uvTo,
    color = color,
    mode = modeSel,
    factors = vec2(pxRange, sdThreshold),
    params = params,
  )

method drawMtsdfImage*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
    flipY: bool = false,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let (uvAt, uvTo) = imageUvBounds(rect, flipY)
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMtsdfAnnular else: SdfMode.sdfModeMtsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = uvAt,
    uvTo = uvTo,
    color = color,
    mode = modeSel,
    factors = vec2(pxRange, sdThreshold),
    params = params,
  )

method sdfAaFactor*(ctx: VulkanContext): float32 =
  ctx.aaFactor

method setSdfAaFactor*(ctx: VulkanContext, aaFactor: float32) =
  if ctx.aaFactor == aaFactor:
    return
  ctx.flush()
  ctx.aaFactor = aaFactor

proc setSdfGlobals*(ctx: VulkanContext, aaFactor: float32) =
  ctx.setSdfAaFactor(aaFactor)

proc drawUvRect(ctx: VulkanContext, at, to: Vec2, uvAt, uvTo: Vec2, color: Color) =
  ctx.checkBatch()
  assert ctx.quadCount < ctx.maxQuads

  let uvShift =
    if ctx.atlasSize > 0:
      ctx.activeTextSubpixelShift() / ctx.atlasSize.float32
    else:
      0.0'f32

  let
    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x - uvShift, uvTo.y),
      vec2(uvTo.x - uvShift, uvTo.y),
      vec2(uvTo.x - uvShift, uvAt.y),
      vec2(uvAt.x - uvShift, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.setVert2(offset + 0, posQuad[0])
  ctx.positions.setVert2(offset + 1, posQuad[1])
  ctx.positions.setVert2(offset + 2, posQuad[2])
  ctx.positions.setVert2(offset + 3, posQuad[3])

  ctx.uvs.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.setVert2(offset + 3, uvQuad[3])

  let rgba = color.rgba()
  ctx.colors.setVertColor(offset + 0, rgba)
  ctx.colors.setVertColor(offset + 1, rgba)
  ctx.colors.setVertColor(offset + 2, rgba)
  ctx.colors.setVertColor(offset + 3, rgba)

  let zero4 = vec4(0.0'f32)
  ctx.sdfParams.setVert4(offset + 0, zero4)
  ctx.sdfParams.setVert4(offset + 1, zero4)
  ctx.sdfParams.setVert4(offset + 2, zero4)
  ctx.sdfParams.setVert4(offset + 3, zero4)

  ctx.sdfRadii.setVert4(offset + 0, zero4)
  ctx.sdfRadii.setVert4(offset + 1, zero4)
  ctx.sdfRadii.setVert4(offset + 2, zero4)
  ctx.sdfRadii.setVert4(offset + 3, zero4)

  let defaultFactors = vec2(0.0'f32, 0.0'f32)
  ctx.sdfFactors.setVert2(offset + 0, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 1, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 2, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 3, defaultFactors)

  when defined(emscripten):
    let modeVal = 0.0'f32
  else:
    let modeVal = 0'u16
  ctx.sdfModeAttr[offset + 0] = modeVal
  ctx.sdfModeAttr[offset + 1] = modeVal
  ctx.sdfModeAttr[offset + 2] = modeVal
  ctx.sdfModeAttr[offset + 3] = modeVal

  ctx.setRectMaskVert4IfNeeded(offset)
  inc ctx.quadCount

proc drawUvRect(
    ctx: VulkanContext, at, to: Vec2, uvAt, uvTo: Vec2, colors: array[4, ColorRGBA]
) =
  ctx.checkBatch()
  assert ctx.quadCount < ctx.maxQuads

  let uvShift =
    if ctx.atlasSize > 0:
      ctx.activeTextSubpixelShift() / ctx.atlasSize.float32
    else:
      0.0'f32

  let
    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x - uvShift, uvTo.y),
      vec2(uvTo.x - uvShift, uvTo.y),
      vec2(uvTo.x - uvShift, uvAt.y),
      vec2(uvAt.x - uvShift, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.setVert2(offset + 0, posQuad[0])
  ctx.positions.setVert2(offset + 1, posQuad[1])
  ctx.positions.setVert2(offset + 2, posQuad[2])
  ctx.positions.setVert2(offset + 3, posQuad[3])

  ctx.uvs.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.setVert2(offset + 3, uvQuad[3])

  ctx.colors.setVertColor(offset + 0, colors[0])
  ctx.colors.setVertColor(offset + 1, colors[1])
  ctx.colors.setVertColor(offset + 2, colors[2])
  ctx.colors.setVertColor(offset + 3, colors[3])
  ctx.setFillExtraColors(offset, rgba(0, 0, 0, 0), rgba(0, 0, 0, 0))

  let zero4 = vec4(0.0'f32)
  ctx.sdfParams.setVert4(offset + 0, zero4)
  ctx.sdfParams.setVert4(offset + 1, zero4)
  ctx.sdfParams.setVert4(offset + 2, zero4)
  ctx.sdfParams.setVert4(offset + 3, zero4)

  ctx.sdfRadii.setVert4(offset + 0, zero4)
  ctx.sdfRadii.setVert4(offset + 1, zero4)
  ctx.sdfRadii.setVert4(offset + 2, zero4)
  ctx.sdfRadii.setVert4(offset + 3, zero4)

  let defaultFactors = vec2(0.0'f32, 0.0'f32)
  ctx.sdfFactors.setVert2(offset + 0, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 1, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 2, defaultFactors)
  ctx.sdfFactors.setVert2(offset + 3, defaultFactors)

  when defined(emscripten):
    let modeVal = 0.0'f32
  else:
    let modeVal = 0'u16
  ctx.sdfModeAttr[offset + 0] = modeVal
  ctx.sdfModeAttr[offset + 1] = modeVal
  ctx.sdfModeAttr[offset + 2] = modeVal
  ctx.sdfModeAttr[offset + 3] = modeVal

  ctx.setRectMaskVert4IfNeeded(offset)
  inc ctx.quadCount

proc drawUvRect(ctx: VulkanContext, rect, uvRect: Rect, color: Color) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, color)

proc drawUvRect(ctx: VulkanContext, rect, uvRect: Rect, colors: array[4, ColorRGBA]) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, colors)

proc tryGetImageRect(ctx: VulkanContext, imageId: Hash, rect: var Rect): bool =
  if imageId notin ctx.entries:
    warn "missing image in context", imageId = imageId
    return false
  rect = ctx.entries[imageId]
  true

proc imageUvBounds(rect: Rect, flipY: bool): tuple[uvAt: Vec2, uvTo: Vec2] =
  if flipY:
    return (vec2(rect.x, rect.y + rect.h), vec2(rect.x + rect.w, rect.y))
  (rect.xy, rect.xy + rect.wh)

proc drawImage*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale: float32,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, color)

proc drawImage*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    colors: array[4, ColorRGBA],
    scale: float32,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, colors)

method drawImage*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let drawSize =
    if size.x > 0.0'f32 and size.y > 0.0'f32:
      size
    else:
      rect.wh * ctx.atlasSize.float32
  let (uvAt, uvTo) = imageUvBounds(rect, flipY)
  ctx.drawUvRect(pos, pos + drawSize, uvAt, uvTo, colors)

method drawImageAdj*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let adj = vec2(2 / ctx.atlasSize.float32)
  ctx.drawUvRect(pos, pos + size, rect.xy + adj, rect.xy + rect.wh - adj, color)

proc drawSprite*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos - wh / 2, pos + wh / 2, rect.xy, rect.xy + rect.wh, color)

proc drawSprite*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  ctx.drawUvRect(pos - size / 2, pos + size / 2, rect.xy, rect.xy + rect.wh, color)

method drawRect*(ctx: VulkanContext, rect: Rect, color: Color) =
  const imgKey = hash("rect")
  if imgKey notin ctx.entries:
    var image = newImage(4, 4)
    image.fill(rgba(255, 255, 255, 255))
    ctx.putImage(imgKey, image)

  let uvRect = ctx.entries[imgKey]
  ctx.drawUvRect(
    rect.xy,
    rect.xy + rect.wh,
    uvRect.xy + uvRect.wh / 2,
    uvRect.xy + uvRect.wh / 2,
    color,
  )

method drawRoundedRectSdf*(
    ctx: VulkanContext,
    rect: Rect,
    color: Color,
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  let rgba = color.rgba()
  ctx.drawRoundedRectSdf(
    rect = rect,
    colors = [rgba, rgba, rgba, rgba],
    radii = radii,
    mode = mode,
    factor = factor,
    spread = spread,
    shapeSize = shapeSize,
  )

proc drawRoundedRectSdfVulkan(
    ctx: VulkanContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
    fillMode: int = SdfFillSolidOrVertex,
    fillMidColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillStopColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillMidPos: float32 = 0.5'f32,
) =
  if rect.w <= 0 or rect.h <= 0:
    return

  ctx.checkBatch()

  let
    quadHalfExtents = rect.wh * 0.5'f32
    insetMode = mode == sdfModeInsetShadow
    resolvedShapeSize =
      (if shapeSize.x > 0.0'f32 and shapeSize.y > 0.0'f32: shapeSize else: rect.wh)
    shapeHalfExtents =
      if insetMode:
        quadHalfExtents
      else:
        resolvedShapeSize * 0.5'f32
    params =
      if insetMode:
        # In inset mode, params.zw carry shadow offset (x, y) in screen space.
        vec4(quadHalfExtents.x, quadHalfExtents.y, shapeSize.x, shapeSize.y)
      else:
        vec4(
          quadHalfExtents.x, quadHalfExtents.y, shapeHalfExtents.x, shapeHalfExtents.y
        )
    encodedRadii = roundedRadiiVec(radii, shapeHalfExtents)
    r4 = encodedRadii.radii

  assert ctx.quadCount < ctx.maxQuads

  let
    at = rect.xy
    to = rect.xy + rect.wh
    uvAt = vec2(0.0'f32, 0.0'f32)
    uvTo = vec2(1.0'f32, 1.0'f32)

    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x, uvTo.y),
      vec2(uvTo.x, uvTo.y),
      vec2(uvTo.x, uvAt.y),
      vec2(uvAt.x, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.setVert2(offset + 0, posQuad[0])
  ctx.positions.setVert2(offset + 1, posQuad[1])
  ctx.positions.setVert2(offset + 2, posQuad[2])
  ctx.positions.setVert2(offset + 3, posQuad[3])

  ctx.uvs.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.setVert2(offset + 3, uvQuad[3])

  ctx.colors.setVertColor(offset + 0, colors[0])
  ctx.colors.setVertColor(offset + 1, colors[1])
  ctx.colors.setVertColor(offset + 2, colors[2])
  ctx.colors.setVertColor(offset + 3, colors[3])
  ctx.setFillExtraColors(offset, fillMidColor, fillStopColor)

  ctx.sdfParams.setVert4(offset + 0, params)
  ctx.sdfParams.setVert4(offset + 1, params)
  ctx.sdfParams.setVert4(offset + 2, params)
  ctx.sdfParams.setVert4(offset + 3, params)

  ctx.sdfRadii.setVert4(offset + 0, r4)
  ctx.sdfRadii.setVert4(offset + 1, r4)
  ctx.sdfRadii.setVert4(offset + 2, r4)
  ctx.sdfRadii.setVert4(offset + 3, r4)

  let factors =
    if fillMode == SdfFillSolidOrVertex:
      vec2(factor, spread)
    else:
      vec2(factor, clamp(fillMidPos, 0.01'f32, 0.99'f32))
  ctx.sdfFactors.setVert2(offset + 0, factors)
  ctx.sdfFactors.setVert2(offset + 1, factors)
  ctx.sdfFactors.setVert2(offset + 2, factors)
  ctx.sdfFactors.setVert2(offset + 3, factors)

  let modeVal = encodeSdfMode(mode, fillMode, encodedRadii.elliptical)
  ctx.sdfModeAttr[offset + 0] = modeVal
  ctx.sdfModeAttr[offset + 1] = modeVal
  ctx.sdfModeAttr[offset + 2] = modeVal
  ctx.sdfModeAttr[offset + 3] = modeVal

  ctx.setRectMaskVert4IfNeeded(offset)
  inc ctx.quadCount

method drawRoundedRectSdf*(
    ctx: VulkanContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  ctx.drawRoundedRectSdfVulkan(
    rect = rect,
    colors = colors,
    radii = radii,
    mode = mode,
    factor = factor,
    spread = spread,
    shapeSize = shapeSize,
  )

method drawRoundedRectSdf*(
    ctx: VulkanContext,
    rect: Rect,
    fill: figbackend.BackendFill,
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  if fill.kind == figbackend.bfLinear3 and
      mode in {sdfModeClipAA, sdfModeAnnular, sdfModeAnnularAA}:
    ctx.drawRoundedRectSdfVulkan(
      rect = rect,
      colors = [fill.lin3Start, fill.lin3Start, fill.lin3Start, fill.lin3Start],
      radii = radii,
      mode = mode,
      factor = factor,
      spread = spread,
      shapeSize = shapeSize,
      fillMode = linear3FillMode(fill.lin3Axis),
      fillMidColor = fill.lin3Mid,
      fillStopColor = fill.lin3Stop,
      fillMidPos = fill.lin3MidPos,
    )
  else:
    ctx.drawRoundedRectSdfVulkan(
      rect = rect,
      colors = figbackend.gradientColors(fill),
      radii = radii,
      mode = mode,
      factor = factor,
      spread = spread,
      shapeSize = shapeSize,
    )

proc drawQuadraticBezierSdfVulkan(
    ctx: VulkanContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    p0, p1, p2: Vec2,
    strokeWeight: float32,
    cap: StrokeCap,
    fillMode: int = SdfFillSolidOrVertex,
    fillMidColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillStopColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillMidPos: float32 = 0.5'f32,
) =
  if rect.w <= 0.0'f32 or rect.h <= 0.0'f32 or strokeWeight <= 0.0'f32:
    return

  ctx.checkBatch()

  let
    quadHalfExtents = rect.wh * 0.5'f32
    params = vec4(quadHalfExtents.x, quadHalfExtents.y, p0.x, p0.y)
    curve = vec4(p1.x, p1.y, p2.x, p2.y)

  assert ctx.quadCount < ctx.maxQuads

  let
    at = rect.xy
    to = rect.xy + rect.wh
    uvAt = vec2(0.0'f32, 0.0'f32)
    uvTo = vec2(1.0'f32, 1.0'f32)

    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x, uvTo.y),
      vec2(uvTo.x, uvTo.y),
      vec2(uvTo.x, uvAt.y),
      vec2(uvAt.x, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.setVert2(offset + 0, posQuad[0])
  ctx.positions.setVert2(offset + 1, posQuad[1])
  ctx.positions.setVert2(offset + 2, posQuad[2])
  ctx.positions.setVert2(offset + 3, posQuad[3])

  ctx.uvs.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.setVert2(offset + 3, uvQuad[3])

  ctx.colors.setVertColor(offset + 0, colors[0])
  ctx.colors.setVertColor(offset + 1, colors[1])
  ctx.colors.setVertColor(offset + 2, colors[2])
  ctx.colors.setVertColor(offset + 3, colors[3])
  ctx.setFillExtraColors(offset, fillMidColor, fillStopColor)

  ctx.sdfParams.setVert4(offset + 0, params)
  ctx.sdfParams.setVert4(offset + 1, params)
  ctx.sdfParams.setVert4(offset + 2, params)
  ctx.sdfParams.setVert4(offset + 3, params)

  ctx.sdfRadii.setVert4(offset + 0, curve)
  ctx.sdfRadii.setVert4(offset + 1, curve)
  ctx.sdfRadii.setVert4(offset + 2, curve)
  ctx.sdfRadii.setVert4(offset + 3, curve)

  let factors =
    if fillMode == SdfFillSolidOrVertex:
      vec2(strokeWeight, 0.0'f32)
    else:
      vec2(strokeWeight, clamp(fillMidPos, 0.01'f32, 0.99'f32))
  ctx.sdfFactors.setVert2(offset + 0, factors)
  ctx.sdfFactors.setVert2(offset + 1, factors)
  ctx.sdfFactors.setVert2(offset + 2, factors)
  ctx.sdfFactors.setVert2(offset + 3, factors)

  let modeVal = encodeSdfMode(figbackend.bezierStrokeSdfMode(cap), fillMode)
  ctx.sdfModeAttr[offset + 0] = modeVal
  ctx.sdfModeAttr[offset + 1] = modeVal
  ctx.sdfModeAttr[offset + 2] = modeVal
  ctx.sdfModeAttr[offset + 3] = modeVal

  ctx.setRectMaskVert4IfNeeded(offset)
  inc ctx.quadCount

method drawQuadraticBezierSdf*(
    ctx: VulkanContext,
    rect: Rect,
    fill: figbackend.BackendFill,
    p0, p1, p2: Vec2,
    strokeWeight: float32,
    cap: StrokeCap,
) =
  if fill.kind == figbackend.bfLinear3:
    ctx.drawQuadraticBezierSdfVulkan(
      rect = rect,
      colors = [fill.lin3Start, fill.lin3Start, fill.lin3Start, fill.lin3Start],
      p0 = p0,
      p1 = p1,
      p2 = p2,
      strokeWeight = strokeWeight,
      cap = cap,
      fillMode = linear3FillMode(fill.lin3Axis),
      fillMidColor = fill.lin3Mid,
      fillStopColor = fill.lin3Stop,
      fillMidPos = fill.lin3MidPos,
    )
  else:
    ctx.drawQuadraticBezierSdfVulkan(
      rect = rect,
      colors = figbackend.gradientColors(fill),
      p0 = p0,
      p1 = p1,
      p2 = p2,
      strokeWeight = strokeWeight,
      cap = cap,
    )

proc runBackdropSeparableBlur(
    ctx: VulkanContext, blurRadius: float32, blurRect: VkRect2D
) =
  vulkanBlurRunSeparable(ctx, blurRadius, blurRect)

method drawBackdropBlur*(
    ctx: VulkanContext, rect: Rect, radii: CornerRadii2D[float32], blurRadius: float32
) =
  if not ctx.swapchainTransferSrcSupported:
    return
  if blurRadius <= 0.0'f32 or rect.w <= 0.0'f32 or rect.h <= 0.0'f32:
    return
  if not ctx.commandRecording or ctx.swapchain == vkNullSwapchain:
    return
  if ctx.acquiredImageIndex.int >= ctx.swapchainImages.len:
    return

  ctx.flush()
  ctx.beginRenderPassIfNeeded()
  if ctx.renderPassBegun:
    ctx.vk.vkCmdEndRenderPass(ctx.commandBuffer)
    ctx.renderPassBegun = false

  let width = max(1'i32, ctx.swapchainExtent.width.int32)
  let height = max(1'i32, ctx.swapchainExtent.height.int32)
  if width <= 0 or height <= 0:
    return

  let blurKernelReach = max(blurRadius, 8.0'f32)
  let blurPad = max(1'i32, int32(ceil(blurKernelReach + 2.0'f32)))
  let x0 = max(0'i32, int32(floor(rect.x - blurPad.float32)))
  let y0 = max(0'i32, int32(floor(rect.y - blurPad.float32)))
  let x1 = min(width, int32(ceil(rect.x + rect.w + blurPad.float32)))
  let y1 = min(height, int32(ceil(rect.y + rect.h + blurPad.float32)))
  if x1 <= x0 or y1 <= y0:
    return
  let blurRect = newVkRect2D(
    offset = newVkOffset2D(x = x0, y = y0),
    extent = newVkExtent2D(width = (x1 - x0).uint32, height = (y1 - y0).uint32),
  )

  ctx.ensureBackdropImage(width, height)
  if ctx.backdropImage.isNilOrEmpty or ctx.backdropImage.view == vkNullImageView:
    return

  let backdropOldLayout =
    if ctx.backdropLayoutReady:
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    else:
      VK_IMAGE_LAYOUT_UNDEFINED
  let backdropSrcAccess =
    if ctx.backdropLayoutReady:
      VkAccessFlags{ShaderReadBit}
    else:
      0.VkAccessFlags
  let backdropSrcStage =
    if ctx.backdropLayoutReady:
      VkPipelineStageFlags{FragmentShaderBit}
    else:
      VkPipelineStageFlags{TopOfPipeBit}

  var backdropToTransfer = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: backdropSrcAccess,
    dstAccessMask: VkAccessFlags{TransferWriteBit},
    oldLayout: backdropOldLayout,
    newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.backdropImage.handle,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer,
    backdropSrcStage,
    VkPipelineStageFlags{TransferBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    backdropToTransfer.addr,
  )

  let swapchainImage = ctx.swapchainImages[ctx.acquiredImageIndex.int]
  var swapchainToTransfer = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
    dstAccessMask: VkAccessFlags{TransferReadBit},
    oldLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
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
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer,
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    VkPipelineStageFlags{TransferBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    swapchainToTransfer.addr,
  )

  var copyRegion = VkImageCopy(
    srcSubresource: newVkImageSubresourceLayers(
      aspectMask = VkImageAspectFlags{ColorBit},
      mipLevel = 0,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
    srcOffset: newVkOffset3D(x = blurRect.offset.x, y = blurRect.offset.y, z = 0),
    dstSubresource: newVkImageSubresourceLayers(
      aspectMask = VkImageAspectFlags{ColorBit},
      mipLevel = 0,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
    dstOffset: newVkOffset3D(x = blurRect.offset.x, y = blurRect.offset.y, z = 0),
    extent: newVkExtent3D(
      width = blurRect.extent.width, height = blurRect.extent.height, depth = 1
    ),
  )
  ctx.vk.vkCmdCopyImage(
    ctx.commandBuffer, swapchainImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    ctx.backdropImage.handle, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, copyRegion.addr,
  )

  var backdropToRead = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{TransferWriteBit},
    dstAccessMask: VkAccessFlags{ShaderReadBit},
    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.backdropImage.handle,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{FragmentShaderBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    backdropToRead.addr,
  )

  var swapchainToPresent = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{TransferReadBit},
    dstAccessMask: VkAccessFlags{ColorAttachmentReadBit, ColorAttachmentWriteBit},
    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    newLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
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
  ctx.vk.vkCmdPipelineBarrier(
    ctx.commandBuffer,
    VkPipelineStageFlags{TransferBit},
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    swapchainToPresent.addr,
  )
  ctx.backdropLayoutReady = true
  ctx.runBackdropSeparableBlur(blurRadius, blurRect)

  ctx.drawRoundedRectSdf(
    rect = rect,
    color = whiteColor,
    radii = radii,
    mode = figbackend.SdfMode.sdfModeBackdropBlur,
    factor = blurRadius,
    spread = 0.0'f32,
    shapeSize = vec2(0.0'f32, 0.0'f32),
  )

proc line*(ctx: VulkanContext, a: Vec2, b: Vec2, weight: float32, color: Color) =
  let hash = hash((2345, a, b, (weight * 100).int, hash(color)))

  let
    w = ceil(abs(b.x - a.x)).int
    h = ceil(abs(a.y - b.y)).int
    pos = vec2(min(a.x, b.x), min(a.y, b.y))

  if w == 0 or h == 0:
    return

  if hash notin ctx.entries:
    let
      image = newImage(w, h)
      c = newContext(image)
    c.fillStyle = rgba(255, 255, 255, 255)
    c.lineWidth = weight
    c.strokeSegment(segment(a - pos, b - pos))
    ctx.putImage(hash, image)
  let uvRect = ctx.entries[hash]
  ctx.drawUvRect(
    pos, pos + vec2(w.float32, h.float32), uvRect.xy, uvRect.xy + uvRect.wh, color
  )

proc linePolygon*(ctx: VulkanContext, poly: seq[Vec2], weight: float32, color: Color) =
  for i in 0 ..< poly.len:
    ctx.line(poly[i], poly[(i + 1) mod poly.len], weight, color)

proc intersectRects(a, b: Rect): Rect =
  let
    x0 = max(a.x, b.x)
    y0 = max(a.y, b.y)
    x1 = min(a.x + a.w, b.x + b.w)
    y1 = min(a.y + a.h, b.y + b.h)
  if x1 <= x0 or y1 <= y0:
    return rect(0, 0, 0, 0)
  rect(x0, y0, x1 - x0, y1 - y0)

proc clearMask*(ctx: VulkanContext) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  ctx.flush()

method beginMask*(ctx: VulkanContext, clipRect: Rect, radii: CornerRadii2D[float32]) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  assert ctx.maskBegun == false, "ctx.beginMask has already been called."
  ctx.flush()
  ctx.pendingMaskValid = false
  ctx.maskBegun = true
  inc ctx.maskDepth

  ctx.pendingMaskRect = clipRect
  ctx.pendingMaskValid = true

method endMask*(ctx: VulkanContext) =
  assert ctx.maskBegun == true, "ctx.maskBegun has not been called."
  ctx.flush()
  ctx.maskBegun = false

  let maskRect =
    if ctx.pendingMaskValid:
      ctx.pendingMaskRect
    else:
      ctx.fullFrameRect()
  let effective =
    if ctx.clipRects.len > 0:
      intersectRects(ctx.clipRects[^1], maskRect)
    else:
      maskRect
  ctx.clipRects.add(effective)
  ctx.applyClipScissor()
  ctx.pendingMaskValid = false

method popMask*(ctx: VulkanContext) =
  ctx.flush()
  if ctx.maskDepth > 0:
    dec ctx.maskDepth
  if ctx.clipRects.len > 0:
    discard ctx.clipRects.pop()
  ctx.applyClipScissor()

method beginRectMask*(
    ctx: VulkanContext, maskRect: Rect, radii: CornerRadii2D[float32]
) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  assert ctx.maskBegun == false, "ctx.beginRectMask cannot start inside a mask."

  if ctx.rectMaskStack.len == 0 and maskRect.w > 0.0'f32 and maskRect.h > 0.0'f32:
    ctx.rectMaskStack.add(ctx.makeRectMask(maskRect, radii))
  else:
    ctx.beginMask(maskRect, radii)
    ctx.endMask()
    ctx.rectMaskStack.add(RectMask(kind: rmkMask))

method popRectMask*(ctx: VulkanContext) =
  assert ctx.rectMaskStack.len > 0, "No rect mask has been pushed."
  let rectMask = ctx.rectMaskStack.pop()
  if rectMask.kind == rmkMask:
    ctx.popMask()

when defined(macosx):
  proc consumeAcquiredImage(ctx: VulkanContext) =
    ## Skip a visually stale acquired image while still consuming the acquire semaphore.
    let
      waitSemaphores = [ctx.imageAvailableSemaphore]
      waitStages = [VkPipelineStageFlags{ColorAttachmentOutputBit}]
      commandBuffers: array[0, VkCommandBuffer] = []
      signalSemaphores: array[0, VkSemaphore] = []

    checkVkResult ctx.vk.vkResetFences(ctx.device, 1, ctx.inFlightFence.addr)
    let submitInfo = newVkSubmitInfo(
      waitSemaphores = waitSemaphores,
      waitDstStageMask = waitStages,
      commandBuffers = commandBuffers,
      signalSemaphores = signalSemaphores,
    )
    checkVkResult ctx.vk.vkQueueSubmit(ctx.queue, 1, submitInfo.addr, ctx.inFlightFence)

proc beginFrame*(
    ctx: VulkanContext,
    frameSize: Vec2,
    proj: Mat4,
    clearMain = false,
    clearMainColor: Color = whiteColor,
) =
  assert ctx.frameBegun == false, "ctx.beginFrame has already been called."
  ctx.frameBegun = true
  ctx.commandRecording = false
  ctx.renderPassBegun = false
  ctx.maskBegun = false
  ctx.maskDepth = 0
  ctx.pendingMaskValid = false
  ctx.clipRects.setLen(0)
  ctx.rectMaskStack.setLen(0)
  ctx.batchHasRectMask = false
  ctx.frameSize = frameSize
  ctx.proj = proj
  ctx.frameNeedsClear = true
  ctx.frameClearColor =
    if clearMain:
      clearMainColor
    else:
      rgba(0, 0, 0, 255).color

  ctx.ensureGpuRuntime()

  let width = max(1, frameSize.x.int32)
  let height = max(1, frameSize.y.int32)
  ctx.ensureSwapchain(width, height)
  if ctx.swapchain == vkNullSwapchain:
    return
  checkVkResult ctx.vk.vkWaitForFences(
    ctx.device, 1, ctx.inFlightFence.addr, VkBool32(VkTrue), high(uint64)
  )
  ctx.recycleFrameResources()
  ctx.destroyRetiredSwapchains(onlyCompleted = true)
  ctx.ensureBackdropImage(
    ctx.swapchainExtent.width.int32, ctx.swapchainExtent.height.int32
  )

  let acquireResult = ctx.vk.vkAcquireNextImageKHR(
    ctx.device,
    ctx.swapchain,
    high(uint64),
    ctx.imageAvailableSemaphore,
    VkFence(0),
    ctx.acquiredImageIndex.addr,
  )
  if acquireResult == VkErrorOutOfDateKhr:
    ctx.swapchainOutOfDate = true
    debug "Acquire returned out-of-date", result = $acquireResult
    return
  for retired in ctx.retiredSwapchains.mitems:
    if retired.replacementSwapchain == ctx.swapchain and
        retired.replacementImage == ctx.acquiredImageIndex.int:
      # Submission waits on this acquire. Its fence will prove that the
      # presentation which followed all retired swapchains has finished.
      retired.awaitingFrameFence = true
  if acquireResult == VkSuboptimalKhr:
    ctx.swapchainOutOfDate = true
    debug "Acquire returned suboptimal", result = $acquireResult
    when defined(macosx):
      ctx.consumeAcquiredImage()
      return
  else:
    checkVkResult acquireResult
  checkVkResult ctx.vk.vkResetFences(ctx.device, 1, ctx.inFlightFence.addr)

  checkVkResult ctx.vk.vkResetCommandBuffer(
    ctx.commandBuffer, 0.VkCommandBufferResetFlags
  )
  let beginInfo = newVkCommandBufferBeginInfo(pInheritanceInfo = nil)
  checkVkResult ctx.vk.vkBeginCommandBuffer(ctx.commandBuffer, beginInfo.addr)
  ctx.commandRecording = true
  if not ctx.backdropLayoutReady:
    # The main shader statically references this descriptor even before the
    # first blur. Keep its declared layout valid for ordinary draws as well.
    var barrier = VkImageMemoryBarrier(
      sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      dstAccessMask: VkAccessFlags{ShaderReadBit},
      oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
      image: ctx.backdropImage.handle,
      subresourceRange: newVkImageSubresourceRange(
        aspectMask = VkImageAspectFlags{ColorBit},
        baseMipLevel = 0,
        levelCount = 1,
        baseArrayLayer = 0,
        layerCount = 1,
      ),
    )
    ctx.vk.vkCmdPipelineBarrier(
      ctx.commandBuffer,
      VkPipelineStageFlags{TopOfPipeBit},
      VkPipelineStageFlags{FragmentShaderBit},
      0.VkDependencyFlags,
      0,
      nil,
      0,
      nil,
      1,
      barrier.addr,
    )
    ctx.backdropLayoutReady = true
  ctx.transitionSwapchain(
    VK_IMAGE_LAYOUT_UNDEFINED,
    VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    0.VkAccessFlags,
    VkAccessFlags{ColorAttachmentReadBit, ColorAttachmentWriteBit},
  )

method beginFrame*(
    ctx: VulkanContext,
    frameSize: Vec2,
    clearMain = false,
    clearMainColor: Color = whiteColor,
) =
  beginFrame(
    ctx,
    frameSize,
    ortho[float32](0.0, frameSize.x, frameSize.y, 0, -1000.0, 1000.0),
    clearMain = clearMain,
    clearMainColor = clearMainColor,
  )

method endFrame*(ctx: VulkanContext) =
  assert ctx.frameBegun == true, "ctx.beginFrame was not called first."
  assert ctx.maskDepth == 0, "Not all masks have been popped."
  assert ctx.rectMaskStack.len == 0, "Not all rect masks have been popped."
  ctx.frameBegun = false

  if ctx.swapchain == vkNullSwapchain or not ctx.commandRecording:
    return

  ctx.flush()
  ctx.beginRenderPassIfNeeded()
  if ctx.renderPassBegun:
    ctx.vk.vkCmdEndRenderPass(ctx.commandBuffer)
    ctx.renderPassBegun = false
  when UseVulkanReadback:
    ctx.readbackReady = false
    ctx.recordSwapchainReadback()
  else:
    ctx.readbackReady = false
  ctx.transitionSwapchain(
    VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    VkImageLayout.PresentSrcKhr,
    VkPipelineStageFlags{ColorAttachmentOutputBit, TransferBit},
    VkPipelineStageFlags{BottomOfPipeBit},
    VkAccessFlags{ColorAttachmentWriteBit, TransferReadBit},
    0.VkAccessFlags,
  )
  checkVkResult ctx.vk.vkEndCommandBuffer(ctx.commandBuffer)

  let waitSemaphores = [ctx.imageAvailableSemaphore]
  let waitStages = [VkPipelineStageFlags{ColorAttachmentOutputBit, TransferBit}]
  let signalSemaphores = [ctx.renderFinishedSemaphores[ctx.acquiredImageIndex.int]]
  let submitInfo = newVkSubmitInfo(
    waitSemaphores = waitSemaphores,
    waitDstStageMask = waitStages,
    commandBuffers = [ctx.commandBuffer],
    signalSemaphores = signalSemaphores,
  )
  checkVkResult ctx.vk.vkQueueSubmit(ctx.queue, 1, submitInfo.addr, ctx.inFlightFence)

  let presentInfo = newVkPresentInfoKHR(
    waitSemaphores = signalSemaphores,
    swapchains = [ctx.swapchain],
    imageIndices = [ctx.acquiredImageIndex],
    results = @[],
  )
  let presentResult = ctx.vk.vkQueuePresentKHR(ctx.presentQueue, presentInfo.addr)
  var presented = false
  if presentResult == VkErrorOutOfDateKhr:
    ctx.swapchainOutOfDate = true
    debug "Present returned out-of-date", result = $presentResult
  elif presentResult == VkSuboptimalKhr:
    ctx.swapchainOutOfDate = true
    presented = true
    debug "Present returned suboptimal", result = $presentResult
  elif presentResult != VkSuccess:
    checkVkResult presentResult
  else:
    presented = true

  if presented:
    for retired in ctx.retiredSwapchains.mitems:
      if retired.replacementImage < 0:
        retired.replacementSwapchain = ctx.swapchain
        retired.replacementImage = ctx.acquiredImageIndex.int

  ctx.commandRecording = false

proc destroyGpu(ctx: VulkanContext) =
  if ctx.isNil:
    return

  if ctx.device != vkNullDevice:
    discard ctx.vk.vkDeviceWaitIdle(ctx.device)

  if ctx.imageAvailableSemaphore != vkNullSemaphore:
    ctx.vk.vkDestroySemaphore(ctx.device, ctx.imageAvailableSemaphore, nil)
    ctx.imageAvailableSemaphore = vkNullSemaphore
  if ctx.inFlightFence != vkNullFence:
    ctx.vk.vkDestroyFence(ctx.device, ctx.inFlightFence, nil)
    ctx.inFlightFence = vkNullFence

  if ctx.commandPool != vkNullCommandPool:
    ctx.vk.vkDestroyCommandPool(ctx.device, ctx.commandPool, nil)
    ctx.commandPool = vkNullCommandPool
    ctx.commandBuffer = vkNullCommandBuffer

  ctx.destroySwapchain()
  ctx.destroyRetiredSwapchains()
  ctx.destroyPipelineObjects()

  if ctx.vertShader != vkNullShaderModule:
    ctx.vk.destroyShaderModule(ctx.device, ctx.vertShader)
    ctx.vertShader = vkNullShaderModule
  if ctx.fragShader != vkNullShaderModule:
    ctx.vk.destroyShaderModule(ctx.device, ctx.fragShader)
    ctx.fragShader = vkNullShaderModule
  if ctx.blurVertShader != vkNullShaderModule:
    ctx.vk.destroyShaderModule(ctx.device, ctx.blurVertShader)
    ctx.blurVertShader = vkNullShaderModule
  if ctx.blurFragShader != vkNullShaderModule:
    ctx.vk.destroyShaderModule(ctx.device, ctx.blurFragShader)
    ctx.blurFragShader = vkNullShaderModule

  for pool in ctx.frameDescriptorPools:
    ctx.vk.destroyDescriptorPool(ctx.device, pool)
  ctx.frameDescriptorPools.setLen(0)
  if ctx.descriptorSetLayout != vkNullDescriptorSetLayout:
    ctx.vk.destroyDescriptorSetLayout(ctx.device, ctx.descriptorSetLayout)
    ctx.descriptorSetLayout = vkNullDescriptorSetLayout
  if ctx.blurDescriptorSetLayout != vkNullDescriptorSetLayout:
    ctx.vk.destroyDescriptorSetLayout(ctx.device, ctx.blurDescriptorSetLayout)
    ctx.blurDescriptorSetLayout = vkNullDescriptorSetLayout

  if ctx.atlasSampler != vkNullSampler:
    ctx.vk.vkDestroySampler(ctx.device, ctx.atlasSampler, nil)
    ctx.atlasSampler = vkNullSampler
  ctx.atlasImage = nil
  ctx.backdropImage = nil
  ctx.backdropBlurTempImage = nil
  ctx.indexBuffer = nil
  ctx.readbackBuffer = nil
  ctx.frameImages.setLen(0)
  ctx.uploadBlocks.setLen(0)

  if ctx.device != vkNullDevice:
    ctx.vk.destroyDevice(ctx.device)
    ctx.device = vkNullDevice

  if ctx.surface != vkNullSurface:
    if ctx.surfaceOwnedByContext:
      ctx.vk.vkDestroySurfaceKHR(ctx.instance, ctx.surface, nil)
    ctx.surface = vkNullSurface
    ctx.surfaceOwnedByContext = false

  if ctx.debugMessenger != VkDebugUtilsMessengerEXT(0):
    ctx.vk.vkDestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debugMessenger, nil)
    ctx.debugMessenger = VkDebugUtilsMessengerEXT(0)
  if ctx.instance != vkNullInstance:
    ctx.vk.destroyInstance(ctx.instance)
    ctx.instance = vkNullInstance
  ctx.vk = nil

  ctx.gpuReady = false
  ctx.presentReady = false
  ctx.commandRecording = false
  ctx.renderPassBegun = false
  ctx.frameNeedsClear = false
  ctx.swapchainOutOfDate = false
  ctx.swapchainTransferSrcSupported = false
  ctx.swapchainRequestedWidth = 0
  ctx.swapchainRequestedHeight = 0
  ctx.atlasLayoutReady = false
  ctx.backdropLayoutReady = false
  ctx.backdropBlurTempLayoutReady = false
  ctx.backdropWidth = 0
  ctx.backdropHeight = 0
  ctx.backdropFormat = VK_FORMAT_UNDEFINED
  ctx.readbackReady = false

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = quadLimit,
    pixelate = false,
    pixelScale = 1.0,
): VulkanContext =
  info "Starting Vulkan Context",
    atlasSize = atlasSize,
    atlasMargin = atlasMargin,
    maxQuads = maxQuads,
    quadLimit = quadLimit,
    pixelate = pixelate,
    pixelScale = pixelScale
  if atlasSize <= 0 or atlasSize > 16_384 or atlasMargin < 0 or
      atlasMargin > atlasSize div 2:
    raise newException(ValueError, "Invalid Vulkan atlas size or margin")
  if maxQuads <= 0 or maxQuads > quadLimit:
    raise newException(ValueError, &"Quads cannot exceed {quadLimit}")

  result = VulkanContext()
  result.atlasSize = atlasSize
  result.initialAtlasSize = atlasSize
  result.atlasMargin = atlasMargin
  result.maxQuads = maxQuads
  result.mat = mat4()
  result.mats = @[]
  result.entries = initTable[Hash, Rect]()
  result.atlasEntryMeta = initTable[Hash, AtlasEntryMeta]()
  result.heights = newSeq[uint16](atlasSize)
  result.pixelate = pixelate
  result.pixelScale = pixelScale
  result.aaFactor = figbackend.DefaultSdfAaFactor
  result.textLcdFilteringEnabled = false
  result.textSubpixelPositioningEnabled = false
  result.textSubpixelGlyphVariantsEnabled = false
  result.textSubpixelShift = 0.0'f32
  result.atlasPixels = newImage(atlasSize, atlasSize)
  result.atlasPixels.fill(rgba(0, 0, 0, 0))
  result.atlasDirty = true
  result.atlasLayoutReady = false
  result.ensureImageMessageSubscription()
  result.noteAtlasCreated()

  result.positions = newSeq[float32](2 * maxQuads * 4)
  result.colors = newSeq[uint8](4 * maxQuads * 4)
  result.fillMidColors = newSeq[uint8](4 * maxQuads * 4)
  result.fillStopColors = newSeq[uint8](4 * maxQuads * 4)
  result.uvs = newSeq[float32](2 * maxQuads * 4)
  result.sdfParams = newSeq[float32](4 * maxQuads * 4)
  result.sdfRadii = newSeq[float32](4 * maxQuads * 4)
  result.sdfModeAttr = newSeq[SdfModeData](maxQuads * 4)
  result.sdfFactors = newSeq[float32](2 * maxQuads * 4)
  result.rectMaskParams = newSeq[float32](4 * maxQuads * 4)
  result.rectMaskRadii = newSeq[float32](4 * maxQuads * 4)
  result.rectMaskMatX = newSeq[float32](4 * maxQuads * 4)
  result.rectMaskMatY = newSeq[float32](4 * maxQuads * 4)
  result.vertexScratch = newSeq[Vertex](maxQuads * 4)

  result.indices = newSeq[uint16](maxQuads * 6)
  for i in 0 ..< maxQuads:
    let offset = i * 4
    let base = i * 6
    result.indices[base + 0] = (offset + 3).uint16
    result.indices[base + 1] = (offset + 0).uint16
    result.indices[base + 2] = (offset + 1).uint16
    result.indices[base + 3] = (offset + 2).uint16
    result.indices[base + 4] = (offset + 3).uint16
    result.indices[base + 5] = (offset + 1).uint16

  result.instance = vkNullInstance
  result.physicalDevice = vkNullPhysicalDevice
  result.device = vkNullDevice
  result.queue = vkNullQueue
  result.queueFamily = 0
  result.presentQueue = vkNullQueue
  result.presentQueueFamily = 0
  result.presentTargetKind = presentTargetNone
  result.instanceSurfaceHint = presentTargetNone
  when defined(linux) or defined(bsd):
    result.linuxSurfaceKind = linuxSurfaceXlib
  result.surface = vkNullSurface
  result.surfaceOwnedByContext = false
  result.swapchain = vkNullSwapchain
  result.swapchainViews = @[]
  result.swapchainImages = @[]
  result.swapchainFramebuffers = @[]
  result.retiredSwapchains = @[]
  result.swapchainFormat = VK_FORMAT_UNDEFINED
  result.swapchainExtent = VkExtent2D(width: 0, height: 0)
  result.swapchainRequestedWidth = 0
  result.swapchainRequestedHeight = 0
  result.swapchainOutOfDate = false
  result.swapchainTransferSrcSupported = false
  result.requestedSwapchainProfile = vspAuto
  result.activeSwapchainProfile = vspAuto
  result.presentReady = false
  result.readbackBuffer = nil
  result.readbackBytes = 0.VkDeviceSize
  result.readbackWidth = 0
  result.readbackHeight = 0
  result.readbackReady = false
  result.atlasImage = nil
  result.backdropImage = nil
  result.backdropBlurTempImage = nil
  result.backdropLayoutReady = false
  result.backdropBlurTempLayoutReady = false
  result.backdropWidth = 0
  result.backdropHeight = 0
  result.backdropFormat = VK_FORMAT_UNDEFINED
  result.backdropBlurFramebuffer = vkNullFramebuffer
  result.backdropBlurTempFramebuffer = vkNullFramebuffer
  result.blurRenderPass = vkNullRenderPass
  result.blurDescriptorSetLayout = vkNullDescriptorSetLayout
  result.blurDescriptorSets = [vkNullDescriptorSet, vkNullDescriptorSet]
  result.blurPipelineLayout = vkNullPipelineLayout
  result.blurPipeline = vkNullPipeline
  result.blurVertShader = vkNullShaderModule
  result.blurFragShader = vkNullShaderModule
  result.atlasSampler = vkNullSampler
  result.indexBuffer = nil
  result.indexBufferBytes = 0.VkDeviceSize
  result.commandPool = vkNullCommandPool
  result.commandBuffer = vkNullCommandBuffer
  result.imageAvailableSemaphore = vkNullSemaphore
  result.inFlightFence = vkNullFence
  result.descriptorSetLayout = vkNullDescriptorSetLayout
  result.descriptorSet = vkNullDescriptorSet
  result.pipelineLayout = vkNullPipelineLayout
  result.pipeline = vkNullPipeline
  result.renderPass = vkNullRenderPass
  result.vertShader = vkNullShaderModule
  result.fragShader = vkNullShaderModule
  result.frameSize = vec2(1.0'f32, 1.0'f32)
  result.proj = mat4()
  result.pendingMaskRect = rect(0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
  result.pendingMaskValid = false
  result.clipRects = @[]
  result.renderPassBegun = false
  result.frameNeedsClear = false
  result.frameClearColor = rgba(0, 0, 0, 255).color

method translate*(ctx: VulkanContext, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))

method rotate*(ctx: VulkanContext, angle: float32) =
  ctx.mat = ctx.mat * rotateZ(angle)

method scale*(ctx: VulkanContext, s: float32) =
  ctx.mat = ctx.mat * scale(vec3(s))

method scale*(ctx: VulkanContext, s: Vec2) =
  ctx.mat = ctx.mat * scale(vec3(s.x, s.y, 1))

method applyTransform*(ctx: VulkanContext, m: Mat4) =
  ctx.mat = ctx.mat * m

method saveTransform*(ctx: VulkanContext) =
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: VulkanContext) =
  if ctx.mats.len > 0:
    ctx.mat = ctx.mats.pop()

method transformMirrorsY*(ctx: VulkanContext): bool =
  let origin = (ctx.mat * vec3(0.0'f32, 0.0'f32, 1.0'f32)).xy
  let xAxis = (ctx.mat * vec3(1.0'f32, 0.0'f32, 1.0'f32)).xy - origin
  let yAxis = (ctx.mat * vec3(0.0'f32, 1.0'f32, 1.0'f32)).xy - origin
  let determinant = xAxis.x * yAxis.y - xAxis.y * yAxis.x
  determinant < 0.0'f32

proc clearTransform*(ctx: VulkanContext) =
  ctx.mat = mat4()
  ctx.mats.setLen(0)

proc fromScreen*(ctx: VulkanContext, windowFrame: Vec2, v: Vec2): Vec2 =
  (ctx.mat.inverse() * vec3(v.x, windowFrame.y - v.y, 0)).xy

proc toScreen*(ctx: VulkanContext, windowFrame: Vec2, v: Vec2): Vec2 =
  result = (ctx.mat * vec3(v.x, v.y, 1)).xy
  result.y = -result.y + windowFrame.y

proc clearPresentTarget*(ctx: VulkanContext) =
  if ctx.gpuReady:
    ctx.destroyGpu()
  elif ctx.surface != vkNullSurface:
    if ctx.surfaceOwnedByContext and ctx.instance != vkNullInstance:
      ctx.vk.vkDestroySurfaceKHR(ctx.instance, ctx.surface, nil)
    ctx.surface = vkNullSurface
    ctx.surfaceOwnedByContext = false
  ctx.presentTargetKind = presentTargetNone
  ctx.instanceSurfaceHint = presentTargetNone
  when defined(linux) or defined(bsd):
    ctx.linuxSurfaceKind = linuxSurfaceXlib
  ctx.presentXlibDisplay = nil
  ctx.presentXlibWindow = 0
  ctx.presentWaylandDisplay = nil
  ctx.presentWaylandSurface = nil
  ctx.presentWin32Hinstance = nil
  ctx.presentWin32Hwnd = nil
  ctx.presentMetalLayer = nil

proc releaseBackendResources*(ctx: VulkanContext) =
  ## Fully releases Vulkan before the renderer abandons this context.
  ## clearPresentTarget intentionally preserves a pre-created instance so a
  ## caller can replace its target; a backend fallback no longer needs it.
  ctx.destroyGpu()
  ctx.clearPresentTarget()

proc setSwapchainProfile*(ctx: VulkanContext, profile: VulkanSwapchainProfile) =
  if ctx.requestedSwapchainProfile == profile:
    return
  ctx.requestedSwapchainProfile = profile
  ctx.activeSwapchainProfile =
    if ctx.physicalDevice != vkNullPhysicalDevice:
      chooseSwapchainProfile(profile, ctx.driverInfo)
    else:
      profile
  if ctx.swapchain != vkNullSwapchain:
    ctx.swapchainOutOfDate = true

proc swapchainProfile*(ctx: VulkanContext): VulkanSwapchainProfile =
  ctx.requestedSwapchainProfile

proc activeSwapchainProfile*(ctx: VulkanContext): VulkanSwapchainProfile =
  ctx.activeSwapchainProfile

proc vulkanDriverInfo*(ctx: VulkanContext): VulkanDriverInfo =
  ctx.driverInfo

method setPresentXlibTarget*(ctx: VulkanContext, display: pointer, window: uint64) =
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetXlib
  ctx.instanceSurfaceHint = presentTargetXlib
  ctx.presentXlibDisplay = display
  ctx.presentXlibWindow = window

proc setPresentWaylandTarget*(ctx: VulkanContext, display: pointer, surface: pointer) =
  if display.isNil or surface.isNil:
    raise newException(ValueError, "Wayland Vulkan display or surface handle is nil")
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetWayland
  ctx.instanceSurfaceHint = presentTargetWayland
  ctx.presentWaylandDisplay = display
  ctx.presentWaylandSurface = surface

method setPresentWin32Target*(ctx: VulkanContext, hinstance: pointer, hwnd: pointer) =
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetWin32
  ctx.instanceSurfaceHint = presentTargetWin32
  ctx.presentWin32Hinstance = hinstance
  ctx.presentWin32Hwnd = hwnd

proc setPresentMetalLayer*(ctx: VulkanContext, layer: pointer) =
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetMetal
  ctx.instanceSurfaceHint = presentTargetMetal
  ctx.presentMetalLayer = layer

proc setInstanceSurfaceHint*(ctx: VulkanContext, target: PresentTargetKind) =
  if ctx.gpuReady:
    raise newException(
      ValueError, "Cannot change Vulkan surface hint after GPU runtime init"
    )
  ctx.instanceSurfaceHint = target

proc ensureInstance*(ctx: VulkanContext) =
  if ctx.instance != vkNullInstance:
    return
  ctx.instance = ctx.createInstanceWithFallback()
  ctx.vk.loadInstance(ctx.instance)
  when UseVulkanValidation:
    let debugInfo = newVkDebugUtilsMessengerCreateInfoEXT(
      messageSeverity = VkDebugUtilsMessageSeverityFlagsEXT{WarningBit, ErrorBit},
      messageType =
        VkDebugUtilsMessageTypeFlagsEXT{GeneralBit, ValidationBit, PerformanceBit},
      pfnUserCallback = validationCallback,
      pUserData = ctx.validationErrors.addr,
    )
    checkVkResult ctx.vk.vkCreateDebugUtilsMessengerEXT(
      ctx.instance, debugInfo.addr, nil, ctx.debugMessenger.addr
    )

proc instanceHandle*(ctx: VulkanContext): pointer =
  cast[pointer](ctx.instance)

proc setExternalSurface*(
    ctx: VulkanContext,
    surface: pointer,
    target: PresentTargetKind,
    ownedByContext = false,
) =
  if surface.isNil:
    raise newException(ValueError, "External Vulkan surface pointer is nil")
  ctx.clearPresentTarget()
  ctx.presentTargetKind = target
  ctx.instanceSurfaceHint = ctx.presentTargetKind
  ctx.surface = cast[VkSurfaceKHR](surface)
  ctx.surfaceOwnedByContext = ownedByContext

method readPixels*(
    ctx: VulkanContext, frame: Rect = rect(0, 0, 0, 0), readFront = true
): Image =
  when not UseVulkanReadback:
    discard readFront
    raise newException(
      ValueError,
      "Vulkan readPixels is disabled; build with -d:figdraw.vulkanReadback=on",
    )
  else:
    discard readFront
    if not ctx.gpuReady:
      raise newException(ValueError, "Vulkan context is not initialized")
    if ctx.readbackBuffer.isNilOrEmpty or not ctx.readbackReady:
      raise newException(ValueError, "No Vulkan frame has been rendered yet")
    if ctx.readbackWidth <= 0 or ctx.readbackHeight <= 0:
      raise newException(ValueError, "Vulkan readback dimensions are invalid")

    checkVkResult ctx.vk.vkWaitForFences(
      ctx.device, 1, ctx.inFlightFence.addr, VkBool32(VkTrue), high(uint64)
    )

    let texW = ctx.readbackWidth.int
    let texH = ctx.readbackHeight.int

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

    let mapped = cast[ptr UncheckedArray[uint8]](ctx.vk.mapMemory(
      ctx.device, ctx.readbackBuffer.allocation, 0.VkDeviceSize, ctx.readbackBytes,
      0.VkMemoryMapFlags,
    ))
    if mapped.isNil:
      raise newException(ValueError, "Failed to map Vulkan readback memory")
    defer:
      ctx.vk.unmapMemory(ctx.device, ctx.readbackBuffer.allocation)

    result = newImage(w, h)
    let stride = texW * 4
    let bgrFormat =
      case ctx.swapchainFormat
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

method kind*(ctx: VulkanContext): figbackend.RendererBackendKind =
  figbackend.RendererBackendKind.rbVulkan

method entriesPtr*(ctx: VulkanContext): ptr Table[Hash, Rect] =
  ctx.entries.addr

method atlasEntryMetaPtr*(ctx: VulkanContext): var Table[Hash, AtlasEntryMeta] =
  result = ctx.atlasEntryMeta

method atlasSize*(ctx: VulkanContext): int =
  ctx.atlasSize

method atlasPackedArea*(ctx: VulkanContext): int =
  for height in ctx.heights:
    result += int(height)

method pixelScale*(ctx: VulkanContext): float32 =
  ctx.pixelScale

method textLcdFilteringEnabled*(ctx: VulkanContext): bool =
  ctx.textLcdFilteringEnabled

method setTextLcdFilteringEnabled*(ctx: VulkanContext, enabled: bool) =
  ctx.textLcdFilteringEnabled = enabled

method textSubpixelPositioningEnabled*(ctx: VulkanContext): bool =
  ctx.textSubpixelPositioningEnabled

method setTextSubpixelPositioningEnabled*(ctx: VulkanContext, enabled: bool) =
  ctx.textSubpixelPositioningEnabled = enabled

method textSubpixelGlyphVariantsEnabled*(ctx: VulkanContext): bool =
  ctx.textSubpixelGlyphVariantsEnabled

method setTextSubpixelGlyphVariantsEnabled*(ctx: VulkanContext, enabled: bool) =
  ctx.textSubpixelGlyphVariantsEnabled = enabled

method setTextSubpixelShift*(ctx: VulkanContext, shift: float32) =
  ctx.textSubpixelShift = shift
