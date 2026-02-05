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

  gpuReady: bool

const
  vkNullInstance = VkInstance(0)
  vkNullPhysicalDevice = VkPhysicalDevice(0)
  vkNullDevice = VkDevice(0)
  vkNullQueue = VkQueue(0)
  vkNullCommandPool = VkCommandPool(0)
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

proc findQueueFamily(device: VkPhysicalDevice): int =
  let families = getQueueFamilyProperties(device)

  for i, family in families:
    if family.queueCount > 0 and VkQueueFlagBits.ComputeBit in family.queueFlags:
      return i

  for i, family in families:
    if family.queueCount > 0 and VkQueueFlagBits.GraphicsBit in family.queueFlags:
      return i

  result = -1

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
    usage = VkBufferUsageFlags{StorageBufferBit},
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
    pEnabledExtensionNames = [],
  )
  ctx.instance = createInstance(instanceInfo)

  vkInit(ctx.instance, load1_2 = false, load1_3 = false)

  let devices = enumeratePhysicalDevices(ctx.instance)
  if devices.len == 0:
    raise newException(ValueError, "No Vulkan physical devices found")

  for device in devices:
    let idx = findQueueFamily(device)
    if idx >= 0:
      ctx.physicalDevice = device
      ctx.queueFamily = idx.uint32
      break

  if ctx.physicalDevice == vkNullPhysicalDevice:
    raise newException(ValueError, "No Vulkan queue family for compute/graphics")

  let queueInfo = newVkDeviceQueueCreateInfo(
    queueFamilyIndex = ctx.queueFamily, queuePriorities = [1.0'f32]
  )
  let deviceInfo = newVkDeviceCreateInfo(
    queueCreateInfos = [queueInfo],
    pEnabledLayerNames = [],
    pEnabledExtensionNames = [],
    enabledFeatures = [],
  )
  ctx.device = createDevice(ctx.physicalDevice, deviceInfo)
  ctx.queue = getDeviceQueue(ctx.device, ctx.queueFamily, 0)

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

  ctx.gpuReady = true
  info "Initialized Vulkan compute pipeline", queueFamily = ctx.queueFamily

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
  if ctx.instance != vkNullInstance:
    destroyInstance(ctx.instance)
    ctx.instance = vkNullInstance

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

  result.ensureGpuRuntime()

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
  except CatchableError:
    # Keep rendering robust if Vulkan copy fails in constrained environments.
    ctx.lastFrame = ctx.canvas.copy()

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
