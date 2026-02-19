import std/[hashes, math, strformat, tables]

import pkg/pixie
import pkg/pixie/simd
import pkg/chroma
import pkg/chronicles
import pkg/vulkan
import pkg/vulkan/wrapper

import ../commons
import ../figbackend as figbackend
import ../common/formatflippy
import ../fignodes
import ../utils/drawextras
import ./vulkan_utils

export drawextras

logScope:
  scope = "vulkan"

const
  quadLimit = 10_921
  sdfVertSpv = staticRead("shaders/sdf.vert.spv")
  sdfFragSpv = staticRead("shaders/sdf.frag.spv")

when defined(emscripten):
  type SdfModeData = float32
else:
  type SdfModeData = uint16

type SdfMode* = figbackend.SdfMode

type PresentTargetKind* = enum
  presentTargetNone
  presentTargetXlib
  presentTargetWayland
  presentTargetWin32
  presentTargetMetal

when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
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

  Vertex = object
    pos: array[2, float32]
    uv: array[2, float32]
    color: array[4, uint8]
    sdfParams: array[4, float32]
    sdfRadii: array[4, float32]
    sdfMode: uint16
    sdfPad: uint16
    sdfFactors: array[2, float32]

  VulkanContext* = ref object of figbackend.BackendContext
    atlasSize: int
    atlasMargin: int
    quadCount: int
    maxQuads: int
    mat*: Mat4
    mats: seq[Mat4]
    entries*: Table[Hash, Rect]
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

    positions: seq[float32]
    colors: seq[uint8]
    uvs: seq[float32]
    sdfParams: seq[float32]
    sdfRadii: seq[float32]
    sdfModeAttr: seq[SdfModeData]
    sdfFactors: seq[float32]
    indices: seq[uint16]
    vertexScratch: seq[Vertex]

    atlasPixels: Image
    atlasDirty: bool
    atlasLayoutReady: bool

    instance: VkInstance
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
    presentWin32Hinstance: pointer
    presentWin32Hwnd: pointer
    presentMetalLayer: pointer
    when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
      linuxSurfaceKind: LinuxSurfaceKind

    surface: VkSurfaceKHR
    surfaceOwnedByContext: bool
    swapchain: VkSwapchainKHR
    swapchainImages: seq[VkImage]
    swapchainViews: seq[VkImageView]
    swapchainFramebuffers: seq[VkFramebuffer]
    swapchainFormat: VkFormat
    swapchainExtent: VkExtent2D
    swapchainOutOfDate: bool
    swapchainTransferSrcSupported: bool
    presentReady: bool

    renderPass: VkRenderPass
    descriptorSetLayout: VkDescriptorSetLayout
    descriptorPool: VkDescriptorPool
    descriptorSet: VkDescriptorSet
    pipelineLayout: VkPipelineLayout
    pipeline: VkPipeline
    vertShader: VkShaderModule
    fragShader: VkShaderModule

    commandPool: VkCommandPool
    commandBuffer: VkCommandBuffer
    imageAvailableSemaphore: VkSemaphore
    renderFinishedSemaphore: VkSemaphore
    inFlightFence: VkFence
    acquiredImageIndex: uint32
    commandRecording: bool
    renderPassBegun: bool
    frameNeedsClear: bool
    frameClearColor: Color
    readbackBuffer: VkBuffer
    readbackMemory: VkDeviceMemory
    readbackBytes: VkDeviceSize
    readbackWidth: int32
    readbackHeight: int32
    readbackReady: bool

    atlasImage: VkImage
    atlasImageMemory: VkDeviceMemory
    atlasView: VkImageView
    atlasSampler: VkSampler
    atlasUploadBuffer: VkBuffer
    atlasUploadMemory: VkDeviceMemory
    atlasUploadBytes: VkDeviceSize

    vertexBuffer: VkBuffer
    vertexMemory: VkDeviceMemory
    vertexBufferBytes: VkDeviceSize
    frameVertexBuffers: seq[VkBuffer]
    frameVertexMemories: seq[VkDeviceMemory]
    indexBuffer: VkBuffer
    indexMemory: VkDeviceMemory
    indexBufferBytes: VkDeviceSize
    vsUniformBuffer: VkBuffer
    vsUniformMemory: VkDeviceMemory
    fsUniformBuffer: VkBuffer
    fsUniformMemory: VkDeviceMemory

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
  vkNullImage = VkImage(0)
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

proc hasPresentTarget(ctx: VulkanContext): bool =
  ctx.presentTargetKind != presentTargetNone

method hasImage*(ctx: VulkanContext, key: Hash): bool =
  key in ctx.entries

proc tryGetImageRect(ctx: VulkanContext, imageId: Hash, rect: var Rect): bool

proc createBuffer(
    ctx: VulkanContext,
    size: VkDeviceSize,
    usage: VkBufferUsageFlags,
    properties: VkMemoryPropertyFlags,
): tuple[buffer: VkBuffer, memory: VkDeviceMemory] =
  let bufferInfo = newVkBufferCreateInfo(
    size = size,
    usage = usage,
    sharingMode = VkSharingMode.Exclusive,
    queueFamilyIndices = [],
  )
  result.buffer = createBuffer(ctx.device, bufferInfo)

  let req = getBufferMemoryRequirements(ctx.device, result.buffer)
  let alloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex = findMemoryType(ctx.physicalDevice, req.memoryTypeBits, properties),
  )
  result.memory = allocateMemory(ctx.device, alloc)
  bindBufferMemory(ctx.device, result.buffer, result.memory, 0.VkDeviceSize)

proc createPresentSurface(ctx: VulkanContext) =
  if not ctx.hasPresentTarget() or ctx.instance == vkNullInstance:
    return
  if ctx.surface != vkNullSurface:
    return

  case ctx.presentTargetKind
  of presentTargetXlib:
    when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
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
    raise newException(
      ValueError, "Wayland Vulkan surface creation requires an external surface handle"
    )
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
      ctx.surfaceOwnedByContext = true
    else:
      raise newException(ValueError, "Win32 Vulkan surface unsupported on this OS")
  of presentTargetMetal:
    when defined(macosx):
      loadVK_EXT_metal_surface()
      let createInfo = newVkMetalSurfaceCreateInfoEXT(
        pLayer = cast[ptr CAMetalLayer](ctx.presentMetalLayer)
      )
      checkVkResult vkCreateMetalSurfaceEXT(
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
): tuple[image: VkImage, memory: VkDeviceMemory] =
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
  checkVkResult vkCreateImage(ctx.device, info.addr, nil, result.image.addr)

  var req: VkMemoryRequirements
  vkGetImageMemoryRequirements(ctx.device, result.image, req.addr)
  let alloc = newVkMemoryAllocateInfo(
    allocationSize = req.size,
    memoryTypeIndex = findMemoryType(ctx.physicalDevice, req.memoryTypeBits, properties),
  )
  checkVkResult vkAllocateMemory(ctx.device, alloc.addr, nil, result.memory.addr)
  checkVkResult vkBindImageMemory(
    ctx.device, result.image, result.memory, 0.VkDeviceSize
  )

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
  checkVkResult vkCreateImageView(ctx.device, info.addr, nil, result.addr)

proc fullFrameRect(ctx: VulkanContext): Rect =
  rect(0.0'f32, 0.0'f32, ctx.frameSize.x, ctx.frameSize.y)

proc destroySwapchain(ctx: VulkanContext) =
  for fb in ctx.swapchainFramebuffers:
    if fb != vkNullFramebuffer:
      vkDestroyFramebuffer(ctx.device, fb, nil)
  ctx.swapchainFramebuffers.setLen(0)

  for view in ctx.swapchainViews:
    if view != vkNullImageView:
      vkDestroyImageView(ctx.device, view, nil)
  ctx.swapchainViews.setLen(0)
  ctx.swapchainImages.setLen(0)

  if ctx.swapchain != vkNullSwapchain:
    vkDestroySwapchainKHR(ctx.device, ctx.swapchain, nil)
    ctx.swapchain = vkNullSwapchain

proc destroyPipelineObjects(ctx: VulkanContext) =
  if ctx.pipeline != vkNullPipeline:
    vkDestroyPipeline(ctx.device, ctx.pipeline, nil)
    ctx.pipeline = vkNullPipeline
  if ctx.pipelineLayout != vkNullPipelineLayout:
    vkDestroyPipelineLayout(ctx.device, ctx.pipelineLayout, nil)
    ctx.pipelineLayout = vkNullPipelineLayout
  if ctx.renderPass != vkNullRenderPass:
    vkDestroyRenderPass(ctx.device, ctx.renderPass, nil)
    ctx.renderPass = vkNullRenderPass

proc updateDescriptorSet(ctx: VulkanContext) =
  var vsInfo = newVkDescriptorBufferInfo(
    buffer = ctx.vsUniformBuffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(VSUniforms)),
  )
  var fsInfo = newVkDescriptorBufferInfo(
    buffer = ctx.fsUniformBuffer,
    offset = 0.VkDeviceSize,
    range = VkDeviceSize(sizeof(FSUniforms)),
  )
  var atlasImageInfo = newVkDescriptorImageInfo(
    sampler = ctx.atlasSampler,
    imageView = ctx.atlasView,
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
  ]
  updateDescriptorSets(ctx.device, writes, [])

proc recreateAtlasGpu(ctx: VulkanContext) =
  if ctx.atlasView != vkNullImageView:
    vkDestroyImageView(ctx.device, ctx.atlasView, nil)
    ctx.atlasView = vkNullImageView
  if ctx.atlasImage != vkNullImage:
    vkDestroyImage(ctx.device, ctx.atlasImage, nil)
    ctx.atlasImage = vkNullImage
  if ctx.atlasImageMemory != vkNullMemory:
    vkFreeMemory(ctx.device, ctx.atlasImageMemory, nil)
    ctx.atlasImageMemory = vkNullMemory

  let atlasAlloc = ctx.createImage(
    width = ctx.atlasSize.uint32,
    height = ctx.atlasSize.uint32,
    format = VK_FORMAT_R8G8B8A8_UNORM,
    tiling = VK_IMAGE_TILING_OPTIMAL,
    usage = VkImageUsageFlags{SampledBit, TransferDstBit},
    properties = VkMemoryPropertyFlags{DeviceLocalBit},
  )
  ctx.atlasImage = atlasAlloc.image
  ctx.atlasImageMemory = atlasAlloc.memory
  ctx.atlasView = ctx.createImageView(
    ctx.atlasImage, VK_FORMAT_R8G8B8A8_UNORM, VkImageAspectFlags{ColorBit}
  )
  ctx.atlasDirty = true
  ctx.atlasLayoutReady = false
  if ctx.descriptorSet != vkNullDescriptorSet:
    ctx.updateDescriptorSet()

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
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
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
  checkVkResult vkCreateRenderPass(
    ctx.device, renderPassInfo.addr, nil, ctx.renderPass.addr
  )

  if ctx.vertShader == vkNullShaderModule:
    let vertInfo = newVkShaderModuleCreateInfo(code = sdfVertSpv)
    ctx.vertShader = createShaderModule(ctx.device, vertInfo)
  if ctx.fragShader == vkNullShaderModule:
    let fragInfo = newVkShaderModuleCreateInfo(code = sdfFragSpv)
    ctx.fragShader = createShaderModule(ctx.device, fragInfo)

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
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfParams)),
    ),
    VkVertexInputAttributeDescription(
      location: 4,
      binding: 0,
      format: VK_FORMAT_R32G32B32A32_SFLOAT,
      offset: uint32(offsetOf(Vertex, sdfRadii)),
    ),
    VkVertexInputAttributeDescription(
      location: 5,
      binding: 0,
      format: VK_FORMAT_R16_UINT,
      offset: uint32(offsetOf(Vertex, sdfMode)),
    ),
    VkVertexInputAttributeDescription(
      location: 6,
      binding: 0,
      format: VK_FORMAT_R32G32_SFLOAT,
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
    setLayouts = [ctx.descriptorSetLayout], pushConstantRanges = []
  )
  ctx.pipelineLayout = createPipelineLayout(ctx.device, pipelineLayoutInfo)

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
  checkVkResult vkCreateGraphicsPipelines(
    ctx.device, 0.VkPipelineCache, 1, pipelineInfo.addr, nil, ctx.pipeline.addr
  )

proc createSwapchain(ctx: VulkanContext, width, height: int32) =
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

  let imageUsage =
    if TransferSrcBit in support.capabilities.supportedUsageFlags:
      ctx.swapchainTransferSrcSupported = true
      VkImageUsageFlags{ColorAttachmentBit, TransferSrcBit}
    else:
      ctx.swapchainTransferSrcSupported = false
      warn "Vulkan swapchain does not support transfer src; readPixels disabled"
      VkImageUsageFlags{ColorAttachmentBit}

  var createInfo = newVkSwapchainCreateInfoKHR(
    surface = ctx.surface,
    minImageCount = imageCount,
    imageFormat = surfaceFormat.format,
    imageColorSpace = surfaceFormat.colorSpace,
    imageExtent = extent,
    imageArrayLayers = 1,
    imageUsage = imageUsage,
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

  var newSwapchain: VkSwapchainKHR
  checkVkResult vkCreateSwapchainKHR(
    ctx.device, createInfo.addr, nil, newSwapchain.addr
  )

  ctx.destroySwapchain()
  ctx.swapchain = newSwapchain

  var actualCount = imageCount
  discard vkGetSwapchainImagesKHR(ctx.device, ctx.swapchain, actualCount.addr, nil)
  ctx.swapchainImages.setLen(actualCount)
  if actualCount > 0:
    discard vkGetSwapchainImagesKHR(
      ctx.device, ctx.swapchain, actualCount.addr, ctx.swapchainImages[0].addr
    )

  ctx.swapchainViews.setLen(actualCount)
  for i in 0 ..< actualCount.int:
    ctx.swapchainViews[i] = ctx.createImageView(
      ctx.swapchainImages[i], surfaceFormat.format, VkImageAspectFlags{ColorBit}
    )

  ctx.swapchainFormat = surfaceFormat.format
  ctx.swapchainExtent = extent
  ctx.swapchainOutOfDate = false

  ctx.createPipeline()

  ctx.swapchainFramebuffers.setLen(ctx.swapchainViews.len)
  for i in 0 ..< ctx.swapchainViews.len:
    let info = newVkFramebufferCreateInfo(
      renderPass = ctx.renderPass,
      attachments = [ctx.swapchainViews[i]],
      width = ctx.swapchainExtent.width,
      height = ctx.swapchainExtent.height,
      layers = 1,
    )
    checkVkResult vkCreateFramebuffer(
      ctx.device, info.addr, nil, ctx.swapchainFramebuffers[i].addr
    )

  info "Created Vulkan swapchain",
    width = int(ctx.swapchainExtent.width),
    height = int(ctx.swapchainExtent.height),
    imageCount = ctx.swapchainImages.len,
    format = $ctx.swapchainFormat

proc clearFrameVertexUploads(ctx: VulkanContext) =
  for buf in ctx.frameVertexBuffers:
    if buf != vkNullBuffer:
      destroyBuffer(ctx.device, buf)
  ctx.frameVertexBuffers.setLen(0)

  for mem in ctx.frameVertexMemories:
    if mem != vkNullMemory:
      freeMemory(ctx.device, mem)
  ctx.frameVertexMemories.setLen(0)

proc ensureSwapchain(ctx: VulkanContext, width, height: int32) =
  if not ctx.presentReady or width <= 0 or height <= 0:
    return

  let needsRecreate =
    ctx.swapchain == vkNullSwapchain or ctx.swapchainOutOfDate or
    ctx.swapchainExtent.width != width.uint32 or
    ctx.swapchainExtent.height != height.uint32
  if not needsRecreate:
    return

  if ctx.device != vkNullDevice:
    discard vkDeviceWaitIdle(ctx.device)
    ctx.clearFrameVertexUploads()
    ctx.clearFrameVertexUploads()
  ctx.createSwapchain(width, height)

proc ensureAtlasUploadBuffer(ctx: VulkanContext, bytes: VkDeviceSize) =
  if ctx.atlasUploadBuffer != vkNullBuffer and ctx.atlasUploadBytes >= bytes:
    return

  if ctx.atlasUploadBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.atlasUploadBuffer)
    ctx.atlasUploadBuffer = vkNullBuffer
  if ctx.atlasUploadMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.atlasUploadMemory)
    ctx.atlasUploadMemory = vkNullMemory

  let alloc = ctx.createBuffer(
    size = bytes,
    usage = VkBufferUsageFlags{TransferSrcBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.atlasUploadBuffer = alloc.buffer
  ctx.atlasUploadMemory = alloc.memory
  ctx.atlasUploadBytes = bytes

proc ensureReadbackBuffer(ctx: VulkanContext, bytes: VkDeviceSize) =
  if ctx.readbackBuffer != vkNullBuffer and ctx.readbackBytes >= bytes:
    return

  if ctx.readbackBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.readbackBuffer)
    ctx.readbackBuffer = vkNullBuffer
  if ctx.readbackMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.readbackMemory)
    ctx.readbackMemory = vkNullMemory

  let alloc = ctx.createBuffer(
    size = bytes,
    usage = VkBufferUsageFlags{TransferDstBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.readbackBuffer = alloc.buffer
  ctx.readbackMemory = alloc.memory
  ctx.readbackBytes = bytes

proc recordAtlasUpload(ctx: VulkanContext, cmd: VkCommandBuffer) =
  let bytes = VkDeviceSize(ctx.atlasSize * ctx.atlasSize * 4)
  ctx.ensureAtlasUploadBuffer(bytes)

  let mapped = cast[ptr uint8](mapMemory(
    ctx.device, ctx.atlasUploadMemory, 0.VkDeviceSize, bytes, 0.VkMemoryMapFlags
  ))
  copyMem(mapped, ctx.atlasPixels.data[0].addr, int(bytes))
  unmapMemory(ctx.device, ctx.atlasUploadMemory)

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
    image: ctx.atlasImage,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  vkCmdPipelineBarrier(
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
      width = ctx.atlasSize.uint32, height = ctx.atlasSize.uint32, depth = 1
    ),
  )
  vkCmdCopyBufferToImage(
    cmd, ctx.atlasUploadBuffer, ctx.atlasImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1,
    region.addr,
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
    image: ctx.atlasImage,
    subresourceRange: newVkImageSubresourceRange(
      aspectMask = VkImageAspectFlags{ColorBit},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    ),
  )
  vkCmdPipelineBarrier(
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
  vkCmdCopyImageToBuffer(
    ctx.commandBuffer, swapchainImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    ctx.readbackBuffer, 1, copyRegion.addr,
  )

  var readbackBarrier = VkBufferMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{TransferWriteBit},
    dstAccessMask: VkAccessFlags{HostReadBit},
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    buffer: ctx.readbackBuffer,
    offset: 0.VkDeviceSize,
    size: readbackBytes,
  )
  vkCmdPipelineBarrier(
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
    ctx.commandBuffer,
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

  ctx.readbackWidth = width
  ctx.readbackHeight = height
  ctx.readbackReady = true

proc createInstanceWithFallback(ctx: VulkanContext): VkInstance =
  let loaderApiVersion = detectLoaderApiVersion()
  let availableExts = queryInstanceExtensionNames()
  let availableLayers = queryInstanceLayerNames()

  var enabledExtNames: seq[string] = @[]
  let surfaceTargetKind =
    if ctx.presentTargetKind != presentTargetNone:
      ctx.presentTargetKind
    else:
      ctx.instanceSurfaceHint
  if surfaceTargetKind != presentTargetNone:
    enabledExtNames.add(VkKhrSurfaceExtensionName)
    case surfaceTargetKind
    of presentTargetXlib:
      when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
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
      when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
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
  when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
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
  vkCmdSetScissor(ctx.commandBuffer, 0, 1, scissor.addr)

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
  vkCmdBeginRenderPass(
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
  vkCmdSetViewport(ctx.commandBuffer, 0, 1, viewport.addr)

  var fullScissor =
    newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = ctx.swapchainExtent)
  vkCmdSetScissor(ctx.commandBuffer, 0, 1, fullScissor.addr)

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
    vkCmdClearAttachments(ctx.commandBuffer, 1, clearAttachment.addr, 1, clearRect.addr)
    ctx.frameNeedsClear = false

  if ctx.clipRects.len > 0:
    ctx.applyClipScissor()

proc ensureGpuRuntime(ctx: VulkanContext) =
  if ctx.gpuReady:
    return

  vkPreload()
  debug "Starting Vulkan runtime initialization",
    hasPresentTarget = ctx.hasPresentTarget(),
    presentTarget = $ctx.presentTargetKind,
    xlibDisplay = cast[uint64](ctx.presentXlibDisplay),
    xlibWindow = ctx.presentXlibWindow,
    win32Hinstance = cast[uint64](ctx.presentWin32Hinstance),
    win32Hwnd = cast[uint64](ctx.presentWin32Hwnd)

  if ctx.instance == vkNullInstance:
    ctx.instance = ctx.createInstanceWithFallback()
    vkInit(ctx.instance, load1_2 = false, load1_3 = false)

  if ctx.hasPresentTarget():
    loadVK_KHR_surface()
    ctx.createPresentSurface()

  let devices = enumeratePhysicalDevices(ctx.instance)
  debug "Enumerated Vulkan physical devices", deviceCount = devices.len
  if devices.len == 0:
    raise newException(ValueError, "No Vulkan physical devices found")

  var wantPresent = ctx.hasPresentTarget()
  var selectedQueues: QueueFamilyIndices
  for device in devices:
    let devName = physicalDeviceName(device)
    let queues = findQueueFamilies(device, ctx.surface, requirePresent = wantPresent)
    if not queues.graphicsFound or not queues.presentFound:
      debug "Skipping Vulkan physical device (queue requirements)",
        device = devName,
        graphicsFound = queues.graphicsFound,
        presentFound = queues.presentFound,
        requirePresent = wantPresent
      continue

    if wantPresent:
      let hasSwapchain =
        checkDeviceExtensionSupport(device, @[VkKhrSwapchainExtensionName])
      debug "Vulkan physical device present support",
        device = devName,
        hasSwapchainExt = hasSwapchain,
        graphicsQueue = queues.graphicsFamily,
        presentQueue = queues.presentFamily
      if not hasSwapchain:
        continue
      let support = querySwapChainSupport(device, ctx.surface)
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
      let queues = findQueueFamilies(device, ctx.surface, requirePresent = false)
      if not queues.graphicsFound:
        debug "Skipping Vulkan physical device (no graphics queue)",
          device = physicalDeviceName(device)
        continue
      ctx.physicalDevice = device
      selectedQueues = queues
      debug "Selected Vulkan physical device without present requirements",
        device = physicalDeviceName(device), graphicsQueue = queues.graphicsFamily
      break

  if ctx.physicalDevice == vkNullPhysicalDevice:
    raise newException(ValueError, "No suitable Vulkan physical device found")

  ctx.queueFamily = selectedQueues.graphicsFamily
  ctx.presentQueueFamily =
    if wantPresent: selectedQueues.presentFamily else: selectedQueues.graphicsFamily
  debug "Using Vulkan queue families",
    graphicsQueue = ctx.queueFamily,
    presentQueue = ctx.presentQueueFamily,
    wantPresent = wantPresent

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

  let cmdAlloc = newVkCommandBufferAllocateInfo(
    commandPool = ctx.commandPool,
    level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    commandBufferCount = 1,
  )
  ctx.commandBuffer = allocateCommandBuffers(ctx.device, cmdAlloc)

  let semaphoreInfo = newVkSemaphoreCreateInfo()
  checkVkResult vkCreateSemaphore(
    ctx.device, semaphoreInfo.addr, nil, ctx.imageAvailableSemaphore.addr
  )
  checkVkResult vkCreateSemaphore(
    ctx.device, semaphoreInfo.addr, nil, ctx.renderFinishedSemaphore.addr
  )
  let fenceInfo = newVkFenceCreateInfo(flags = VkFenceCreateFlags{SignaledBit})
  checkVkResult vkCreateFence(ctx.device, fenceInfo.addr, nil, ctx.inFlightFence.addr)

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
  ]
  ctx.descriptorSetLayout = createDescriptorSetLayout(
    ctx.device, newVkDescriptorSetLayoutCreateInfo(bindings = setBindings)
  )

  let poolSizes = [
    newVkDescriptorPoolSize(
      `type` = VkDescriptorType.UniformBuffer, descriptorCount = 2
    ),
    newVkDescriptorPoolSize(
      `type` = VkDescriptorType.CombinedImageSampler, descriptorCount = 2
    ),
  ]
  ctx.descriptorPool = createDescriptorPool(
    ctx.device, newVkDescriptorPoolCreateInfo(maxSets = 1, poolSizes = poolSizes)
  )
  ctx.descriptorSet = allocateDescriptorSets(
    ctx.device,
    newVkDescriptorSetAllocateInfo(
      descriptorPool = ctx.descriptorPool, setLayouts = [ctx.descriptorSetLayout]
    ),
  )

  let vertexBytes = VkDeviceSize(sizeof(Vertex) * ctx.maxQuads * 4)
  let vertexAlloc = ctx.createBuffer(
    size = vertexBytes,
    usage = VkBufferUsageFlags{VertexBufferBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.vertexBuffer = vertexAlloc.buffer
  ctx.vertexMemory = vertexAlloc.memory
  ctx.vertexBufferBytes = vertexBytes

  let indexBytes = VkDeviceSize(sizeof(uint16) * ctx.indices.len)
  let indexAlloc = ctx.createBuffer(
    size = indexBytes,
    usage = VkBufferUsageFlags{IndexBufferBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.indexBuffer = indexAlloc.buffer
  ctx.indexMemory = indexAlloc.memory
  ctx.indexBufferBytes = indexBytes

  let mappedIdx = cast[ptr uint8](mapMemory(
    ctx.device, ctx.indexMemory, 0.VkDeviceSize, indexBytes, 0.VkMemoryMapFlags
  ))
  copyMem(mappedIdx, ctx.indices[0].addr, int(indexBytes))
  unmapMemory(ctx.device, ctx.indexMemory)

  let vsAlloc = ctx.createBuffer(
    size = VkDeviceSize(sizeof(VSUniforms)),
    usage = VkBufferUsageFlags{UniformBufferBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.vsUniformBuffer = vsAlloc.buffer
  ctx.vsUniformMemory = vsAlloc.memory

  let fsAlloc = ctx.createBuffer(
    size = VkDeviceSize(sizeof(FSUniforms)),
    usage = VkBufferUsageFlags{UniformBufferBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.fsUniformBuffer = fsAlloc.buffer
  ctx.fsUniformMemory = fsAlloc.memory

  let samplerInfo = newVkSamplerCreateInfo(
    magFilter = VK_FILTER_LINEAR,
    minFilter = VK_FILTER_LINEAR,
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
  checkVkResult vkCreateSampler(
    ctx.device, samplerInfo.addr, nil, ctx.atlasSampler.addr
  )

  ctx.recreateAtlasGpu()
  ctx.updateDescriptorSet()

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
    return
  if ctx.atlasDirty:
    if ctx.renderPassBegun:
      vkCmdEndRenderPass(ctx.commandBuffer)
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

  let uploadBytes = VkDeviceSize(vertexCount * sizeof(Vertex))
  let vertexAlloc = ctx.createBuffer(
    size = uploadBytes,
    usage = VkBufferUsageFlags{VertexBufferBit},
    properties = VkMemoryPropertyFlags{HostVisibleBit, HostCoherentBit},
  )
  ctx.frameVertexBuffers.add(vertexAlloc.buffer)
  ctx.frameVertexMemories.add(vertexAlloc.memory)

  let mappedVertex = cast[ptr uint8](mapMemory(
    ctx.device, vertexAlloc.memory, 0.VkDeviceSize, uploadBytes, 0.VkMemoryMapFlags
  ))
  copyMem(mappedVertex, ctx.vertexScratch[0].addr, int(uploadBytes))
  unmapMemory(ctx.device, vertexAlloc.memory)

  var vsu = VSUniforms(proj: ctx.proj)
  var fsu = FSUniforms(
    windowFrame: ctx.frameSize, aaFactor: ctx.aaFactor, maskTexEnabled: 0'u32
  )

  let mappedVs = cast[ptr uint8](mapMemory(
    ctx.device,
    ctx.vsUniformMemory,
    0.VkDeviceSize,
    VkDeviceSize(sizeof(VSUniforms)),
    0.VkMemoryMapFlags,
  ))
  copyMem(mappedVs, vsu.addr, sizeof(VSUniforms))
  unmapMemory(ctx.device, ctx.vsUniformMemory)

  let mappedFs = cast[ptr uint8](mapMemory(
    ctx.device,
    ctx.fsUniformMemory,
    0.VkDeviceSize,
    VkDeviceSize(sizeof(FSUniforms)),
    0.VkMemoryMapFlags,
  ))
  copyMem(mappedFs, fsu.addr, sizeof(FSUniforms))
  unmapMemory(ctx.device, ctx.fsUniformMemory)

  vkCmdBindPipeline(ctx.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipeline)

  let vbs = [vertexAlloc.buffer]
  let offs = [0.VkDeviceSize]
  vkCmdBindVertexBuffers(ctx.commandBuffer, 0, 1, vbs[0].unsafeAddr, offs[0].unsafeAddr)
  vkCmdBindIndexBuffer(
    ctx.commandBuffer, ctx.indexBuffer, 0.VkDeviceSize, VK_INDEX_TYPE_UINT16
  )
  vkCmdBindDescriptorSets(
    ctx.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipelineLayout, 0, 1,
    ctx.descriptorSet.addr, 0, nil,
  )

  let indexCount = uint32(ctx.quadCount * 6)
  vkCmdDrawIndexed(ctx.commandBuffer, indexCount, 1, 0, 0, 0)
  ctx.quadCount = 0

proc checkBatch(ctx: VulkanContext) =
  if not ctx.commandRecording:
    # Keep CPU-side batch empty when Vulkan recording is unavailable.
    ctx.quadCount = 0
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

func `*`*(m: Mat4, v: Vec2): Vec2 =
  (m * vec3(v.x, v.y, 0.0)).xy

proc copyIntoAtlas(atlas: Image, atX, atY: int, image: Image) =
  for y in 0 ..< image.height:
    let dstRow = (atY + y) * atlas.width + atX
    let srcRow = y * image.width
    copyMem(
      atlas.data[dstRow].addr,
      image.data[srcRow].unsafeAddr,
      image.width * sizeof(ColorRGBA),
    )

proc grow(ctx: VulkanContext) =
  ctx.flush()
  ctx.atlasSize = ctx.atlasSize * 2
  info "grow atlasSize", atlasSize = ctx.atlasSize
  ctx.heights.setLen(ctx.atlasSize)
  ctx.entries.clear()
  ctx.atlasPixels = newImage(ctx.atlasSize, ctx.atlasSize)
  ctx.atlasPixels.fill(rgba(0, 0, 0, 0))
  if ctx.gpuReady:
    ctx.recreateAtlasGpu()

proc findEmptyRect(ctx: VulkanContext, width, height: int): Rect =
  let imgWidth = width + ctx.atlasMargin * 2
  let imgHeight = height + ctx.atlasMargin * 2

  var lowest = ctx.atlasSize
  var at = 0
  for i in 0 .. ctx.atlasSize - 1:
    let v = int(ctx.heights[i])
    if v < lowest:
      var fit = true
      for j in 0 .. imgWidth:
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
    ctx.heights[j] = uint16(lowest + imgHeight + ctx.atlasMargin * 2)

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
  copyIntoAtlas(ctx.atlasPixels, int(rect.x), int(rect.y), image)
  ctx.atlasDirty = true

method updateImage*(ctx: VulkanContext, path: Hash, image: Image) =
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

  inc ctx.quadCount

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

  inc ctx.quadCount

method drawMsdfImage*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMsdfAnnular else: SdfMode.sdfModeMsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = rect.xy,
    uvTo = rect.xy + rect.wh,
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
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMtsdfAnnular else: SdfMode.sdfModeMtsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = rect.xy,
    uvTo = rect.xy + rect.wh,
    color = color,
    mode = modeSel,
    factors = vec2(pxRange, sdThreshold),
    params = params,
  )

proc setSdfGlobals*(ctx: VulkanContext, aaFactor: float32) =
  if ctx.aaFactor == aaFactor:
    return
  ctx.aaFactor = aaFactor

proc drawUvRect(ctx: VulkanContext, at, to: Vec2, uvAt, uvTo: Vec2, color: Color) =
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

  inc ctx.quadCount

proc drawUvRect(ctx: VulkanContext, rect, uvRect: Rect, color: Color) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, color)

proc tryGetImageRect(ctx: VulkanContext, imageId: Hash, rect: var Rect): bool =
  if imageId notin ctx.entries:
    warn "missing image in context", imageId = imageId
    return false
  rect = ctx.entries[imageId]
  true

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

method drawImage*(ctx: VulkanContext, imageId: Hash, pos: Vec2, color: Color) =
  drawImage(ctx, imageId, pos, color, 1.0'f32)

method drawImage*(
    ctx: VulkanContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  ctx.drawUvRect(pos, pos + size, rect.xy, rect.xy + rect.wh, color)

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
    radii: array[DirectionCorners, float32],
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

method drawRoundedRectSdf*(
    ctx: VulkanContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: array[DirectionCorners, float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
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
    maxRadius = min(shapeHalfExtents.x, shapeHalfExtents.y)
    radiiClamped = [
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
    r4 = vec4(
      radiiClamped[dcTopRight],
      radiiClamped[dcBottomRight],
      radiiClamped[dcTopLeft],
      radiiClamped[dcBottomLeft],
    )

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

  ctx.sdfParams.setVert4(offset + 0, params)
  ctx.sdfParams.setVert4(offset + 1, params)
  ctx.sdfParams.setVert4(offset + 2, params)
  ctx.sdfParams.setVert4(offset + 3, params)

  ctx.sdfRadii.setVert4(offset + 0, r4)
  ctx.sdfRadii.setVert4(offset + 1, r4)
  ctx.sdfRadii.setVert4(offset + 2, r4)
  ctx.sdfRadii.setVert4(offset + 3, r4)

  let factors = vec2(factor, spread)
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

  inc ctx.quadCount

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

method beginMask*(
    ctx: VulkanContext, clipRect: Rect, radii: array[DirectionCorners, float32]
) =
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

  checkVkResult vkWaitForFences(
    ctx.device, 1, ctx.inFlightFence.addr, VkBool32(VkTrue), high(uint64)
  )
  ctx.clearFrameVertexUploads()

  let acquireResult = vkAcquireNextImageKHR(
    ctx.device,
    ctx.swapchain,
    high(uint64),
    ctx.imageAvailableSemaphore,
    VkFence(0),
    ctx.acquiredImageIndex.addr,
  )
  if acquireResult in [VkErrorOutOfDateKhr, VkSuboptimalKhr]:
    ctx.swapchainOutOfDate = true
    debug "Acquire returned out-of-date/suboptimal", result = $acquireResult
    return
  checkVkResult acquireResult
  checkVkResult vkResetFences(ctx.device, 1, ctx.inFlightFence.addr)

  checkVkResult vkResetCommandBuffer(ctx.commandBuffer, 0.VkCommandBufferResetFlags)
  let beginInfo = newVkCommandBufferBeginInfo(pInheritanceInfo = nil)
  checkVkResult vkBeginCommandBuffer(ctx.commandBuffer, beginInfo.addr)
  ctx.commandRecording = true

  if ctx.atlasDirty:
    ctx.recordAtlasUpload(ctx.commandBuffer)

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
  ctx.frameBegun = false

  if ctx.swapchain == vkNullSwapchain or not ctx.commandRecording:
    return

  ctx.flush()
  ctx.beginRenderPassIfNeeded()
  if ctx.renderPassBegun:
    vkCmdEndRenderPass(ctx.commandBuffer)
    ctx.renderPassBegun = false
  ctx.readbackReady = false
  ctx.recordSwapchainReadback()
  checkVkResult vkEndCommandBuffer(ctx.commandBuffer)

  let waitSemaphores = [ctx.imageAvailableSemaphore]
  let waitStages = [VkPipelineStageFlags{ColorAttachmentOutputBit, TransferBit}]
  let signalSemaphores = [ctx.renderFinishedSemaphore]
  let submitInfo = newVkSubmitInfo(
    waitSemaphores = waitSemaphores,
    waitDstStageMask = waitStages,
    commandBuffers = [ctx.commandBuffer],
    signalSemaphores = signalSemaphores,
  )
  checkVkResult vkQueueSubmit(ctx.queue, 1, submitInfo.addr, ctx.inFlightFence)

  let presentInfo = newVkPresentInfoKHR(
    waitSemaphores = signalSemaphores,
    swapchains = [ctx.swapchain],
    imageIndices = [ctx.acquiredImageIndex],
    results = @[],
  )
  let presentResult = vkQueuePresentKHR(ctx.presentQueue, presentInfo.addr)
  if presentResult in [VkErrorOutOfDateKhr, VkSuboptimalKhr]:
    ctx.swapchainOutOfDate = true
    debug "Present returned out-of-date/suboptimal", result = $presentResult
  elif presentResult != VkSuccess:
    checkVkResult presentResult

  ctx.commandRecording = false

proc destroyGpu(ctx: VulkanContext) =
  if ctx.isNil:
    return

  if ctx.device != vkNullDevice:
    discard vkDeviceWaitIdle(ctx.device)

  if ctx.imageAvailableSemaphore != vkNullSemaphore:
    vkDestroySemaphore(ctx.device, ctx.imageAvailableSemaphore, nil)
    ctx.imageAvailableSemaphore = vkNullSemaphore
  if ctx.renderFinishedSemaphore != vkNullSemaphore:
    vkDestroySemaphore(ctx.device, ctx.renderFinishedSemaphore, nil)
    ctx.renderFinishedSemaphore = vkNullSemaphore
  if ctx.inFlightFence != vkNullFence:
    vkDestroyFence(ctx.device, ctx.inFlightFence, nil)
    ctx.inFlightFence = vkNullFence

  if ctx.commandPool != vkNullCommandPool:
    vkDestroyCommandPool(ctx.device, ctx.commandPool, nil)
    ctx.commandPool = vkNullCommandPool
    ctx.commandBuffer = vkNullCommandBuffer

  ctx.destroySwapchain()
  ctx.destroyPipelineObjects()

  if ctx.vertShader != vkNullShaderModule:
    destroyShaderModule(ctx.device, ctx.vertShader)
    ctx.vertShader = vkNullShaderModule
  if ctx.fragShader != vkNullShaderModule:
    destroyShaderModule(ctx.device, ctx.fragShader)
    ctx.fragShader = vkNullShaderModule

  if ctx.descriptorPool != vkNullDescriptorPool:
    destroyDescriptorPool(ctx.device, ctx.descriptorPool)
    ctx.descriptorPool = vkNullDescriptorPool
  if ctx.descriptorSetLayout != vkNullDescriptorSetLayout:
    destroyDescriptorSetLayout(ctx.device, ctx.descriptorSetLayout)
    ctx.descriptorSetLayout = vkNullDescriptorSetLayout

  if ctx.atlasSampler != vkNullSampler:
    vkDestroySampler(ctx.device, ctx.atlasSampler, nil)
    ctx.atlasSampler = vkNullSampler
  if ctx.atlasView != vkNullImageView:
    vkDestroyImageView(ctx.device, ctx.atlasView, nil)
    ctx.atlasView = vkNullImageView
  if ctx.atlasImage != vkNullImage:
    vkDestroyImage(ctx.device, ctx.atlasImage, nil)
    ctx.atlasImage = vkNullImage
  if ctx.atlasImageMemory != vkNullMemory:
    vkFreeMemory(ctx.device, ctx.atlasImageMemory, nil)
    ctx.atlasImageMemory = vkNullMemory

  if ctx.atlasUploadBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.atlasUploadBuffer)
    ctx.atlasUploadBuffer = vkNullBuffer
  if ctx.atlasUploadMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.atlasUploadMemory)
    ctx.atlasUploadMemory = vkNullMemory

  if ctx.vertexBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.vertexBuffer)
    ctx.vertexBuffer = vkNullBuffer
  if ctx.vertexMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.vertexMemory)
    ctx.vertexMemory = vkNullMemory

  if ctx.indexBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.indexBuffer)
    ctx.indexBuffer = vkNullBuffer
  if ctx.indexMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.indexMemory)
    ctx.indexMemory = vkNullMemory

  if ctx.vsUniformBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.vsUniformBuffer)
    ctx.vsUniformBuffer = vkNullBuffer
  if ctx.vsUniformMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.vsUniformMemory)
    ctx.vsUniformMemory = vkNullMemory

  if ctx.fsUniformBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.fsUniformBuffer)
    ctx.fsUniformBuffer = vkNullBuffer
  if ctx.fsUniformMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.fsUniformMemory)
    ctx.fsUniformMemory = vkNullMemory

  if ctx.readbackBuffer != vkNullBuffer:
    destroyBuffer(ctx.device, ctx.readbackBuffer)
    ctx.readbackBuffer = vkNullBuffer
  if ctx.readbackMemory != vkNullMemory:
    freeMemory(ctx.device, ctx.readbackMemory)
    ctx.readbackMemory = vkNullMemory

  if ctx.device != vkNullDevice:
    destroyDevice(ctx.device)
    ctx.device = vkNullDevice

  if ctx.surface != vkNullSurface:
    if ctx.surfaceOwnedByContext:
      vkDestroySurfaceKHR(ctx.instance, ctx.surface, nil)
    ctx.surface = vkNullSurface
    ctx.surfaceOwnedByContext = false

  if ctx.instance != vkNullInstance:
    destroyInstance(ctx.instance)
    ctx.instance = vkNullInstance

  ctx.gpuReady = false
  ctx.presentReady = false
  ctx.commandRecording = false
  ctx.renderPassBegun = false
  ctx.frameNeedsClear = false
  ctx.swapchainOutOfDate = false
  ctx.swapchainTransferSrcSupported = false
  ctx.atlasLayoutReady = false
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
  if maxQuads > quadLimit:
    raise newException(ValueError, &"Quads cannot exceed {quadLimit}")

  result = VulkanContext()
  result.atlasSize = atlasSize
  result.atlasMargin = atlasMargin
  result.maxQuads = maxQuads
  result.mat = mat4()
  result.mats = @[]
  result.entries = initTable[Hash, Rect]()
  result.heights = newSeq[uint16](atlasSize)
  result.pixelate = pixelate
  result.pixelScale = pixelScale
  result.aaFactor = 1.2'f32
  result.atlasPixels = newImage(atlasSize, atlasSize)
  result.atlasPixels.fill(rgba(0, 0, 0, 0))
  result.atlasDirty = true
  result.atlasLayoutReady = false

  result.positions = newSeq[float32](2 * maxQuads * 4)
  result.colors = newSeq[uint8](4 * maxQuads * 4)
  result.uvs = newSeq[float32](2 * maxQuads * 4)
  result.sdfParams = newSeq[float32](4 * maxQuads * 4)
  result.sdfRadii = newSeq[float32](4 * maxQuads * 4)
  result.sdfModeAttr = newSeq[SdfModeData](maxQuads * 4)
  result.sdfFactors = newSeq[float32](2 * maxQuads * 4)
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
  when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
    result.linuxSurfaceKind = linuxSurfaceXlib
  result.surface = vkNullSurface
  result.surfaceOwnedByContext = false
  result.swapchain = vkNullSwapchain
  result.swapchainViews = @[]
  result.swapchainImages = @[]
  result.swapchainFramebuffers = @[]
  result.swapchainFormat = VK_FORMAT_UNDEFINED
  result.swapchainExtent = VkExtent2D(width: 0, height: 0)
  result.swapchainOutOfDate = false
  result.swapchainTransferSrcSupported = false
  result.presentReady = false
  result.readbackBuffer = vkNullBuffer
  result.readbackMemory = vkNullMemory
  result.readbackBytes = 0.VkDeviceSize
  result.readbackWidth = 0
  result.readbackHeight = 0
  result.readbackReady = false
  result.pendingMaskRect = rect(0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
  result.pendingMaskValid = false
  result.clipRects = @[]
  result.renderPassBegun = false
  result.frameNeedsClear = false
  result.frameClearColor = rgba(0, 0, 0, 255).color
  result.frameVertexBuffers = @[]
  result.frameVertexMemories = @[]

method translate*(ctx: VulkanContext, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))

method rotate*(ctx: VulkanContext, angle: float32) =
  ctx.mat = ctx.mat * rotateZ(angle)

method scale*(ctx: VulkanContext, s: float32) =
  ctx.mat = ctx.mat * scale(vec3(s))

method scale*(ctx: VulkanContext, s: Vec2) =
  ctx.mat = ctx.mat * scale(vec3(s.x, s.y, 1))

method saveTransform*(ctx: VulkanContext) =
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: VulkanContext) =
  if ctx.mats.len > 0:
    ctx.mat = ctx.mats.pop()

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
      vkDestroySurfaceKHR(ctx.instance, ctx.surface, nil)
    ctx.surface = vkNullSurface
    ctx.surfaceOwnedByContext = false
  ctx.presentTargetKind = presentTargetNone
  ctx.instanceSurfaceHint = presentTargetNone
  when defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
    ctx.linuxSurfaceKind = linuxSurfaceXlib
  ctx.presentXlibDisplay = nil
  ctx.presentXlibWindow = 0
  ctx.presentWin32Hinstance = nil
  ctx.presentWin32Hwnd = nil
  ctx.presentMetalLayer = nil

method setPresentXlibTarget*(ctx: VulkanContext, display: pointer, window: uint64) =
  ctx.clearPresentTarget()
  ctx.presentTargetKind = presentTargetXlib
  ctx.instanceSurfaceHint = presentTargetXlib
  ctx.presentXlibDisplay = display
  ctx.presentXlibWindow = window

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
  vkPreload()
  ctx.instance = ctx.createInstanceWithFallback()
  vkInit(ctx.instance, load1_2 = false, load1_3 = false)

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
  discard readFront
  if not ctx.gpuReady:
    raise newException(ValueError, "Vulkan context is not initialized")
  if ctx.readbackBuffer == vkNullBuffer or ctx.readbackMemory == vkNullMemory or
      not ctx.readbackReady:
    raise newException(ValueError, "No Vulkan frame has been rendered yet")
  if ctx.readbackWidth <= 0 or ctx.readbackHeight <= 0:
    raise newException(ValueError, "Vulkan readback dimensions are invalid")

  checkVkResult vkWaitForFences(
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

  let mapped = cast[ptr UncheckedArray[uint8]](mapMemory(
    ctx.device, ctx.readbackMemory, 0.VkDeviceSize, ctx.readbackBytes,
    0.VkMemoryMapFlags,
  ))
  if mapped.isNil:
    raise newException(ValueError, "Failed to map Vulkan readback memory")
  defer:
    unmapMemory(ctx.device, ctx.readbackMemory)

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

method pixelScale*(ctx: VulkanContext): float32 =
  ctx.pixelScale
