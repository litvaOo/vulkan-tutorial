package main

import "core:strings"
import "base:runtime"
import "core:slice"
import vk "vendor:vulkan"
import glfw "vendor:glfw"
import glfw_bindings "vendor:glfw/bindings"


device_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

create_vk_instance :: proc(ctx: ^Context) {
  app_info: vk.ApplicationInfo

  {
    app_info.sType = vk.StructureType.APPLICATION_INFO
    app_info.pApplicationName = "Hello Triangle"
    app_info.applicationVersion = vk.MAKE_VERSION(1, 0, 0);
    app_info.pEngineName = "NoEngine"
    app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = vk.API_VERSION_1_4
  }

  create_info: vk.InstanceCreateInfo
  glfw_extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions())
  when ODIN_OS == .Darwin {
		create_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
		append(&glfw_extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}
  {
    create_info.sType = vk.StructureType.INSTANCE_CREATE_INFO
    create_info.pApplicationInfo = &app_info
    create_info.enabledExtensionCount = u32(len(glfw_extensions))
    create_info.ppEnabledExtensionNames = raw_data(glfw_extensions)
    create_info.enabledLayerCount = 0
  }

  vk_result := vk.CreateInstance(&create_info, nil, &ctx.instance)
  if vk_result != vk.Result.SUCCESS {
    panic("Failed creation")
  }
}

check_validation_layer_support :: proc (ctx: ^Context) -> bool {
  when ODIN_DEBUG {
    validation_layers : [][256]u8 // uninitialized because no default validation_layers are available
    layer_count : u32
    vk.EnumerateInstanceLayerProperties(&layer_count, nil)

    available_layers := make([^]vk.LayerProperties, layer_count)
    vk.EnumerateInstanceLayerProperties(&layer_count, available_layers)

    for layer in validation_layers {
      layer_found := false

      for i := u32(0); i < layer_count; i += 1 {
        if available_layers[i].layerName == layer {
          layer_found = true
          break
        }
      }
      
      if !layer_found {
        return false
      }
    }
    return true
  }
  return true
}

pick_physical_device :: proc (ctx: ^Context) {
  device_count : u32
  vk.EnumeratePhysicalDevices(ctx.instance, &device_count, nil)
  if device_count == 0 {
    panic("No vulkan devices")
  }
  devices := make([^]vk.PhysicalDevice, device_count)
  vk.EnumeratePhysicalDevices(ctx.instance, &device_count, devices)
  for i := u32(0); i < device_count; i += 1 {
    if (is_device_suitable(ctx, devices[i])) {
      ctx.physical_device = devices[i]
      ctx.msaa_samples = get_max_usable_sample_count(ctx)
      break
    }
  }
  if ctx.physical_device == nil {
    panic("No suitable vulkan device")
  }
}

is_device_suitable :: proc (ctx: ^Context, device: vk.PhysicalDevice) -> bool {
  device_properties : vk.PhysicalDeviceProperties
  device_features : vk.PhysicalDeviceFeatures
  vk.GetPhysicalDeviceProperties(device, &device_properties)
  vk.GetPhysicalDeviceFeatures(device, &device_features)

  find_queue_families(ctx, device) or_return
  check_device_extension_support(ctx, device) or_return

  swap_chain_support := query_swap_chain_support(ctx, device)
  if (swap_chain_support.formats == nil || swap_chain_support.present_modes == nil) do return false
  return true
}

check_device_extension_support :: proc(ctx: ^Context, device: vk.PhysicalDevice) -> bool {
  extension_count := u32(0)
  vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)
  available_extensions := make([]vk.ExtensionProperties, extension_count)
  vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(available_extensions))

  outer_loop: for device_extension in device_extensions {
    for extension in available_extensions {
      bytes := extension.extensionName
      ext_name := strings.clone_from_bytes(bytes[:len(device_extension)])
      if string(device_extension) == ext_name {
        continue outer_loop
      }
    }
    return false
  }
  return true
}

create_logical_device :: proc (ctx: ^Context) {
  queue_family_indices := find_queue_families(ctx, ctx.physical_device) or_else panic("No queue indices")

  unique_queue_families := make(map[u32]int)
  unique_queue_families[queue_family_indices.graphics_family] = 0
  unique_queue_families[queue_family_indices.present_family] = 0

  queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo)

  for queue in unique_queue_families {
    queue_create_info := vk.DeviceQueueCreateInfo{
      sType = .DEVICE_QUEUE_CREATE_INFO,
      queueFamilyIndex = queue_family_indices.graphics_family,
      queueCount = 1,
      pQueuePriorities = raw_data([]f32{1.0}),
    }
    append(&queue_create_infos, queue_create_info)
  }

  device_features := vk.PhysicalDeviceFeatures{
    samplerAnisotropy = true,
    sampleRateShading = true,
  }
  device_create_info := vk.DeviceCreateInfo{
    sType = .DEVICE_CREATE_INFO,
    pQueueCreateInfos = raw_data(queue_create_infos),
    queueCreateInfoCount = u32(len(&queue_create_infos)),
    pEnabledFeatures = &device_features,
    enabledExtensionCount = u32(len(device_extensions)),
    ppEnabledExtensionNames = raw_data(device_extensions),
    enabledLayerCount = 0, 
  }

  vk_handler( vk.CreateDevice(ctx.physical_device, &device_create_info, nil, &ctx.logical_device) )
  vk.GetDeviceQueue(ctx.logical_device, queue_family_indices.graphics_family, 0, &ctx.graphics_queue)
  vk.GetDeviceQueue(ctx.logical_device, queue_family_indices.present_family, 0, &ctx.present_queue)
}

create_surface :: proc (ctx: ^Context) {
  if glfw.CreateWindowSurface(ctx.instance, ctx.window, nil, &ctx.surface) != vk.Result.SUCCESS {
    panic("Failed to create window surface")
  }
}

create_graphics_pipeline :: proc(ctx: ^Context) {
  vert_shader_code := read_file("vert.spv")
  frag_shader_code := read_file("frag.spv")

  vert_shader_module := create_shader_module(ctx, vert_shader_code)
  frag_shader_module := create_shader_module(ctx, frag_shader_code)

  vert_shader_stage_info : vk.PipelineShaderStageCreateInfo
  frag_shader_stage_info : vk.PipelineShaderStageCreateInfo

  { 
    vert_shader_stage_info.sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO
    vert_shader_stage_info.stage = vk.ShaderStageFlags{vk.ShaderStageFlag.VERTEX}
    vert_shader_stage_info.module = vert_shader_module
    vert_shader_stage_info.pName = "main"

    frag_shader_stage_info.sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO
    frag_shader_stage_info.stage = vk.ShaderStageFlags{vk.ShaderStageFlag.FRAGMENT}
    frag_shader_stage_info.module = frag_shader_module
    frag_shader_stage_info.pName = "main"
  }

  shader_stages := []vk.PipelineShaderStageCreateInfo{vert_shader_stage_info, frag_shader_stage_info}

  binding_description := get_binding_description(ctx)
  attribute_descriptions := get_attribute_descriptions(ctx)

  vertex_input_info : vk.PipelineVertexInputStateCreateInfo
  {
    vertex_input_info.sType = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
    vertex_input_info.vertexBindingDescriptionCount = 1
    vertex_input_info.vertexAttributeDescriptionCount = u32(len(attribute_descriptions))
    vertex_input_info.pVertexBindingDescriptions = &binding_description
    vertex_input_info.pVertexAttributeDescriptions = raw_data(attribute_descriptions)
  }

  input_assembly : vk.PipelineInputAssemblyStateCreateInfo
  {
    input_assembly.sType = vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
    input_assembly.topology = vk.PrimitiveTopology.TRIANGLE_LIST
    input_assembly.primitiveRestartEnable = false
  }

  viewport_state: vk.PipelineViewportStateCreateInfo
  { 
    viewport_state.sType = vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO
    viewport_state.viewportCount = 1
    viewport_state.scissorCount = 1
  }

  rasterizer : vk.PipelineRasterizationStateCreateInfo
  {
    rasterizer.sType = vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO
    rasterizer.depthClampEnable = false
    rasterizer.rasterizerDiscardEnable = false
    rasterizer.polygonMode = vk.PolygonMode.FILL
    rasterizer.lineWidth = 1.0
    rasterizer.cullMode = vk.CullModeFlags{vk.CullModeFlag.BACK}
    rasterizer.frontFace = vk.FrontFace.COUNTER_CLOCKWISE
    rasterizer.depthBiasEnable = false
    rasterizer.depthBiasConstantFactor = 0.0
    rasterizer.depthBiasClamp = 0.0
    rasterizer.depthBiasSlopeFactor = 0.0
  }

  multisampling : vk.PipelineMultisampleStateCreateInfo
  {
    multisampling.sType = vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    multisampling.sampleShadingEnable = true
    multisampling.rasterizationSamples = ctx.msaa_samples
    multisampling.minSampleShading = 0.2
    multisampling.pSampleMask = nil
    multisampling.alphaToCoverageEnable = false
    multisampling.alphaToOneEnable = false
  }

  color_blend_attachment : vk.PipelineColorBlendAttachmentState
  {
    color_blend_attachment.colorWriteMask = vk.ColorComponentFlags{
      vk.ColorComponentFlag.R, vk.ColorComponentFlag.G,
      vk.ColorComponentFlag.B, vk.ColorComponentFlag.A }
    color_blend_attachment.blendEnable = false
    color_blend_attachment.srcColorBlendFactor = vk.BlendFactor.ONE
    color_blend_attachment.dstColorBlendFactor = vk.BlendFactor.ZERO
    color_blend_attachment.colorBlendOp = vk.BlendOp.ADD
    color_blend_attachment.srcAlphaBlendFactor = vk.BlendFactor.ONE
    color_blend_attachment.dstAlphaBlendFactor = vk.BlendFactor.ZERO
    color_blend_attachment.alphaBlendOp = vk.BlendOp.ADD
  }

  color_blending : vk.PipelineColorBlendStateCreateInfo
  {
    color_blending.sType = vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
    color_blending.logicOpEnable = false
    color_blending.logicOp = vk.LogicOp.COPY
    color_blending.attachmentCount = 1
    color_blending.pAttachments = &color_blend_attachment
    color_blending.blendConstants[0] = 0.0
    color_blending.blendConstants[1] = 0.0
    color_blending.blendConstants[2] = 0.0
    color_blending.blendConstants[3] = 0.0
  }

  dynamic_states := []vk.DynamicState{
    vk.DynamicState.VIEWPORT,
    vk.DynamicState.SCISSOR,
  }

  dynamic_state: vk.PipelineDynamicStateCreateInfo
  {
    dynamic_state.sType = vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO
    dynamic_state.dynamicStateCount = u32(len(dynamic_states))
    dynamic_state.pDynamicStates = raw_data(dynamic_states)
  }

  pipeline_layout_info : vk.PipelineLayoutCreateInfo
  {
    pipeline_layout_info.sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO
    pipeline_layout_info.setLayoutCount = 1
    pipeline_layout_info.pSetLayouts = &ctx.descriptor_set_layout
    pipeline_layout_info.pushConstantRangeCount = 0
    pipeline_layout_info.pPushConstantRanges = nil
  }

  if vk.CreatePipelineLayout(ctx.logical_device, &pipeline_layout_info, nil, &ctx.pipeline_layout) != vk.Result.SUCCESS {
    panic("Failed to create pipeline layout")
  }

  depth_stencil: vk.PipelineDepthStencilStateCreateInfo
  {
    depth_stencil.sType = vk.StructureType.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
    depth_stencil.depthTestEnable = true
    depth_stencil.depthWriteEnable = true

    depth_stencil.depthCompareOp = .LESS
    depth_stencil.depthBoundsTestEnable = false
    depth_stencil.minDepthBounds = 0.0
    depth_stencil.maxDepthBounds = 1.0

    depth_stencil.stencilTestEnable = false
    depth_stencil.front = {}
    depth_stencil.back = {}
  }

  pipeline_info: vk.GraphicsPipelineCreateInfo
  {
    pipeline_info.sType = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO
    pipeline_info.stageCount = 2
    pipeline_info.pStages = raw_data(shader_stages)
    pipeline_info.pVertexInputState = &vertex_input_info
    pipeline_info.pInputAssemblyState = &input_assembly
    pipeline_info.pViewportState = &viewport_state
    pipeline_info.pRasterizationState = &rasterizer
    pipeline_info.pMultisampleState = &multisampling
    pipeline_info.pDepthStencilState = &depth_stencil
    pipeline_info.pColorBlendState = &color_blending
    pipeline_info.pDynamicState = &dynamic_state
    pipeline_info.layout = ctx.pipeline_layout
    pipeline_info.renderPass = ctx.render_pass
    pipeline_info.subpass = 0
  }

  if vk.CreateGraphicsPipelines(ctx.logical_device, 0, 1, &pipeline_info, nil, &ctx.graphics_pipeline) != vk.Result.SUCCESS {
    panic("Failed to create graphic pipeline")
  }
  
  vk.DestroyShaderModule(ctx.logical_device, frag_shader_module, nil)
  vk.DestroyShaderModule(ctx.logical_device, vert_shader_module, nil)
}

create_render_pass :: proc(ctx: ^Context) {
  color_attachment: vk.AttachmentDescription
  {
    color_attachment.format = ctx.swap_chain_image_format
    color_attachment.samples = ctx.msaa_samples
    color_attachment.loadOp = vk.AttachmentLoadOp.CLEAR
    color_attachment.storeOp = vk.AttachmentStoreOp.STORE
    color_attachment.stencilLoadOp = vk.AttachmentLoadOp.DONT_CARE
    color_attachment.stencilStoreOp = vk.AttachmentStoreOp.DONT_CARE
    color_attachment.initialLayout = vk.ImageLayout.UNDEFINED
    color_attachment.finalLayout = vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL
  }

  color_attachment_ref: vk.AttachmentReference
  {
    color_attachment_ref.attachment = 0
    color_attachment_ref.layout = vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL
  }

  color_attachment_resolve: vk.AttachmentDescription
  {
    color_attachment_resolve.format = ctx.swap_chain_image_format
    color_attachment_resolve.samples = {._1}
    color_attachment_resolve.loadOp = .DONT_CARE
    color_attachment_resolve.storeOp = .STORE
    color_attachment_resolve.stencilLoadOp = .DONT_CARE
    color_attachment_resolve.stencilStoreOp = .DONT_CARE
    color_attachment_resolve.initialLayout = .UNDEFINED
    color_attachment_resolve.finalLayout = .PRESENT_SRC_KHR
  }

  color_attachment_resolve_ref: vk.AttachmentReference
  {
    color_attachment_resolve_ref.attachment = 2
    color_attachment_resolve_ref.layout = .COLOR_ATTACHMENT_OPTIMAL
  }

  depth_attachment: vk.AttachmentDescription
  {
    depth_attachment.format = find_depth_format(ctx)
    depth_attachment.samples = ctx.msaa_samples
    depth_attachment.loadOp = .CLEAR
    depth_attachment.storeOp = .DONT_CARE
    depth_attachment.stencilLoadOp = .DONT_CARE
    depth_attachment.stencilStoreOp = .DONT_CARE
    depth_attachment.initialLayout = .UNDEFINED
    depth_attachment.finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
  }

  depth_attachment_ref: vk.AttachmentReference
  {
    depth_attachment_ref.attachment = 1
    depth_attachment_ref.layout = vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL
  }

  subpass: vk.SubpassDescription
  {
    subpass.pipelineBindPoint = vk.PipelineBindPoint.GRAPHICS
    subpass.colorAttachmentCount = 1
    subpass.pColorAttachments = &color_attachment_ref
    subpass.pResolveAttachments = &color_attachment_resolve_ref
    subpass.pDepthStencilAttachment = &depth_attachment_ref
  }

  dependency: vk.SubpassDependency
  {
    dependency.srcSubpass = vk.SUBPASS_EXTERNAL
    dependency.dstSubpass = 0
    dependency.srcStageMask = vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
    dependency.srcAccessMask = vk.AccessFlags{vk.AccessFlag.INDIRECT_COMMAND_READ}
    dependency.dstStageMask = vk.PipelineStageFlags{vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
    dependency.dstAccessMask = vk.AccessFlags{vk.AccessFlag.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE}
  }

  attachments := []vk.AttachmentDescription{color_attachment, depth_attachment, color_attachment_resolve}

  render_pass_info: vk.RenderPassCreateInfo
  { 
    render_pass_info.sType = vk.StructureType.RENDER_PASS_CREATE_INFO
    render_pass_info.attachmentCount = u32(len(attachments))
    render_pass_info.pAttachments = raw_data(attachments)
    render_pass_info.subpassCount = 1
    render_pass_info.pSubpasses = &subpass
    render_pass_info.dependencyCount = 1
    render_pass_info.pDependencies = &dependency
  }

  if vk.CreateRenderPass(ctx.logical_device, &render_pass_info, nil, &ctx.render_pass) != vk.Result.SUCCESS {
    panic("Failed to create render pass")
  }
}

create_framebuffers :: proc(ctx: ^Context) {
  ctx.swap_chain_framebuffers = make([dynamic]vk.Framebuffer, len(ctx.swap_chain_image_views))
  for i := 0; i < len(ctx.swap_chain_image_views); i += 1 {
    attachments := []vk.ImageView{ctx.color_image_view, ctx.depth_image_view, ctx.swap_chain_image_views[i] }

    framebuffer_info: vk.FramebufferCreateInfo
    {
      framebuffer_info.sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO
      framebuffer_info.renderPass = ctx.render_pass
      framebuffer_info.attachmentCount = u32(len(attachments))
      framebuffer_info.pAttachments = raw_data(attachments)
      framebuffer_info.width = ctx.swap_chain_extent.width
      framebuffer_info.height = ctx.swap_chain_extent.height
      framebuffer_info.layers = 1
    }

    if vk.CreateFramebuffer(ctx.logical_device, &framebuffer_info, nil, &ctx.swap_chain_framebuffers[i]) != vk.Result.SUCCESS {
      panic("Failed to create framebuffer")
    }
  }
}

create_command_pool :: proc(ctx: ^Context) {
  queue_family_indices := find_queue_families(ctx, ctx.physical_device) or_else panic("Failed to get queue index")

  pool_info: vk.CommandPoolCreateInfo
  { 
    pool_info.sType = vk.StructureType.COMMAND_POOL_CREATE_INFO
    pool_info.flags = vk.CommandPoolCreateFlags{vk.CommandPoolCreateFlag.RESET_COMMAND_BUFFER}
    pool_info.queueFamilyIndex = queue_family_indices.graphics_family
  }
  if vk.CreateCommandPool(ctx.logical_device, &pool_info, nil, &ctx.command_pool) != vk.Result.SUCCESS {
    panic("Failed to create command pool")
  }
}

create_command_buffers :: proc(ctx: ^Context) {
  alloc_info: vk.CommandBufferAllocateInfo
  ctx.command_buffers = make([dynamic]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
  { 
    alloc_info.sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO
    alloc_info.commandPool = ctx.command_pool
    alloc_info.level = vk.CommandBufferLevel.PRIMARY
    alloc_info.commandBufferCount = u32(len(ctx.command_buffers))
  }
  if vk.AllocateCommandBuffers(ctx.logical_device, &alloc_info, raw_data(ctx.command_buffers)) != vk.Result.SUCCESS {
    panic("Failed to allocate command buffer")
  }
}

create_sync_objects :: proc(ctx: ^Context) {
  ctx.image_available_semaphores = make([dynamic]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
  ctx.render_finished_semaphores = make([dynamic]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
  ctx.in_flight_fences = make([dynamic]vk.Fence, MAX_FRAMES_IN_FLIGHT)

  semaphore_info: vk.SemaphoreCreateInfo
  semaphore_info.sType = vk.StructureType.SEMAPHORE_CREATE_INFO

  fence_info: vk.FenceCreateInfo
  fence_info.sType = vk.StructureType.FENCE_CREATE_INFO
  fence_info.flags = vk.FenceCreateFlags{vk.FenceCreateFlag.SIGNALED}

  for i := u32(0); i < MAX_FRAMES_IN_FLIGHT; i += 1{ 
    if vk.CreateSemaphore(ctx.logical_device, &semaphore_info, nil, &ctx.image_available_semaphores[i]) != vk.Result.SUCCESS ||
      vk.CreateSemaphore(ctx.logical_device, &semaphore_info, nil, &ctx.render_finished_semaphores[i]) != vk.Result.SUCCESS ||
      vk.CreateFence(ctx.logical_device, &fence_info, nil, &ctx.in_flight_fences[i]) != vk.Result.SUCCESS {
        panic("Failed to create sync objects")
      }
  }
}
