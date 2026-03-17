import pkg/chroma
import pkg/chronicles
import pkg/vulkan
import pkg/vulkan/wrapper

import ../commons
import ./vresource
import ./vulkan_utils

type PresentTargetKind* = enum
  presentTargetNone
  presentTargetXlib
  presentTargetWayland
  presentTargetWin32
  presentTargetMetal

when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
  type LinuxSurfaceKind* = enum
    linuxSurfaceXlib
    linuxSurfaceXcb

type
  VSUniforms* = object
    proj*: Mat4

  FSUniforms* = object
    windowFrame*: Vec2
    aaFactor*: float32
    maskTexEnabled*: uint32

  BlurUniforms* = object
    texelStep*: Vec2
    blurRadius*: float32
    pad0*: float32

  GpuBuffer* = object
    device*: VkDevice
    buffer*: VkBuffer
    memory*: VkDeviceMemory

  GpuImage* = object
    device*: VkDevice
    image*: VkImage
    memory*: VkDeviceMemory

  GpuImageView* = object
    device*: VkDevice
    view*: VkImageView

  GpuFramebuffer* = object
    device*: VkDevice
    framebuffer*: VkFramebuffer

  GpuHandle*[H] = object
    device*: VkDevice
    handle*: H

  GpuRenderPass* = GpuHandle[VkRenderPass]
  GpuPipelineLayout* = GpuHandle[VkPipelineLayout]
  GpuPipeline* = GpuHandle[VkPipeline]
  GpuShaderModule* = GpuHandle[VkShaderModule]

  MainPipelineState* = object
    renderPass*: VResource[GpuRenderPass]
    pipelineLayout*: VResource[GpuPipelineLayout]
    pipeline*: VResource[GpuPipeline]
    vertShader*: VResource[GpuShaderModule]
    fragShader*: VResource[GpuShaderModule]

  BlurPipelineState* = object
    renderPass*: VResource[GpuRenderPass]
    pipelineLayout*: VResource[GpuPipelineLayout]
    pipeline*: VResource[GpuPipeline]
    vertShader*: VResource[GpuShaderModule]
    fragShader*: VResource[GpuShaderModule]
    backdropBlurFramebuffer*: VResource[GpuFramebuffer]
    backdropBlurTempFramebuffer*: VResource[GpuFramebuffer]

  Vertex* = object
    pos*: array[2, float32]
    uv*: array[2, float32]
    color*: array[4, uint8]
    sdfParams*: array[4, float32]
    sdfRadii*: array[4, float32]
    sdfMode*: uint16
    sdfPad*: uint16
    sdfFactors*: array[2, float32]

  GpuState* = object
    instance*: VkInstance
    physicalDevice*: VkPhysicalDevice
    device*: VkDevice
    queue*: VkQueue
    queueFamily*: uint32
    presentQueue*: VkQueue
    presentQueueFamily*: uint32

    surface*: VkSurfaceKHR
    surfaceOwnedByContext*: bool
    swapchain*: VkSwapchainKHR
    swapchainImages*: seq[VkImage]
    swapchainViews*: seq[VkImageView]
    swapchainFramebuffers*: seq[VResource[GpuFramebuffer]]
    swapchainFormat*: VkFormat
    swapchainExtent*: VkExtent2D
    swapchainOutOfDate*: bool
    swapchainTransferSrcSupported*: bool
    presentReady*: bool

    pipelineState*: MainPipelineState
    descriptorSetLayout*: VkDescriptorSetLayout
    descriptorPool*: VkDescriptorPool
    descriptorSet*: VkDescriptorSet

    commandPool*: VkCommandPool
    commandBuffer*: VkCommandBuffer
    imageAvailableSemaphore*: VkSemaphore
    renderFinishedSemaphore*: VkSemaphore
    inFlightFence*: VkFence
    acquiredImageIndex*: uint32
    commandRecording*: bool
    renderPassBegun*: bool
    frameNeedsClear*: bool
    frameClearColor*: Color
    readback*: VResource[GpuBuffer]
    readbackBytes*: VkDeviceSize
    readbackWidth*: int32
    readbackHeight*: int32
    readbackReady*: bool

    atlasLayoutReady*: bool
    atlasImage*: VResource[GpuImage]
    atlasView*: VResource[GpuImageView]
    backdropImage*: VResource[GpuImage]
    backdropView*: VResource[GpuImageView]
    backdropBlurTempImage*: VResource[GpuImage]
    backdropBlurTempView*: VResource[GpuImageView]
    backdropLayoutReady*: bool
    backdropBlurTempLayoutReady*: bool
    backdropWidth*: int32
    backdropHeight*: int32
    backdropFormat*: VkFormat
    blurPipelineState*: BlurPipelineState
    blurDescriptorSetLayout*: VkDescriptorSetLayout
    blurDescriptorPool*: VkDescriptorPool
    blurDescriptorSets*: array[2, VkDescriptorSet]
    blurUniforms*: array[2, VResource[GpuBuffer]]
    atlasSampler*: VkSampler
    atlasUpload*: VResource[GpuBuffer]
    atlasUploadBytes*: VkDeviceSize

    vertex*: VResource[GpuBuffer]
    vertexBufferBytes*: VkDeviceSize
    frameVertices*: seq[VResource[GpuBuffer]]
    index*: VResource[GpuBuffer]
    indexBufferBytes*: VkDeviceSize
    vsUniform*: VResource[GpuBuffer]
    fsUniform*: VResource[GpuBuffer]

    gpuReady*: bool

const
  vkNullInstance = VkInstance(0)
  vkNullDevice = VkDevice(0)
  vkNullSurface = VkSurfaceKHR(0)
  vkNullSwapchain = VkSwapchainKHR(0)
  vkNullRenderPass = VkRenderPass(0)
  vkNullFramebuffer = VkFramebuffer(0)
  vkNullImageView = VkImageView(0)
  vkNullImage = VkImage(0)
  vkNullBuffer = VkBuffer(0)
  vkNullMemory = VkDeviceMemory(0)
  vkNullDescriptorSetLayout = VkDescriptorSetLayout(0)
  vkNullDescriptorPool = VkDescriptorPool(0)
  vkNullPipelineLayout = VkPipelineLayout(0)
  vkNullPipeline = VkPipeline(0)
  vkNullShaderModule = VkShaderModule(0)
  vkNullCommandPool = VkCommandPool(0)
  vkNullCommandBuffer = VkCommandBuffer(0)
  vkNullSemaphore = VkSemaphore(0)
  vkNullFence = VkFence(0)

proc isNil*(handle: VkRenderPass): bool =
  handle == vkNullRenderPass

proc isNil*(handle: VkPipelineLayout): bool =
  handle == vkNullPipelineLayout

proc isNil*(handle: VkPipeline): bool =
  handle == vkNullPipeline

proc isNil*(handle: VkShaderModule): bool =
  handle == vkNullShaderModule

proc destroyHandle*(device: VkDevice, handle: VkRenderPass) =
  vkDestroyRenderPass(device, handle, nil)

proc destroyHandle*(device: VkDevice, handle: VkPipelineLayout) =
  vkDestroyPipelineLayout(device, handle, nil)

proc destroyHandle*(device: VkDevice, handle: VkPipeline) =
  vkDestroyPipeline(device, handle, nil)

proc destroyHandle*(device: VkDevice, handle: VkShaderModule) =
  destroyShaderModule(device, handle)

proc `=destroy`*(resource: var GpuBuffer) =
  if resource.buffer != vkNullBuffer:
    destroyBuffer(resource.device, resource.buffer)
    resource.buffer = vkNullBuffer
  if resource.memory != vkNullMemory:
    freeMemory(resource.device, resource.memory)
    resource.memory = vkNullMemory
  resource.device = vkNullDevice

proc `=destroy`*(resource: var GpuImage) =
  if resource.image != vkNullImage:
    vkDestroyImage(resource.device, resource.image, nil)
    resource.image = vkNullImage
  if resource.memory != vkNullMemory:
    vkFreeMemory(resource.device, resource.memory, nil)
    resource.memory = vkNullMemory
  resource.device = vkNullDevice

proc `=destroy`*(resource: var GpuImageView) =
  if resource.view != vkNullImageView:
    vkDestroyImageView(resource.device, resource.view, nil)
    resource.view = vkNullImageView
  resource.device = vkNullDevice

proc `=destroy`*(resource: var GpuFramebuffer) =
  if resource.framebuffer != vkNullFramebuffer:
    vkDestroyFramebuffer(resource.device, resource.framebuffer, nil)
    resource.framebuffer = vkNullFramebuffer
  resource.device = vkNullDevice

proc `=destroy`*[H](resource: var GpuHandle[H]) =
  mixin destroyHandle, isNil
  if not isNil(resource.handle):
    destroyHandle(resource.device, resource.handle)
    resource.handle = default(H)
  resource.device = vkNullDevice

proc destroySwapchain*(gpu: var GpuState) =
  gpu.swapchainFramebuffers.setLen(0)

  for view in gpu.swapchainViews:
    if view != vkNullImageView:
      vkDestroyImageView(gpu.device, view, nil)
  gpu.swapchainViews.setLen(0)
  gpu.swapchainImages.setLen(0)

  if gpu.swapchain != vkNullSwapchain:
    vkDestroySwapchainKHR(gpu.device, gpu.swapchain, nil)
    gpu.swapchain = vkNullSwapchain

proc destroyPipelineObjects*(gpu: var GpuState) =
  gpu.blurPipelineState = BlurPipelineState()
  gpu.pipelineState = MainPipelineState()

proc clearFrameVertexUploads*(gpu: var GpuState) =
  gpu.frameVertices.setLen(0)

proc `=destroy`*(gpu: var GpuState) =
  if gpu.device != vkNullDevice:
    discard vkDeviceWaitIdle(gpu.device)

  if gpu.imageAvailableSemaphore != vkNullSemaphore:
    vkDestroySemaphore(gpu.device, gpu.imageAvailableSemaphore, nil)
    gpu.imageAvailableSemaphore = vkNullSemaphore
  if gpu.renderFinishedSemaphore != vkNullSemaphore:
    vkDestroySemaphore(gpu.device, gpu.renderFinishedSemaphore, nil)
    gpu.renderFinishedSemaphore = vkNullSemaphore
  if gpu.inFlightFence != vkNullFence:
    vkDestroyFence(gpu.device, gpu.inFlightFence, nil)
    gpu.inFlightFence = vkNullFence

  if gpu.commandPool != vkNullCommandPool:
    vkDestroyCommandPool(gpu.device, gpu.commandPool, nil)
    gpu.commandPool = vkNullCommandPool
    gpu.commandBuffer = vkNullCommandBuffer

  gpu.destroySwapchain()
  gpu.destroyPipelineObjects()

  if gpu.descriptorPool != vkNullDescriptorPool:
    destroyDescriptorPool(gpu.device, gpu.descriptorPool)
    gpu.descriptorPool = vkNullDescriptorPool
  if gpu.descriptorSetLayout != vkNullDescriptorSetLayout:
    destroyDescriptorSetLayout(gpu.device, gpu.descriptorSetLayout)
    gpu.descriptorSetLayout = vkNullDescriptorSetLayout
  if gpu.blurDescriptorPool != vkNullDescriptorPool:
    destroyDescriptorPool(gpu.device, gpu.blurDescriptorPool)
    gpu.blurDescriptorPool = vkNullDescriptorPool
  if gpu.blurDescriptorSetLayout != vkNullDescriptorSetLayout:
    destroyDescriptorSetLayout(gpu.device, gpu.blurDescriptorSetLayout)
    gpu.blurDescriptorSetLayout = vkNullDescriptorSetLayout

  if gpu.atlasSampler != VkSampler(0):
    vkDestroySampler(gpu.device, gpu.atlasSampler, nil)
    gpu.atlasSampler = VkSampler(0)
  gpu.atlasView.reset()
  gpu.atlasImage.reset()
  gpu.backdropView.reset()
  gpu.backdropImage.reset()
  gpu.backdropBlurTempView.reset()
  gpu.backdropBlurTempImage.reset()

  gpu.atlasUpload.reset()
  gpu.vertex.reset()
  gpu.index.reset()
  gpu.vsUniform.reset()
  gpu.fsUniform.reset()
  for i in 0 ..< gpu.blurUniforms.len:
    gpu.blurUniforms[i].reset()

  gpu.readback.reset()
  gpu.frameVertices.setLen(0)

  if gpu.device != vkNullDevice:
    destroyDevice(gpu.device)
    gpu.device = vkNullDevice

  if gpu.surface != vkNullSurface:
    if gpu.surfaceOwnedByContext:
      vkDestroySurfaceKHR(gpu.instance, gpu.surface, nil)
    gpu.surface = vkNullSurface
    gpu.surfaceOwnedByContext = false

  if gpu.instance != vkNullInstance:
    destroyInstance(gpu.instance)
    gpu.instance = vkNullInstance

proc initGpuBuffer*(
    device: VkDevice,
    physicalDevice: VkPhysicalDevice,
    size: VkDeviceSize,
    usage: VkBufferUsageFlags,
    properties: VkMemoryPropertyFlags,
): VResource[GpuBuffer] =
  let bufferInfo = newVkBufferCreateInfo(
    size = size,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = [],
  )
  var bufferAlloc = GpuBuffer(device: device)
  bufferAlloc.buffer = createBuffer(device, bufferInfo)

  let req = getBufferMemoryRequirements(device, bufferAlloc.buffer)
  let memoryAlloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex = findMemoryType(physicalDevice, req.memoryTypeBits, properties),
  )
  bufferAlloc.memory = allocateMemory(device, memoryAlloc)
  bindBufferMemory(device, bufferAlloc.buffer, bufferAlloc.memory, 0.VkDeviceSize)
  result = initVResource(bufferAlloc)

proc initGpuImage*(
    device: VkDevice,
    physicalDevice: VkPhysicalDevice,
    width, height: uint32,
    format: VkFormat,
    tiling: VkImageTiling,
    usage: VkImageUsageFlags,
    properties: VkMemoryPropertyFlags,
): VResource[GpuImage] =
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
  var alloc = GpuImage(device: device)
  checkVkResult vkCreateImage(device, info.addr, nil, alloc.image.addr)

  var req: VkMemoryRequirements
  vkGetImageMemoryRequirements(device, alloc.image, req.addr)
  let memoryAlloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex = findMemoryType(physicalDevice, req.memoryTypeBits, properties),
  )
  checkVkResult vkAllocateMemory(device, memoryAlloc.addr, nil, alloc.memory.addr)
  checkVkResult vkBindImageMemory(device, alloc.image, alloc.memory, 0.VkDeviceSize)
  result = initVResource(alloc)

proc initGpuImageView*(
    device: VkDevice, image: VkImage, format: VkFormat, aspectMask: VkImageAspectFlags
): VResource[GpuImageView] =
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
  var alloc = GpuImageView(device: device)
  checkVkResult vkCreateImageView(device, info.addr, nil, alloc.view.addr)
  result = initVResource(alloc)

proc initGpuFramebuffer*(
    device: VkDevice, info: VkFramebufferCreateInfo
): VResource[GpuFramebuffer] =
  var alloc = GpuFramebuffer(device: device)
  checkVkResult vkCreateFramebuffer(device, info.addr, nil, alloc.framebuffer.addr)
  result = initVResource(alloc)

proc initGpuRenderPass*(
    device: VkDevice, info: VkRenderPassCreateInfo
): VResource[GpuRenderPass] =
  var alloc = GpuRenderPass(device: device)
  checkVkResult vkCreateRenderPass(device, info.addr, nil, alloc.handle.addr)
  result = initVResource(alloc)

proc initGpuPipelineLayout*(
    device: VkDevice, info: VkPipelineLayoutCreateInfo
): VResource[GpuPipelineLayout] =
  var alloc = GpuPipelineLayout(device: device)
  alloc.handle = createPipelineLayout(device, info)
  result = initVResource(alloc)

proc initGpuPipeline*(
    device: VkDevice, info: VkGraphicsPipelineCreateInfo
): VResource[GpuPipeline] =
  var alloc = GpuPipeline(device: device)
  checkVkResult vkCreateGraphicsPipelines(
    device, 0.VkPipelineCache, 1, info.addr, nil, alloc.handle.addr
  )
  result = initVResource(alloc)

proc initGpuShaderModule*(
    device: VkDevice, info: VkShaderModuleCreateInfo
): VResource[GpuShaderModule] =
  var alloc = GpuShaderModule(device: device)
  alloc.handle = createShaderModule(device, info)
  result = initVResource(alloc)

when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
  proc createInstanceWithFallback*(
      presentTargetKind: PresentTargetKind,
      instanceSurfaceHint: PresentTargetKind,
      linuxSurfaceKind: var LinuxSurfaceKind,
  ): VkInstance =
    let loaderApiVersion = detectLoaderApiVersion()
    let availableExts = queryInstanceExtensionNames()
    let availableLayers = queryInstanceLayerNames()

    var enabledExtNames: seq[string] = @[]
    let surfaceTargetKind =
      if presentTargetKind != presentTargetNone:
        presentTargetKind
      else:
        instanceSurfaceHint
    if surfaceTargetKind != presentTargetNone:
      enabledExtNames.add(VkKhrSurfaceExtensionName)
      case surfaceTargetKind
      of presentTargetXlib:
        let hasXlib = VkKhrXlibSurfaceExtensionName in availableExts
        let hasXcb = VkKhrXcbSurfaceExtensionName in availableExts
        if hasXlib:
          linuxSurfaceKind = linuxSurfaceXlib
          enabledExtNames.add(VkKhrXlibSurfaceExtensionName)
        elif hasXcb:
          linuxSurfaceKind = linuxSurfaceXcb
          enabledExtNames.add(VkKhrXcbSurfaceExtensionName)
          warn "Vulkan XLIB surface extension unavailable; using XCB surface extension",
            selectedExtension = VkKhrXcbSurfaceExtensionName
        else:
          linuxSurfaceKind = linuxSurfaceXlib
          enabledExtNames.add(VkKhrXlibSurfaceExtensionName)
          warn "Neither VK_KHR_xlib_surface nor VK_KHR_xcb_surface reported as available"
      of presentTargetWayland:
        if VkKhrWaylandSurfaceExtensionName in availableExts:
          enabledExtNames.add(VkKhrWaylandSurfaceExtensionName)
        else:
          raise newException(
            ValueError, "VK_KHR_wayland_surface extension is required but unavailable"
          )
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
    debug "Selected Linux Vulkan surface extension mode",
      linuxSurfaceKind = $linuxSurfaceKind

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
      let instanceInfo = newVkInstanceCreateInfo(
        pApplicationInfo = appInfo.addr,
        pEnabledLayerNames = [],
        pEnabledExtensionNames = enabledExts,
      )
      try:
        debug "Creating Vulkan instance",
          requestedApiVersion = vulkanApiVersion(apiVersion),
          requestedExtensions = enabledExtNames
        return createInstance(instanceInfo)
      except VulkanError as exc:
        if exc.res == VkErrorIncompatibleDriver and apiVersion != vkApiVersion1_0:
          warn "Vulkan instance creation failed; retrying with older API version",
            attemptedApiVersion = vulkanApiVersion(apiVersion), reason = exc.msg
          continue
        raise

    raise newException(
      ValueError, "Failed to create Vulkan instance (no compatible Vulkan API version)"
    )
else:
  proc createInstanceWithFallback*(
      presentTargetKind: PresentTargetKind, instanceSurfaceHint: PresentTargetKind
  ): VkInstance =
    let loaderApiVersion = detectLoaderApiVersion()
    let availableExts = queryInstanceExtensionNames()
    let availableLayers = queryInstanceLayerNames()

    var enabledExtNames: seq[string] = @[]
    let surfaceTargetKind =
      if presentTargetKind != presentTargetNone:
        presentTargetKind
      else:
        instanceSurfaceHint
    if surfaceTargetKind != presentTargetNone:
      enabledExtNames.add(VkKhrSurfaceExtensionName)
      case surfaceTargetKind
      of presentTargetXlib:
        enabledExtNames.add(VkKhrXlibSurfaceExtensionName)
      of presentTargetWayland:
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
      let instanceInfo = newVkInstanceCreateInfo(
        pApplicationInfo = appInfo.addr,
        pEnabledLayerNames = [],
        pEnabledExtensionNames = enabledExts,
      )
      try:
        debug "Creating Vulkan instance",
          requestedApiVersion = vulkanApiVersion(apiVersion),
          requestedExtensions = enabledExtNames
        return createInstance(instanceInfo)
      except VulkanError as exc:
        if exc.res == VkErrorIncompatibleDriver and apiVersion != vkApiVersion1_0:
          warn "Vulkan instance creation failed; retrying with older API version",
            attemptedApiVersion = vulkanApiVersion(apiVersion), reason = exc.msg
          continue
        raise

    raise newException(
      ValueError, "Failed to create Vulkan instance (no compatible Vulkan API version)"
    )
proc applyClipScissor*(gpu: var GpuState, clipRects: seq[Rect], fullFrameRect: Rect) =
  if not gpu.commandRecording or gpu.swapchain == vkNullSwapchain or
      not gpu.renderPassBegun:
    return

  let clipRect =
    if clipRects.len > 0:
      clipRects[^1]
    else:
      fullFrameRect

  let maxW = max(0'i32, gpu.swapchainExtent.width.int32)
  let maxH = max(0'i32, gpu.swapchainExtent.height.int32)

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
  vkCmdSetScissor(gpu.commandBuffer, 0, 1, scissor.addr)

proc beginRenderPassIfNeeded*(
    gpu: var GpuState, clipRects: seq[Rect], fullFrameRect: Rect
) =
  if not gpu.commandRecording or gpu.swapchain == vkNullSwapchain or
      gpu.renderPassBegun:
    return

  let renderPassInfo = VkRenderPassBeginInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: nil,
    renderPass: gpu.pipelineState.renderPass[].handle,
    framebuffer: gpu.swapchainFramebuffers[gpu.acquiredImageIndex.int][].framebuffer,
    renderArea: newVkRect2D(
      offset = newVkOffset2D(x = 0, y = 0), extent = gpu.swapchainExtent
    ),
    clearValueCount: 0,
    pClearValues: nil,
  )
  vkCmdBeginRenderPass(gpu.commandBuffer, renderPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE)
  gpu.renderPassBegun = true

  let viewport = newVkViewport(
    x = 0,
    y = 0,
    width = gpu.swapchainExtent.width.float32,
    height = gpu.swapchainExtent.height.float32,
    minDepth = 0,
    maxDepth = 1,
  )
  vkCmdSetViewport(gpu.commandBuffer, 0, 1, viewport.addr)

  var fullScissor =
    newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = gpu.swapchainExtent)
  vkCmdSetScissor(gpu.commandBuffer, 0, 1, fullScissor.addr)

  if gpu.frameNeedsClear:
    let clearValue = VkClearValue(
      color: VkClearColorValue(
        float32: [
          gpu.frameClearColor.r.float32, gpu.frameClearColor.g.float32,
          gpu.frameClearColor.b.float32, gpu.frameClearColor.a.float32,
        ]
      )
    )
    var clearAttachment = VkClearAttachment(
      aspectMask: VkImageAspectFlags{ColorBit},
      colorAttachment: 0,
      clearValue: clearValue,
    )
    var clearRect = VkClearRect(
      rect: newVkRect2D(
        offset = newVkOffset2D(x = 0, y = 0), extent = gpu.swapchainExtent
      ),
      baseArrayLayer: 0,
      layerCount: 1,
    )
    vkCmdClearAttachments(gpu.commandBuffer, 1, clearAttachment.addr, 1, clearRect.addr)
    gpu.frameNeedsClear = false

  if clipRects.len > 0:
    gpu.applyClipScissor(clipRects, fullFrameRect)

proc ensureBackdropImage*(gpu: var GpuState, width, height: int32): bool =
  let w = max(1'i32, width)
  let h = max(1'i32, height)
  let backdropFormat =
    if gpu.swapchainFormat != VK_FORMAT_UNDEFINED:
      gpu.swapchainFormat
    else:
      VK_FORMAT_B8G8R8A8_UNORM
  if gpu.backdropImage.isInitialized() and gpu.backdropView.isInitialized() and
      gpu.backdropBlurTempImage.isInitialized() and
      gpu.backdropBlurTempView.isInitialized() and gpu.backdropWidth == w and
      gpu.backdropHeight == h and gpu.backdropFormat == backdropFormat:
    return false

  gpu.blurPipelineState.backdropBlurFramebuffer = VResource[GpuFramebuffer]()
  gpu.blurPipelineState.backdropBlurTempFramebuffer = VResource[GpuFramebuffer]()

  gpu.backdropBlurTempView.reset()
  gpu.backdropBlurTempImage.reset()
  gpu.backdropView.reset()
  gpu.backdropImage.reset()

  gpu.backdropImage = initGpuImage(
    device = gpu.device,
    physicalDevice = gpu.physicalDevice,
    width = w.uint32,
    height = h.uint32,
    format = backdropFormat,
    tiling = VK_IMAGE_TILING_OPTIMAL,
    usage = VkImageUsageFlags{SampledBit, TransferDstBit, ColorAttachmentBit},
    properties = VkMemoryPropertyFlags{DeviceLocalBit},
  )
  gpu.backdropView = initGpuImageView(
    device = gpu.device,
    image = gpu.backdropImage[].image,
    format = backdropFormat,
    aspectMask = VkImageAspectFlags{ColorBit},
  )
  gpu.backdropBlurTempImage = initGpuImage(
    device = gpu.device,
    physicalDevice = gpu.physicalDevice,
    width = w.uint32,
    height = h.uint32,
    format = backdropFormat,
    tiling = VK_IMAGE_TILING_OPTIMAL,
    usage = VkImageUsageFlags{SampledBit, ColorAttachmentBit},
    properties = VkMemoryPropertyFlags{DeviceLocalBit},
  )
  gpu.backdropBlurTempView = initGpuImageView(
    device = gpu.device,
    image = gpu.backdropBlurTempImage[].image,
    format = backdropFormat,
    aspectMask = VkImageAspectFlags{ColorBit},
  )
  gpu.backdropLayoutReady = false
  gpu.backdropBlurTempLayoutReady = false
  gpu.backdropWidth = w
  gpu.backdropHeight = h
  gpu.backdropFormat = backdropFormat
  result = true

proc createPipeline*(
    gpu: var GpuState,
    descriptorSetLayout: VkDescriptorSetLayout,
    vertCode, fragCode: openArray[char],
) =
  gpu.destroyPipelineObjects()

  var colorAttachment = VkAttachmentDescription(
    flags: 0.VkAttachmentDescriptionFlags,
    format: gpu.swapchainFormat,
    samples: VK_SAMPLE_COUNT_1_BIT,
    loadOp: VK_ATTACHMENT_LOAD_OP_LOAD,
    storeOp: VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout: VkImageLayout.PresentSrcKhr,
    finalLayout: VkImageLayout.PresentSrcKhr,
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
    srcAccessMask: 0.VkAccessFlags,
    dstAccessMask: VkAccessFlags{ColorAttachmentReadBit, ColorAttachmentWriteBit},
    dependencyFlags: 0.VkDependencyFlags,
  )

  let renderPassInfo = newVkRenderPassCreateInfo(
    attachments = [colorAttachment], subpasses = [subpass], dependencies = [dependency]
  )
  var pipelineState = MainPipelineState(
    renderPass: initGpuRenderPass(gpu.device, renderPassInfo)
  )
  pipelineState.vertShader = initGpuShaderModule(
    gpu.device, newVkShaderModuleCreateInfo(code = vertCode)
  )
  pipelineState.fragShader = initGpuShaderModule(
    gpu.device, newVkShaderModuleCreateInfo(code = fragCode)
  )

  let vertStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.VertexBit,
    module = pipelineState.vertShader[].handle,
    pName = "main",
    pSpecializationInfo = nil,
  )
  let fragStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.FragmentBit,
    module = pipelineState.fragShader[].handle,
    pName = "main",
    pSpecializationInfo = nil,
  )

  let bindingDesc = VkVertexInputBindingDescription(
    binding: 0,
    stride: uint32(sizeof(Vertex)),
    inputRate: VK_VERTEX_INPUT_RATE_VERTEX,
  )
  let attrDescs = [
    VkVertexInputAttributeDescription(
      location: 0, binding: 0, format: VK_FORMAT_R32G32_SFLOAT,
      offset: uint32(offsetOf(Vertex, pos)),
    ),
    VkVertexInputAttributeDescription(
      location: 1, binding: 0, format: VK_FORMAT_R32G32_SFLOAT,
      offset: uint32(offsetOf(Vertex, uv)),
    ),
    VkVertexInputAttributeDescription(
      location: 2, binding: 0, format: VK_FORMAT_R8G8B8A8_UNORM,
      offset: uint32(offsetOf(Vertex, color)),
    ),
    VkVertexInputAttributeDescription(
      location: 3, binding: 0, format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfParams)),
    ),
    VkVertexInputAttributeDescription(
      location: 4, binding: 0, format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfRadii)),
    ),
    VkVertexInputAttributeDescription(
      location: 5, binding: 0, format: VK_FORMAT_R16_UINT,
      offset: uint32(offsetOf(Vertex, sdfMode)),
    ),
    VkVertexInputAttributeDescription(
      location: 6, binding: 0, format: VK_FORMAT_R32G32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfFactors)),
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
    setLayouts = [descriptorSetLayout], pushConstantRanges = []
  )
  pipelineState.pipelineLayout = initGpuPipelineLayout(gpu.device, pipelineLayoutInfo)

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
    layout = pipelineState.pipelineLayout[].handle,
    renderPass = pipelineState.renderPass[].handle,
    subpass = 0,
    basePipelineHandle = 0.VkPipeline,
    basePipelineIndex = -1,
  )
  pipelineState.pipeline = initGpuPipeline(gpu.device, pipelineInfo)
  gpu.pipelineState = move(pipelineState)

template updateDescriptorSet*(ctx: untyped) =
  var vsInfo = newVkDescriptorBufferInfo(
    buffer = ctx.gpu.vsUniform[].buffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(VSUniforms)),
  )
  var fsInfo = newVkDescriptorBufferInfo(
    buffer = ctx.gpu.fsUniform[].buffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(FSUniforms)),
  )
  var atlasImageInfo = newVkDescriptorImageInfo(
    sampler = ctx.gpu.atlasSampler,
    imageView = ctx.gpu.atlasView[].view,
    imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
  )
  var backdropImageInfo = newVkDescriptorImageInfo(
    sampler = ctx.gpu.atlasSampler,
    imageView = (
      if ctx.gpu.backdropView.isInitialized():
        ctx.gpu.backdropView[].view
      else:
        ctx.gpu.atlasView[].view
    ),
    imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
  )

  let writes = [
    newVkWriteDescriptorSet(
      dstSet = ctx.gpu.descriptorSet,
      dstBinding = 0,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      pImageInfo = nil,
      pBufferInfo = vsInfo.addr,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.gpu.descriptorSet,
      dstBinding = 1,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      pImageInfo = nil,
      pBufferInfo = fsInfo.addr,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.gpu.descriptorSet,
      dstBinding = 2,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      pImageInfo = atlasImageInfo.addr,
      pBufferInfo = nil,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.gpu.descriptorSet,
      dstBinding = 3,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      pImageInfo = atlasImageInfo.addr,
      pBufferInfo = nil,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = ctx.gpu.descriptorSet,
      dstBinding = 4,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      pImageInfo = backdropImageInfo.addr,
      pBufferInfo = nil,
      pTexelBufferView = nil,
    ),
  ]
  updateDescriptorSets(ctx.gpu.device, writes, [])

template updateBlurDescriptorSet*(ctx, descriptorSet, srcView, uniformBuffer: untyped) =
  if srcView == vkNullImageView or descriptorSet == vkNullDescriptorSet or
      uniformBuffer == vkNullBuffer:
    return

  var srcInfo = newVkDescriptorImageInfo(
    sampler = ctx.gpu.atlasSampler,
    imageView = srcView,
    imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
  )
  var blurInfo = newVkDescriptorBufferInfo(
    buffer = uniformBuffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(BlurUniforms)),
  )

  let writes = [
    newVkWriteDescriptorSet(
      dstSet = descriptorSet,
      dstBinding = 0,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.CombinedImageSampler,
      pImageInfo = srcInfo.addr,
      pBufferInfo = nil,
      pTexelBufferView = nil,
    ),
    newVkWriteDescriptorSet(
      dstSet = descriptorSet,
      dstBinding = 1,
      dstArrayElement = 0,
      descriptorCount = 1,
      descriptorType = VkDescriptorType.UniformBuffer,
      pImageInfo = nil,
      pBufferInfo = blurInfo.addr,
      pTexelBufferView = nil,
    ),
  ]
  updateDescriptorSets(ctx.gpu.device, writes, [])

template updateBlurDescriptorSets*(ctx: untyped) =
  if ctx.gpu.blurDescriptorSets[0] == vkNullDescriptorSet or
      ctx.gpu.blurDescriptorSets[1] == vkNullDescriptorSet:
    return
  if not ctx.gpu.blurUniforms[0].isInitialized() or
      not ctx.gpu.blurUniforms[1].isInitialized():
    return
  let src0 = (
    if ctx.gpu.backdropView.isInitialized():
      ctx.gpu.backdropView[].view
    else:
      ctx.gpu.atlasView[].view
  )
  let src1 =
    if ctx.gpu.backdropBlurTempView.isInitialized():
      ctx.gpu.backdropBlurTempView[].view
    else:
      src0
  ctx.updateBlurDescriptorSet(
    descriptorSet = ctx.gpu.blurDescriptorSets[0],
    srcView = src0,
    uniformBuffer = ctx.gpu.blurUniforms[0][].buffer,
  )
  ctx.updateBlurDescriptorSet(
    descriptorSet = ctx.gpu.blurDescriptorSets[1],
    srcView = src1,
    uniformBuffer = ctx.gpu.blurUniforms[1][].buffer,
  )
