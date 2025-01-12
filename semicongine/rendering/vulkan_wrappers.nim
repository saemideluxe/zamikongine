import std/strformat
import std/strutils
import std/typetraits

import ../core

proc getBestPhysicalDevice*(instance: VkInstance): VkPhysicalDevice =
  var nDevices: uint32
  checkVkResult vkEnumeratePhysicalDevices(instance, addr(nDevices), nil)
  var devices = newSeq[VkPhysicalDevice](nDevices)
  checkVkResult vkEnumeratePhysicalDevices(instance, addr(nDevices), devices.ToCPointer)

  var score = 0'u32
  for pDevice in devices:
    var props: VkPhysicalDeviceProperties
    # CANNOT use svkGetPhysicalDeviceProperties (not initialized yet)
    vkGetPhysicalDeviceProperties(pDevice, addr(props))
    if props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU and
        props.limits.maxImageDimension2D > score:
      score = props.limits.maxImageDimension2D
      result = pDevice

  if score == 0:
    for pDevice in devices:
      var props: VkPhysicalDeviceProperties
      # CANNOT use svkGetPhysicalDeviceProperties (not initialized yet)
      vkGetPhysicalDeviceProperties(pDevice, addr(props))
      if props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU and
          props.limits.maxImageDimension2D > score:
        score = props.limits.maxImageDimension2D
        result = pDevice

  assert score > 0, "Unable to find integrated or discrete GPU"

proc svkGetPhysicalDeviceSurfaceSupportKHR*(
    pDevice: VkPhysicalDevice, surface: VkSurfaceKHR, queueFamily: uint32
): bool =
  var presentation = VkBool32(false)
  checkVkResult vkGetPhysicalDeviceSurfaceSupportKHR(
    pDevice, queueFamily, surface, addr(presentation)
  )
  return bool(presentation)

proc getQueueFamily*(
    pDevice: VkPhysicalDevice, surface: VkSurfaceKHR, qType: VkQueueFlagBits
): uint32 =
  var nQueuefamilies: uint32
  vkGetPhysicalDeviceQueueFamilyProperties(pDevice, addr nQueuefamilies, nil)
  var queuFamilies = newSeq[VkQueueFamilyProperties](nQueuefamilies)
  vkGetPhysicalDeviceQueueFamilyProperties(
    pDevice, addr nQueuefamilies, queuFamilies.ToCPointer
  )
  for i in 0'u32 ..< nQueuefamilies:
    if qType in toEnums(queuFamilies[i].queueFlags):
      # for graphics queues we always also want prsentation, they seem never to be separated in practice
      if pDevice.svkGetPhysicalDeviceSurfaceSupportKHR(surface, i) or
          qType != VK_QUEUE_GRAPHICS_BIT:
        return i
  assert false, &"Queue of type {qType} not found"

proc svkGetDeviceQueue*(
    device: VkDevice, queueFamilyIndex: uint32, qType: VkQueueFlagBits
): VkQueue =
  vkGetDeviceQueue(device, queueFamilyIndex, 0, addr(result))

func size(format: VkFormat): uint64 =
  const formatSize = [VK_FORMAT_B8G8R8A8_SRGB.int: 4'u64]
  return formatSize[format.int]

proc svkGetPhysicalDeviceSurfacePresentModesKHR*(): seq[VkPresentModeKHR] =
  var n_modes: uint32
  checkVkResult vkGetPhysicalDeviceSurfacePresentModesKHR(
    engine().vulkan.physicalDevice, engine().vulkan.surface, addr(n_modes), nil
  )
  result = newSeq[VkPresentModeKHR](n_modes)
  checkVkResult vkGetPhysicalDeviceSurfacePresentModesKHR(
    engine().vulkan.physicalDevice,
    engine().vulkan.surface,
    addr(n_modes),
    result.ToCPointer,
  )

proc hasValidationLayer*(): bool =
  var n_layers: uint32
  checkVkResult vkEnumerateInstanceLayerProperties(addr(n_layers), nil)
  if n_layers > 0:
    var layers = newSeq[VkLayerProperties](n_layers)
    checkVkResult vkEnumerateInstanceLayerProperties(addr(n_layers), layers.ToCPointer)
    for layer in layers:
      if layer.layerName.CleanString == "VK_LAYER_KHRONOS_validation":
        return true
  return false

proc svkGetPhysicalDeviceProperties*(): VkPhysicalDeviceProperties =
  vkGetPhysicalDeviceProperties(engine().vulkan.physicalDevice, addr(result))

proc svkCreateBuffer*(size: uint64, usage: openArray[VkBufferUsageFlagBits]): VkBuffer =
  var createInfo = VkBufferCreateInfo(
    sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    flags: VkBufferCreateFlags(0),
    size: size,
    usage: usage.toBits,
    sharingMode: VK_SHARING_MODE_EXCLUSIVE,
  )
  checkVkResult vkCreateBuffer(
    device = engine().vulkan.device,
    pCreateInfo = addr(createInfo),
    pAllocator = nil,
    pBuffer = addr(result),
  )

proc svkAllocateMemory*(size: uint64, typeIndex: uint32): VkDeviceMemory =
  var memoryAllocationInfo = VkMemoryAllocateInfo(
    sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    allocationSize: size,
    memoryTypeIndex: typeIndex,
  )
  checkVkResult vkAllocateMemory(
    engine().vulkan.device, addr(memoryAllocationInfo), nil, addr(result)
  )

proc svkCreate2DImage*(
    width, height: uint32,
    format: VkFormat,
    usage: openArray[VkImageUsageFlagBits],
    samples = VK_SAMPLE_COUNT_1_BIT,
    nLayers = 1'u32,
): VkImage =
  var imageProps: VkImageFormatProperties
  checkVkResult vkGetPhysicalDeviceImageFormatProperties(
    engine().vulkan.physicalDevice,
    format,
    VK_IMAGE_TYPE_2D,
    VK_IMAGE_TILING_OPTIMAL,
    usage.toBits,
    VkImageCreateFlags(0),
    addr(imageProps),
  )

  var imageInfo = VkImageCreateInfo(
    sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
    imageType: VK_IMAGE_TYPE_2D,
    extent: VkExtent3D(width: width, height: height, depth: 1),
    mipLevels: min(1'u32, imageProps.maxMipLevels),
    arrayLayers: nLayers,
    format: format,
    tiling: VK_IMAGE_TILING_OPTIMAL,
    initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
    usage: usage.toBits,
    sharingMode: VK_SHARING_MODE_EXCLUSIVE,
    samples: samples,
  )
  checkVkResult vkCreateImage(engine().vulkan.device, addr imageInfo, nil, addr(result))

proc svkCreate2DImageView*(
    image: VkImage,
    format: VkFormat,
    aspect = VK_IMAGE_ASPECT_COLOR_BIT,
    nLayers = 1'u32,
    isArray = false,
): VkImageView =
  var createInfo = VkImageViewCreateInfo(
    sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    image: image,
    viewType: if isArray: VK_IMAGE_VIEW_TYPE_2D_ARRAY else: VK_IMAGE_VIEW_TYPE_2D,
    format: format,
    components: VkComponentMapping(
      r: VK_COMPONENT_SWIZZLE_IDENTITY,
      g: VK_COMPONENT_SWIZZLE_IDENTITY,
      b: VK_COMPONENT_SWIZZLE_IDENTITY,
      a: VK_COMPONENT_SWIZZLE_IDENTITY,
    ),
    subresourceRange: VkImageSubresourceRange(
      aspectMask: toBits [aspect],
      baseMipLevel: 0,
      levelCount: 1,
      baseArrayLayer: 0,
      layerCount: nLayers,
    ),
  )
  checkVkResult vkCreateImageView(
    engine().vulkan.device, addr(createInfo), nil, addr(result)
  )

proc svkCreateFramebuffer*(
    renderpass: VkRenderPass, width, height: uint32, attachments: openArray[VkImageView]
): VkFramebuffer =
  var framebufferInfo = VkFramebufferCreateInfo(
    sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
    renderPass: renderpass,
    attachmentCount: attachments.len.uint32,
    pAttachments: attachments.ToCPointer,
    width: width,
    height: height,
    layers: 1,
  )
  checkVkResult vkCreateFramebuffer(
    engine().vulkan.device, addr(framebufferInfo), nil, addr(result)
  )

proc svkGetBufferMemoryRequirements*(
    buffer: VkBuffer
): tuple[size: uint64, alignment: uint64, memoryTypes: seq[uint32]] =
  var reqs: VkMemoryRequirements
  vkGetBufferMemoryRequirements(engine().vulkan.device, buffer, addr(reqs))
  result.size = reqs.size
  result.alignment = reqs.alignment
  for i in 0'u32 ..< VK_MAX_MEMORY_TYPES:
    if ((1'u32 shl i) and reqs.memoryTypeBits) > 0:
      result.memoryTypes.add i

proc svkGetImageMemoryRequirements*(
    image: VkImage
): tuple[size: uint64, alignment: uint64, memoryTypes: seq[uint32]] =
  var reqs: VkMemoryRequirements
  vkGetImageMemoryRequirements(engine().vulkan.device, image, addr(reqs))
  result.size = reqs.size
  result.alignment = reqs.alignment
  for i in 0'u32 ..< VK_MAX_MEMORY_TYPES:
    if ((1'u32 shl i) and reqs.memoryTypeBits) > 0:
      result.memoryTypes.add i

proc svkCreateFence*(signaled = false): VkFence =
  var fenceInfo = VkFenceCreateInfo(
    sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    flags:
      if signaled:
        toBits [VK_FENCE_CREATE_SIGNALED_BIT]
      else:
        VkFenceCreateFlags(0),
  )
  checkVkResult vkCreateFence(
    engine().vulkan.device, addr(fenceInfo), nil, addr(result)
  )

proc svkCreateSemaphore*(): VkSemaphore =
  var semaphoreInfo =
    VkSemaphoreCreateInfo(sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO)
  checkVkResult vkCreateSemaphore(
    engine().vulkan.device, addr(semaphoreInfo), nil, addr(result)
  )

proc await*(fence: VkFence, timeout = high(uint64)): bool =
  let waitResult =
    vkWaitForFences(engine().vulkan.device, 1, addr(fence), false, timeout)
  if waitResult == VK_TIMEOUT:
    return false
  checkVkResult waitResult
  return true

proc svkResetFences*(fence: VkFence) =
  checkVkResult vkResetFences(engine().vulkan.device, 1, addr(fence))

proc svkCmdBindDescriptorSets*(
    commandBuffer: VkCommandBuffer,
    descriptorSets: openArray[VkDescriptorSet],
    layout: VkPipelineLayout,
) =
  vkCmdBindDescriptorSets(
    commandBuffer = commandBuffer,
    pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
    layout = layout,
    firstSet = 0,
    descriptorSetCount = descriptorSets.len.uint32,
    pDescriptorSets = descriptorSets.ToCPointer,
    dynamicOffsetCount = 0,
    pDynamicOffsets = nil,
  )

proc svkCmdBindDescriptorSet*(
    commandBuffer: VkCommandBuffer,
    descriptorSet: VkDescriptorSet,
    index: DescriptorSetIndex,
    layout: VkPipelineLayout,
) =
  vkCmdBindDescriptorSets(
    commandBuffer = commandBuffer,
    pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
    layout = layout,
    firstSet = index.uint32,
    descriptorSetCount = 1,
    pDescriptorSets = addr(descriptorSet),
    dynamicOffsetCount = 0,
    pDynamicOffsets = nil,
  )

proc svkCreateRenderPass*(
    attachments: openArray[VkAttachmentDescription],
    colorAttachments: openArray[VkAttachmentReference],
    depthAttachments: openArray[VkAttachmentReference],
    resolveAttachments: openArray[VkAttachmentReference],
    dependencies: openArray[VkSubpassDependency],
): VkRenderPass =
  assert colorAttachments.len == resolveAttachments.len or resolveAttachments.len == 0
  var subpass = VkSubpassDescription(
    flags: VkSubpassDescriptionFlags(0),
    pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
    inputAttachmentCount: 0,
    pInputAttachments: nil,
    colorAttachmentCount: colorAttachments.len.uint32,
    pColorAttachments: colorAttachments.ToCPointer,
    pResolveAttachments: resolveAttachments.ToCPointer,
    pDepthStencilAttachment: depthAttachments.ToCPointer,
    preserveAttachmentCount: 0,
    pPreserveAttachments: nil,
  )
  var createInfo = VkRenderPassCreateInfo(
    sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    attachmentCount: uint32(attachments.len),
    pAttachments: attachments.ToCPointer,
    subpassCount: 1,
    pSubpasses: addr(subpass),
    dependencyCount: uint32(dependencies.len),
    pDependencies: dependencies.ToCPointer,
  )
  checkVkResult vkCreateRenderPass(
    engine().vulkan.device, addr(createInfo), nil, addr(result)
  )

proc bestMemory*(mappable: bool, filter: seq[uint32] = @[]): uint32 =
  var physicalProperties: VkPhysicalDeviceMemoryProperties
  vkGetPhysicalDeviceMemoryProperties(
    engine().vulkan.physicalDevice, addr(physicalProperties)
  )

  var maxScore: float = -1
  var maxIndex: uint32 = 0
  for index in 0'u32 ..< physicalProperties.memoryTypeCount:
    if filter.len == 0 or index in filter:
      let flags = toEnums(physicalProperties.memoryTypes[index].propertyFlags)
      if not mappable or VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT in flags:
        var score: float = 0
        if VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT in flags:
          score += 1_000_000
        if VK_MEMORY_PROPERTY_HOST_CACHED_BIT in flags:
          score += 1_000
        score +=
          float(
            physicalProperties.memoryHeaps[
              physicalProperties.memoryTypes[index].heapIndex
            ].size
          ) / 1_000_000_000
        if score > maxScore:
          maxScore = score
          maxIndex = index
  assert maxScore > 0,
    &"Unable to find memory type (mappable: {mappable}, filter: {filter})"
  return maxIndex

template withSingleUseCommandBuffer*(cmd, body: untyped): untyped =
  block:
    var
      commandBufferPool: VkCommandPool
      createInfo = VkCommandPoolCreateInfo(
        sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        flags: VkCommandPoolCreateFlags(0),
        queueFamilyIndex: engine().vulkan.graphicsQueueFamily,
      )
    checkVkResult vkCreateCommandPool(
      engine().vulkan.device, addr createInfo, nil, addr(commandBufferPool)
    )
    var
      `cmd` {.inject.}: VkCommandBuffer
      allocInfo = VkCommandBufferAllocateInfo(
        sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool: commandBufferPool,
        level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        commandBufferCount: 1,
      )
    checkVkResult engine().vulkan.device.vkAllocateCommandBuffers(
      addr allocInfo, addr(`cmd`)
    )
    var beginInfo = VkCommandBufferBeginInfo(
      sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      flags: VkCommandBufferUsageFlags(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT),
    )
    checkVkResult `cmd`.vkBeginCommandBuffer(addr beginInfo)

    body

    checkVkResult `cmd`.vkEndCommandBuffer()
    var submitInfo = VkSubmitInfo(
      sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
      commandBufferCount: 1,
      pCommandBuffers: addr(`cmd`),
    )

    var fence = svkCreateFence()
    checkVkResult vkQueueSubmit(
      engine().vulkan.graphicsQueue, 1, addr(submitInfo), fence
    )
    discard fence.await()
    vkDestroyFence(engine().vulkan.device, fence, nil)
    vkDestroyCommandPool(engine().vulkan.device, commandBufferPool, nil)

template withStagingBuffer*[T: (VkBuffer, uint64) | (VkImage, uint32, uint32, uint32)](
    target: T, bufferSize: uint64, dataPointer, body: untyped
): untyped =
  var `dataPointer` {.inject.}: pointer
  let stagingBuffer = svkCreateBuffer(bufferSize, [VK_BUFFER_USAGE_TRANSFER_SRC_BIT])
  let memoryRequirements = svkGetBufferMemoryRequirements(stagingBuffer)
  let memoryType = bestMemory(mappable = true, filter = memoryRequirements.memoryTypes)
  let stagingMemory = svkAllocateMemory(memoryRequirements.size, memoryType)
  checkVkResult vkMapMemory(
    device = engine().vulkan.device,
    memory = stagingMemory,
    offset = 0'u64,
    size = VK_WHOLE_SIZE,
    flags = VkMemoryMapFlags(0),
    ppData = addr(`dataPointer`),
  )
  checkVkResult vkBindBufferMemory(
    engine().vulkan.device, stagingBuffer, stagingMemory, 0
  )

  block:
    # usually: write data to dataPointer in body
    body

  var stagingRange = VkMappedMemoryRange(
    sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
    memory: stagingMemory,
    size: VK_WHOLE_SIZE,
  )
  checkVkResult vkFlushMappedMemoryRanges(engine().vulkan.device, 1, addr(stagingRange))

  withSingleUseCommandBuffer(commandBuffer):
    when T is (VkBuffer, uint64):
      # first make sure memory has been made available with a memory barrier
      # we are just waiting for the vertex input stage, but I think that is fine for most buffer copies (for now at least)
      let memoryBarrier = VkMemoryBarrier(sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER)
      vkCmdPipelineBarrier(
        commandBuffer = commandBuffer,
        srcStageMask = toBits [VK_PIPELINE_STAGE_VERTEX_INPUT_BIT],
        dstStageMask = toBits [VK_PIPELINE_STAGE_TRANSFER_BIT],
        dependencyFlags = VkDependencyFlags(0),
        memoryBarrierCount = 1,
        pMemoryBarriers = addr(memoryBarrier),
        bufferMemoryBarrierCount = 0,
        pBufferMemoryBarriers = nil,
        imageMemoryBarrierCount = 0,
        pImageMemoryBarriers = nil,
      )
      # now copy stuff
      let copyRegion =
        VkBufferCopy(size: bufferSize, dstOffset: target[1], srcOffset: 0)
      vkCmdCopyBuffer(
        commandBuffer = commandBuffer,
        srcBuffer = stagingBuffer,
        dstBuffer = target[0],
        regionCount = 1,
        pRegions = addr(copyRegion),
      )
    elif T is (VkImage, uint32, uint32, uint32):
      let region = VkBufferImageCopy(
        bufferOffset: 0,
        bufferRowLength: 0,
        bufferImageHeight: 0,
        imageSubresource: VkImageSubresourceLayers(
          aspectMask: toBits [VK_IMAGE_ASPECT_COLOR_BIT],
          mipLevel: 0,
          baseArrayLayer: 0,
          layerCount: target[3],
        ),
        imageOffset: VkOffset3D(x: 0, y: 0, z: 0),
        imageExtent: VkExtent3D(width: target[1], height: target[2], depth: 1),
      )
      vkCmdCopyBufferToImage(
        commandBuffer = commandBuffer,
        srcBuffer = stagingBuffer,
        dstImage = target[0],
        dstImageLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        regionCount = 1,
        pRegions = addr(region),
      )

  vkDestroyBuffer(engine().vulkan.device, stagingBuffer, nil)
  vkFreeMemory(engine().vulkan.device, stagingMemory, nil)

func getDescriptorType*[T](): VkDescriptorType {.compileTIme.} =
  when T is ImageObject:
    VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
  elif T is GPUValue:
    when getBufferType(default(T)) in [UniformBuffer, UniformBufferMapped]:
      VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
    elif getBufferType(default(T)) in [StorageBuffer, StorageBufferMapped]:
      VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
    else:
      {.error: "Unsupported descriptor type: " & $T.}
  elif T is array:
    when elementType(default(T)) is ImageObject:
      VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
    elif elementType(default(T)) is GPUValue:
      when getBufferType(default(elementType(default(T)))) in
          [UniformBuffer, UniformBufferMapped]:
        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
      elif getBufferType(default(elementType(default(T)))) in
          [StorageBuffer, StorageBufferMapped]:
        VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
      else:
        {.error: "Unsupported descriptor type: " & $T.}
    else:
      {.error: "Unsupported descriptor type: " & $T.}
  else:
    {.error: "Unsupported descriptor type: " & $T.}

func getDescriptorCount*[T](): uint32 {.compileTIme.} =
  when T is array:
    len(T)
  else:
    1

func getBindingNumber*[T](field: static string): uint32 {.compileTime.} =
  var c = 0'u32
  var found = false
  for name, value in fieldPairs(default(T)):
    when name == field:
      result = c
      found = true
    else:
      inc c
  assert found, "Field '" & field & "' of descriptor '" & $T & "' not found"

proc currentFiF*(): int =
  assert engine().vulkan.swapchain != nil, "Swapchain has not been initialized yet"
  engine().vulkan.swapchain.currentFiF
