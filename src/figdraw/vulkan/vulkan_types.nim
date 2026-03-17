import pkg/chroma
import pkg/vulkan
import pkg/vulkan/wrapper

import ../commons
import ./vresource

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

    renderPass*: VkRenderPass
    descriptorSetLayout*: VkDescriptorSetLayout
    descriptorPool*: VkDescriptorPool
    descriptorSet*: VkDescriptorSet
    pipelineLayout*: VkPipelineLayout
    pipeline*: VkPipeline
    vertShader*: VkShaderModule
    fragShader*: VkShaderModule

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
    backdropBlurFramebuffer*: VResource[GpuFramebuffer]
    backdropBlurTempFramebuffer*: VResource[GpuFramebuffer]
    blurRenderPass*: VkRenderPass
    blurDescriptorSetLayout*: VkDescriptorSetLayout
    blurDescriptorPool*: VkDescriptorPool
    blurDescriptorSets*: array[2, VkDescriptorSet]
    blurPipelineLayout*: VkPipelineLayout
    blurPipeline*: VkPipeline
    blurVertShader*: VkShaderModule
    blurFragShader*: VkShaderModule
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
  gpu.backdropBlurFramebuffer.reset()
  gpu.backdropBlurTempFramebuffer.reset()

  if gpu.blurPipeline != vkNullPipeline:
    vkDestroyPipeline(gpu.device, gpu.blurPipeline, nil)
    gpu.blurPipeline = vkNullPipeline
  if gpu.blurPipelineLayout != vkNullPipelineLayout:
    vkDestroyPipelineLayout(gpu.device, gpu.blurPipelineLayout, nil)
    gpu.blurPipelineLayout = vkNullPipelineLayout
  if gpu.blurRenderPass != vkNullRenderPass:
    vkDestroyRenderPass(gpu.device, gpu.blurRenderPass, nil)
    gpu.blurRenderPass = vkNullRenderPass

  if gpu.pipeline != vkNullPipeline:
    vkDestroyPipeline(gpu.device, gpu.pipeline, nil)
    gpu.pipeline = vkNullPipeline
  if gpu.pipelineLayout != vkNullPipelineLayout:
    vkDestroyPipelineLayout(gpu.device, gpu.pipelineLayout, nil)
    gpu.pipelineLayout = vkNullPipelineLayout
  if gpu.renderPass != vkNullRenderPass:
    vkDestroyRenderPass(gpu.device, gpu.renderPass, nil)
    gpu.renderPass = vkNullRenderPass

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

  if gpu.vertShader != vkNullShaderModule:
    destroyShaderModule(gpu.device, gpu.vertShader)
    gpu.vertShader = vkNullShaderModule
  if gpu.fragShader != vkNullShaderModule:
    destroyShaderModule(gpu.device, gpu.fragShader)
    gpu.fragShader = vkNullShaderModule
  if gpu.blurVertShader != vkNullShaderModule:
    destroyShaderModule(gpu.device, gpu.blurVertShader)
    gpu.blurVertShader = vkNullShaderModule
  if gpu.blurFragShader != vkNullShaderModule:
    destroyShaderModule(gpu.device, gpu.blurFragShader)
    gpu.blurFragShader = vkNullShaderModule

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
