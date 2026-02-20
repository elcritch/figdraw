## Vulkan backdrop blur helpers shared by `vulkan_context.nim`.
##
## These are templates so they expand inside `vulkan_context` and can access
## that module's private context fields and Vulkan helper constants.

template vulkanBlurRecreateFramebuffers*(ctx: untyped) =
  if ctx.backdropBlurFramebuffer != vkNullFramebuffer:
    vkDestroyFramebuffer(ctx.device, ctx.backdropBlurFramebuffer, nil)
    ctx.backdropBlurFramebuffer = vkNullFramebuffer
  if ctx.backdropBlurTempFramebuffer != vkNullFramebuffer:
    vkDestroyFramebuffer(ctx.device, ctx.backdropBlurTempFramebuffer, nil)
    ctx.backdropBlurTempFramebuffer = vkNullFramebuffer
  if ctx.blurRenderPass == vkNullRenderPass:
    return
  if ctx.backdropView == vkNullImageView or ctx.backdropBlurTempView == vkNullImageView:
    return
  if ctx.backdropWidth <= 0 or ctx.backdropHeight <= 0:
    return

  let tempInfo = newVkFramebufferCreateInfo(
    renderPass = ctx.blurRenderPass,
    attachments = [ctx.backdropBlurTempView],
    width = ctx.backdropWidth.uint32,
    height = ctx.backdropHeight.uint32,
    layers = 1,
  )
  checkVkResult vkCreateFramebuffer(
    ctx.device, tempInfo.addr, nil, ctx.backdropBlurTempFramebuffer.addr
  )

  let backdropInfo = newVkFramebufferCreateInfo(
    renderPass = ctx.blurRenderPass,
    attachments = [ctx.backdropView],
    width = ctx.backdropWidth.uint32,
    height = ctx.backdropHeight.uint32,
    layers = 1,
  )
  checkVkResult vkCreateFramebuffer(
    ctx.device, backdropInfo.addr, nil, ctx.backdropBlurFramebuffer.addr
  )

template vulkanBlurUpdateDescriptorSet*(
    ctx, descriptorSet, srcView, uniformBuffer: untyped
) =
  if srcView == vkNullImageView or descriptorSet == vkNullDescriptorSet or
      uniformBuffer == vkNullBuffer:
    return

  var srcInfo = newVkDescriptorImageInfo(
    sampler = ctx.atlasSampler,
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
  updateDescriptorSets(ctx.device, writes, [])

template vulkanBlurUpdateDescriptorSets*(ctx: untyped) =
  if ctx.blurDescriptorSets[0] == vkNullDescriptorSet or
      ctx.blurDescriptorSets[1] == vkNullDescriptorSet:
    return
  if ctx.blurUniformBuffers[0] == vkNullBuffer or
      ctx.blurUniformBuffers[1] == vkNullBuffer:
    return
  let src0 =
    (if ctx.backdropView != vkNullImageView: ctx.backdropView else: ctx.atlasView)
  let src1 =
    if ctx.backdropBlurTempView != vkNullImageView: ctx.backdropBlurTempView else: src0
  ctx.updateBlurDescriptorSet(
    descriptorSet = ctx.blurDescriptorSets[0],
    srcView = src0,
    uniformBuffer = ctx.blurUniformBuffers[0],
  )
  ctx.updateBlurDescriptorSet(
    descriptorSet = ctx.blurDescriptorSets[1],
    srcView = src1,
    uniformBuffer = ctx.blurUniformBuffers[1],
  )

template vulkanBlurWriteUniforms*(ctx, uniformMemory, texelStep, blurRadius: untyped) =
  if uniformMemory == vkNullMemory:
    return
  var blurU = BlurUniforms(texelStep: texelStep, blurRadius: blurRadius, pad0: 0.0'f32)
  let mapped = cast[ptr uint8](mapMemory(
    ctx.device,
    uniformMemory,
    0.VkDeviceSize,
    VkDeviceSize(sizeof(BlurUniforms)),
    0.VkMemoryMapFlags,
  ))
  copyMem(mapped, blurU.addr, sizeof(BlurUniforms))
  unmapMemory(ctx.device, uniformMemory)

template vulkanBlurCreatePipeline*(ctx: untyped) =
  if ctx.swapchainFormat == VK_FORMAT_UNDEFINED:
    return

  if ctx.blurPipeline != vkNullPipeline:
    vkDestroyPipeline(ctx.device, ctx.blurPipeline, nil)
    ctx.blurPipeline = vkNullPipeline
  if ctx.blurPipelineLayout != vkNullPipelineLayout:
    vkDestroyPipelineLayout(ctx.device, ctx.blurPipelineLayout, nil)
    ctx.blurPipelineLayout = vkNullPipelineLayout
  if ctx.blurRenderPass != vkNullRenderPass:
    vkDestroyRenderPass(ctx.device, ctx.blurRenderPass, nil)
    ctx.blurRenderPass = vkNullRenderPass
  if ctx.backdropBlurFramebuffer != vkNullFramebuffer:
    vkDestroyFramebuffer(ctx.device, ctx.backdropBlurFramebuffer, nil)
    ctx.backdropBlurFramebuffer = vkNullFramebuffer
  if ctx.backdropBlurTempFramebuffer != vkNullFramebuffer:
    vkDestroyFramebuffer(ctx.device, ctx.backdropBlurTempFramebuffer, nil)
    ctx.backdropBlurTempFramebuffer = vkNullFramebuffer

  var colorAttachment = VkAttachmentDescription(
    flags: 0.VkAttachmentDescriptionFlags,
    format: ctx.swapchainFormat,
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
    ctx.device, renderPassInfo.addr, nil, ctx.blurRenderPass.addr
  )

  if ctx.blurVertShader == vkNullShaderModule:
    let vertInfo = newVkShaderModuleCreateInfo(code = blurVertSpv)
    ctx.blurVertShader = createShaderModule(ctx.device, vertInfo)
  if ctx.blurFragShader == vkNullShaderModule:
    let fragInfo = newVkShaderModuleCreateInfo(code = blurFragSpv)
    ctx.blurFragShader = createShaderModule(ctx.device, fragInfo)

  let vertStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.VertexBit,
    module = ctx.blurVertShader,
    pName = "main",
    pSpecializationInfo = nil,
  )
  let fragStage = newVkPipelineShaderStageCreateInfo(
    stage = VkShaderStageFlagBits.FragmentBit,
    module = ctx.blurFragShader,
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
    setLayouts = [ctx.blurDescriptorSetLayout], pushConstantRanges = []
  )
  ctx.blurPipelineLayout = createPipelineLayout(ctx.device, pipelineLayoutInfo)

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
    layout = ctx.blurPipelineLayout,
    renderPass = ctx.blurRenderPass,
    subpass = 0,
    basePipelineHandle = 0.VkPipeline,
    basePipelineIndex = -1,
  )
  checkVkResult vkCreateGraphicsPipelines(
    ctx.device, 0.VkPipelineCache, 1, pipelineInfo.addr, nil, ctx.blurPipeline.addr
  )

  ctx.recreateBlurFramebuffers()

template vulkanBlurRunSeparable*(ctx, blurRadius: untyped) =
  if blurRadius <= 0.5'f32:
    return
  if not ctx.commandRecording:
    return
  if ctx.blurRenderPass == vkNullRenderPass or ctx.blurPipeline == vkNullPipeline or
      ctx.blurPipelineLayout == vkNullPipelineLayout:
    return
  if ctx.blurDescriptorSets[0] == vkNullDescriptorSet or
      ctx.blurDescriptorSets[1] == vkNullDescriptorSet or
      ctx.blurUniformBuffers[0] == vkNullBuffer or
      ctx.blurUniformBuffers[1] == vkNullBuffer or
      ctx.blurUniformMemories[0] == vkNullMemory or
      ctx.blurUniformMemories[1] == vkNullMemory:
    return
  if ctx.backdropView == vkNullImageView or ctx.backdropBlurTempView == vkNullImageView or
      ctx.backdropBlurFramebuffer == vkNullFramebuffer or
      ctx.backdropBlurTempFramebuffer == vkNullFramebuffer:
    return
  if ctx.backdropWidth <= 0 or ctx.backdropHeight <= 0:
    return

  let
    w = max(1.0'f32, ctx.backdropWidth.float32)
    h = max(1.0'f32, ctx.backdropHeight.float32)
    extent = newVkExtent2D(
      width = ctx.backdropWidth.uint32, height = ctx.backdropHeight.uint32
    )
    viewport =
      newVkViewport(x = 0, y = 0, width = w, height = h, minDepth = 0, maxDepth = 1)
  var scissor = newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = extent)

  let tempOldLayout =
    if ctx.backdropBlurTempLayoutReady:
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    else:
      VK_IMAGE_LAYOUT_UNDEFINED
  let tempSrcAccess =
    if ctx.backdropBlurTempLayoutReady:
      VkAccessFlags{ShaderReadBit}
    else:
      0.VkAccessFlags
  let tempSrcStage =
    if ctx.backdropBlurTempLayoutReady:
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
    image: ctx.backdropBlurTempImage,
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
    uniformMemory = ctx.blurUniformMemories[0],
    texelStep = vec2(1.0'f32 / w, 0.0'f32),
    blurRadius = blurRadius,
  )

  let tempPassInfo = VkRenderPassBeginInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: nil,
    renderPass: ctx.blurRenderPass,
    framebuffer: ctx.backdropBlurTempFramebuffer,
    renderArea: newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = extent),
    clearValueCount: 0,
    pClearValues: nil,
  )
  vkCmdBeginRenderPass(ctx.commandBuffer, tempPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE)
  vkCmdBindPipeline(
    ctx.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.blurPipeline
  )
  vkCmdSetViewport(ctx.commandBuffer, 0, 1, viewport.addr)
  vkCmdSetScissor(ctx.commandBuffer, 0, 1, scissor.addr)
  vkCmdBindDescriptorSets(
    ctx.commandBuffer,
    VK_PIPELINE_BIND_POINT_GRAPHICS,
    ctx.blurPipelineLayout,
    0,
    1,
    ctx.blurDescriptorSets[0].addr,
    0,
    nil,
  )
  vkCmdDraw(ctx.commandBuffer, 3, 1, 0, 0)
  vkCmdEndRenderPass(ctx.commandBuffer)
  ctx.backdropBlurTempLayoutReady = true

  var backdropToColor = VkImageMemoryBarrier(
    sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
    pNext: nil,
    srcAccessMask: VkAccessFlags{ShaderReadBit},
    dstAccessMask: VkAccessFlags{ColorAttachmentWriteBit},
    oldLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    newLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
    image: ctx.backdropImage,
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
    uniformMemory = ctx.blurUniformMemories[1],
    texelStep = vec2(0.0'f32, 1.0'f32 / h),
    blurRadius = blurRadius,
  )

  let backdropPassInfo = VkRenderPassBeginInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext: nil,
    renderPass: ctx.blurRenderPass,
    framebuffer: ctx.backdropBlurFramebuffer,
    renderArea: newVkRect2D(offset = newVkOffset2D(x = 0, y = 0), extent = extent),
    clearValueCount: 0,
    pClearValues: nil,
  )
  vkCmdBeginRenderPass(
    ctx.commandBuffer, backdropPassInfo.addr, VK_SUBPASS_CONTENTS_INLINE
  )
  vkCmdBindPipeline(
    ctx.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.blurPipeline
  )
  vkCmdSetViewport(ctx.commandBuffer, 0, 1, viewport.addr)
  vkCmdSetScissor(ctx.commandBuffer, 0, 1, scissor.addr)
  vkCmdBindDescriptorSets(
    ctx.commandBuffer,
    VK_PIPELINE_BIND_POINT_GRAPHICS,
    ctx.blurPipelineLayout,
    0,
    1,
    ctx.blurDescriptorSets[1].addr,
    0,
    nil,
  )
  vkCmdDraw(ctx.commandBuffer, 3, 1, 0, 0)
  vkCmdEndRenderPass(ctx.commandBuffer)
  ctx.backdropLayoutReady = true
