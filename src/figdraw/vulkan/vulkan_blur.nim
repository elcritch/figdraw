## Vulkan backdrop blur helpers shared by `vulkan_context.nim`.
##
## These are templates so they expand inside `vulkan_context` and can access
## that module's private context fields and Vulkan helper constants.

template vulkanBlurRecreateFramebuffers*(ctx: untyped) =
  ctx.gpu.backdropBlurFramebuffer.reset()
  ctx.gpu.backdropBlurTempFramebuffer.reset()
  if ctx.gpu.blurRenderPass == vkNullRenderPass:
    return
  if not ctx.gpu.backdropView.isInitialized() or
      not ctx.gpu.backdropBlurTempView.isInitialized():
    return
  if ctx.gpu.backdropWidth <= 0 or ctx.gpu.backdropHeight <= 0:
    return

  let tempInfo = newVkFramebufferCreateInfo(
    renderPass = ctx.gpu.blurRenderPass,
    attachments = [ctx.gpu.backdropBlurTempView[].view],
    width = ctx.gpu.backdropWidth.uint32,
    height = ctx.gpu.backdropHeight.uint32,
    layers = 1,
  )
  var tempFramebuffer = ctx.createFramebuffer(tempInfo)
  ctx.gpu.backdropBlurTempFramebuffer.reset(tempFramebuffer.release())

  let backdropInfo = newVkFramebufferCreateInfo(
    renderPass = ctx.gpu.blurRenderPass,
    attachments = [ctx.gpu.backdropView[].view],
    width = ctx.gpu.backdropWidth.uint32,
    height = ctx.gpu.backdropHeight.uint32,
    layers = 1,
  )
  var backdropFramebuffer = ctx.createFramebuffer(backdropInfo)
  ctx.gpu.backdropBlurFramebuffer.reset(backdropFramebuffer.release())

template vulkanBlurUpdateDescriptorSet*(
    ctx, descriptorSet, srcView, uniformBuffer: untyped
) =
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

template vulkanBlurUpdateDescriptorSets*(ctx: untyped) =
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

template vulkanBlurWriteUniforms*(ctx, uniformMemory, texelStep, blurRadius: untyped) =
  if uniformMemory == vkNullMemory:
    return
  var blurU = BlurUniforms(texelStep: texelStep, blurRadius: blurRadius, pad0: 0.0'f32)
  let mapped = cast[ptr uint8](mapMemory(
    ctx.gpu.device,
    uniformMemory,
    0.VkDeviceSize,
    VkDeviceSize(sizeof(BlurUniforms)),
    0.VkMemoryMapFlags,
  ))
  copyMem(mapped, blurU.addr, sizeof(BlurUniforms))
  unmapMemory(ctx.gpu.device, uniformMemory)

template vulkanBlurCreatePipeline*(ctx: untyped) =
  if ctx.gpu.swapchainFormat == VK_FORMAT_UNDEFINED:
    return

  if ctx.gpu.blurPipeline != vkNullPipeline:
    vkDestroyPipeline(ctx.gpu.device, ctx.gpu.blurPipeline, nil)
    ctx.gpu.blurPipeline = vkNullPipeline
  if ctx.gpu.blurPipelineLayout != vkNullPipelineLayout:
    vkDestroyPipelineLayout(ctx.gpu.device, ctx.gpu.blurPipelineLayout, nil)
    ctx.gpu.blurPipelineLayout = vkNullPipelineLayout
  if ctx.gpu.blurRenderPass != vkNullRenderPass:
    vkDestroyRenderPass(ctx.gpu.device, ctx.gpu.blurRenderPass, nil)
    ctx.gpu.blurRenderPass = vkNullRenderPass
  ctx.gpu.backdropBlurFramebuffer.reset()
  ctx.gpu.backdropBlurTempFramebuffer.reset()

  var colorAttachment = VkAttachmentDescription(
    flags: 0.VkAttachmentDescriptionFlags,
    format: ctx.gpu.swapchainFormat,
    samples: VK_SAMPLE_COUNT_1_BIT,
    loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    storeOp: VK_ATTACHMENT_STORE_OP_STORE,
    stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    finalLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
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
  let dependencies = [
    VkSubpassDependency(
      srcSubpass: VK_SUBPASS_EXTERNAL,
      dstSubpass: 0,
      srcStageMask: VkPipelineStageFlags{FragmentShaderBit, TransferBit},
      dstStageMask: VkPipelineStageFlags{ColorAttachmentOutputBit},
      srcAccessMask: VkAccessFlags{ShaderReadBit, TransferWriteBit},
      dstAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
      dependencyFlags: 0.VkDependencyFlags,
    ),
    VkSubpassDependency(
      srcSubpass: 0,
      dstSubpass: VK_SUBPASS_EXTERNAL,
      srcStageMask: VkPipelineStageFlags{ColorAttachmentOutputBit},
      dstStageMask: VkPipelineStageFlags{FragmentShaderBit},
      srcAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
      dstAccessMask: VkAccessFlags{ShaderReadBit},
      dependencyFlags: 0.VkDependencyFlags,
    ),
  ]

  let renderPassInfo = newVkRenderPassCreateInfo(
    attachments = [colorAttachment], subpasses = [subpass], dependencies = dependencies
  )
  checkVkResult vkCreateRenderPass(
    ctx.gpu.device, renderPassInfo.addr, nil, ctx.gpu.blurRenderPass.addr
  )

  if ctx.gpu.blurVertShader == vkNullShaderModule:
    let vertInfo = newVkShaderModuleCreateInfo(code = blurVertSpv)
    ctx.gpu.blurVertShader = createShaderModule(ctx.gpu.device, vertInfo)
  if ctx.gpu.blurFragShader == vkNullShaderModule:
    let fragInfo = newVkShaderModuleCreateInfo(code = blurFragSpv)
    ctx.gpu.blurFragShader = createShaderModule(ctx.gpu.device, fragInfo)

  let vertStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.VertexBit,
    module = ctx.gpu.blurVertShader,
    pName = "main",
    pSpecializationInfo = nil,
  )
  let fragStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.FragmentBit,
    module = ctx.gpu.blurFragShader,
    pName = "main",
    pSpecializationInfo = nil,
  )

  let vertexInputInfo = newVkPipelineVertexInputStateCreateInfo(
    vertexBindingDescriptions = [], vertexAttributeDescriptions = []
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
    blendEnable = VkBool32(VkFalse),
    srcColorBlendFactor = VK_BLEND_FACTOR_ONE,
    dstColorBlendFactor = VK_BLEND_FACTOR_ZERO,
    colorBlendOp = VK_BLEND_OP_ADD,
    srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
    dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO,
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
    setLayouts = [ctx.gpu.blurDescriptorSetLayout], pushConstantRanges = []
  )
  ctx.gpu.blurPipelineLayout = createPipelineLayout(ctx.gpu.device, pipelineLayoutInfo)

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
    layout = ctx.gpu.blurPipelineLayout,
    renderPass = ctx.gpu.blurRenderPass,
    subpass = 0,
    basePipelineHandle = 0.VkPipeline,
    basePipelineIndex = -1,
  )
  checkVkResult vkCreateGraphicsPipelines(
    ctx.gpu.device, 0.VkPipelineCache, 1, pipelineInfo.addr, nil,
    ctx.gpu.blurPipeline.addr,
  )

  ctx.recreateBlurFramebuffers()

template vulkanBlurRunSeparable*(ctx, blurRadius, blurRect: untyped) =
  if blurRadius <= 0.5'f32:
    return
  if not ctx.gpu.commandRecording:
    return
  if ctx.gpu.blurRenderPass == vkNullRenderPass or ctx.gpu.blurPipeline == vkNullPipeline or
      ctx.gpu.blurPipelineLayout == vkNullPipelineLayout:
    return
  if ctx.gpu.blurDescriptorSets[0] == vkNullDescriptorSet or
      ctx.gpu.blurDescriptorSets[1] == vkNullDescriptorSet or
      not ctx.gpu.blurUniforms[0].isInitialized() or
      not ctx.gpu.blurUniforms[1].isInitialized():
    return
  if not ctx.gpu.backdropView.isInitialized() or
      not ctx.gpu.backdropBlurTempView.isInitialized() or
      not ctx.gpu.backdropBlurFramebuffer.isInitialized() or
      not ctx.gpu.backdropBlurTempFramebuffer.isInitialized():
    return
  if ctx.gpu.backdropWidth <= 0 or ctx.gpu.backdropHeight <= 0:
    return

  let
    w = max(1.0'f32, ctx.gpu.backdropWidth.float32)
    h = max(1.0'f32, ctx.gpu.backdropHeight.float32)
    viewport =
      newVkViewport(x = 0, y = 0, width = w, height = h, minDepth = 0, maxDepth = 1)

  var drawRect = blurRect
  if drawRect.offset.x < 0:
    let shift = -drawRect.offset.x
    drawRect.offset.x = 0
    if shift.int32 >= drawRect.extent.width.int32:
      return
    drawRect.extent.width = (drawRect.extent.width.int32 - shift).uint32
  if drawRect.offset.y < 0:
    let shift = -drawRect.offset.y
    drawRect.offset.y = 0
    if shift.int32 >= drawRect.extent.height.int32:
      return
    drawRect.extent.height = (drawRect.extent.height.int32 - shift).uint32

  let maxRight = ctx.gpu.backdropWidth
  let maxBottom = ctx.gpu.backdropHeight
  let rectRight = drawRect.offset.x + drawRect.extent.width.int32
  let rectBottom = drawRect.offset.y + drawRect.extent.height.int32
  if rectRight <= 0 or rectBottom <= 0 or drawRect.offset.x >= maxRight or
      drawRect.offset.y >= maxBottom:
    return
  if rectRight > maxRight:
    drawRect.extent.width = (maxRight - drawRect.offset.x).uint32
  if rectBottom > maxBottom:
    drawRect.extent.height = (maxBottom - drawRect.offset.y).uint32
  if drawRect.extent.width == 0 or drawRect.extent.height == 0:
    return

  let scissor = drawRect

  let tempOldLayout =
    if ctx.gpu.backdropBlurTempLayoutReady:
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    else:
      VK_IMAGE_LAYOUT_UNDEFINED
  let tempSrcAccess =
    if ctx.gpu.backdropBlurTempLayoutReady:
      VkAccessFlags{ShaderReadBit}
    else:
      0.VkAccessFlags
  let tempSrcStage =
    if ctx.gpu.backdropBlurTempLayoutReady:
      VkPipelineStageFlags{FragmentShaderBit}
    else:
      VkPipelineStageFlags{TopOfPipeBit}

  var tempToColor = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: tempSrcAccess,
    dstAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
    oldLayout: tempOldLayout,
    newLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.gpu.backdropBlurTempImage[].image,
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
    tempSrcStage,
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    tempToColor.addr,
  )

  ctx.writeBlurUniforms(
    uniformMemory = ctx.gpu.blurUniforms[0][].memory,
    texelStep = vec2(1.0'f32 / w, 0.0'f32),
    blurRadius = blurRadius,
  )

  let tempPassInfo = VkRenderPassBeginInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: nil,
    renderPass: ctx.gpu.blurRenderPass,
    framebuffer: ctx.gpu.backdropBlurTempFramebuffer[].framebuffer,
    renderArea: drawRect,
    clearValueCount: 0,
    pClearValues: nil,
  )
  vkCmdBeginRenderPass(
    ctx.gpu.commandBuffer, tempPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE
  )
  vkCmdBindPipeline(
    ctx.gpu.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.gpu.blurPipeline
  )
  vkCmdSetViewport(ctx.gpu.commandBuffer, 0, 1, viewport.addr)
  vkCmdSetScissor(ctx.gpu.commandBuffer, 0, 1, scissor.addr)
  vkCmdBindDescriptorSets(
    ctx.gpu.commandBuffer,
    VK_PIPELINE_BIND_POINT_GRAPHICS,
    ctx.gpu.blurPipelineLayout,
    0,
    1,
    ctx.gpu.blurDescriptorSets[0].addr,
    0,
    nil,
  )
  vkCmdDraw(ctx.gpu.commandBuffer, 3, 1, 0, 0)
  vkCmdEndRenderPass(ctx.gpu.commandBuffer)
  ctx.gpu.backdropBlurTempLayoutReady = true

  var backdropToColor = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{ShaderReadBit},
    dstAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
    oldLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    newLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.gpu.backdropImage[].image,
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
    VkPipelineStageFlags{FragmentShaderBit},
    VkPipelineStageFlags{ColorAttachmentOutputBit},
    0.VkDependencyFlags,
    0,
    nil,
    0,
    nil,
    1,
    backdropToColor.addr,
  )

  ctx.writeBlurUniforms(
    uniformMemory = ctx.gpu.blurUniforms[1][].memory,
    texelStep = vec2(0.0'f32, 1.0'f32 / h),
    blurRadius = blurRadius,
  )

  let backdropPassInfo = VkRenderPassBeginInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: nil,
    renderPass: ctx.gpu.blurRenderPass,
    framebuffer: ctx.gpu.backdropBlurFramebuffer[].framebuffer,
    renderArea: drawRect,
    clearValueCount: 0,
    pClearValues: nil,
  )
  vkCmdBeginRenderPass(
    ctx.gpu.commandBuffer, backdropPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE
  )
  vkCmdBindPipeline(
    ctx.gpu.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.gpu.blurPipeline
  )
  vkCmdSetViewport(ctx.gpu.commandBuffer, 0, 1, viewport.addr)
  vkCmdSetScissor(ctx.gpu.commandBuffer, 0, 1, scissor.addr)
  vkCmdBindDescriptorSets(
    ctx.gpu.commandBuffer,
    VK_PIPELINE_BIND_POINT_GRAPHICS,
    ctx.gpu.blurPipelineLayout,
    0,
    1,
    ctx.gpu.blurDescriptorSets[1].addr,
    0,
    nil,
  )
  vkCmdDraw(ctx.gpu.commandBuffer, 3, 1, 0, 0)
  vkCmdEndRenderPass(ctx.gpu.commandBuffer)
  ctx.gpu.backdropLayoutReady = true
