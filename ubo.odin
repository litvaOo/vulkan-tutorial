package main

import vk "vendor:vulkan"
import "core:time"
import "core:math/linalg"
import "core:mem"

UBO :: struct #align(16){
  model: matrix[4, 4]f32,
  view: matrix[4, 4]f32,
  proj: matrix[4, 4]f32,
}

create_descriptor_set_layout :: proc(ctx: ^Context) {
  ubo_layout_binding: vk.DescriptorSetLayoutBinding
  {
    ubo_layout_binding.binding = 0
    ubo_layout_binding.descriptorType = vk.DescriptorType.UNIFORM_BUFFER
    ubo_layout_binding.descriptorCount = 1
    ubo_layout_binding.stageFlags = {vk.ShaderStageFlag.VERTEX }
    ubo_layout_binding.pImmutableSamplers = nil
  }

  layout_info: vk.DescriptorSetLayoutCreateInfo
  {
    layout_info.sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_CREATE_INFO
    layout_info.bindingCount = 1
    layout_info.pBindings = &ubo_layout_binding
  }

  if vk.CreateDescriptorSetLayout(ctx.logical_device, &layout_info, nil, &ctx.descriptor_set_layout) != vk.Result.SUCCESS {
    panic("Failed to create descriptor set layout")
  }
}

create_uniform_buffer :: proc(ctx: ^Context) {
  buffer_size := vk.DeviceSize(size_of(UBO))

  ctx.uniform_buffers = make([dynamic]vk.Buffer, MAX_FRAMES_IN_FLIGHT)
  ctx.uniform_buffers_memory = make([dynamic]vk.DeviceMemory, MAX_FRAMES_IN_FLIGHT)
  ctx.uniform_buffers_mapped = make([dynamic]rawptr, MAX_FRAMES_IN_FLIGHT)

  for i in 0..<MAX_FRAMES_IN_FLIGHT {
    create_buffer(ctx, buffer_size, 
        {vk.BufferUsageFlag.UNIFORM_BUFFER}, {vk.MemoryPropertyFlag.HOST_VISIBLE, vk.MemoryPropertyFlag.HOST_COHERENT},
        &ctx.uniform_buffers[i], &ctx.uniform_buffers_memory[i])
    vk.MapMemory(ctx.logical_device, ctx.uniform_buffers_memory[i], 0, buffer_size, {}, &ctx.uniform_buffers_mapped[i])

  }
}

update_uniform_buffer :: proc(ctx: ^Context) {
  diff_time := time.duration_seconds(time.diff(ctx.start_time, time.now()))

  {
    // diff time is divided by ten because we are too fast
    ctx.ubo.model = linalg.matrix_mul(linalg.identity(matrix[4,4]f32), linalg.matrix4_rotate_f32(90.0*f32(diff_time/20), [3]f32{0.0, 0.0, 1.0}))
    ctx.ubo.view = linalg.matrix_mul(linalg.identity(matrix[4,4]f32), linalg.matrix4_look_at_f32([3]f32{2.0, 2.0, 2.0}, [3]f32{0.0, 0.0, 0.0}, [3]f32{0.0, 0.0, 1.0}))
    ctx.ubo.proj = linalg.matrix_mul(linalg.identity(matrix[4,4]f32), linalg.matrix4_perspective_f32(45.0, f32(ctx.swap_chain_extent.width)/f32(ctx.swap_chain_extent.height), 0.1, 10))
    ctx.ubo.proj[1][1] *= -1
  }

  mem.copy(ctx.uniform_buffers_mapped[ctx.current_frame], &ctx.ubo, size_of(ctx.ubo))
}

create_descriptor_pool :: proc(ctx: ^Context) {
  pool_size: vk.DescriptorPoolSize
  {
    pool_size.type = vk.DescriptorType.UNIFORM_BUFFER
    pool_size.descriptorCount = MAX_FRAMES_IN_FLIGHT
  }

  pool_info: vk.DescriptorPoolCreateInfo
  {
    pool_info.sType = vk.StructureType.DESCRIPTOR_POOL_CREATE_INFO
    pool_info.poolSizeCount = 1
    pool_info.pPoolSizes = &pool_size
    pool_info.maxSets = MAX_FRAMES_IN_FLIGHT
  }

  if vk.CreateDescriptorPool(ctx.logical_device, &pool_info, nil, &ctx.descriptor_pool) != vk.Result.SUCCESS {
    panic("Failed to create descriptor pool")
  }
}

create_descriptor_sets :: proc(ctx: ^Context) {
  layouts := [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout{}
  for i in 0..<MAX_FRAMES_IN_FLIGHT {
    layouts[i] = ctx.descriptor_set_layout
  }
  
  alloc_info: vk.DescriptorSetAllocateInfo
  {
    alloc_info.sType = vk.StructureType.DESCRIPTOR_SET_ALLOCATE_INFO
    alloc_info.descriptorPool = ctx.descriptor_pool
    alloc_info.descriptorSetCount = MAX_FRAMES_IN_FLIGHT
    alloc_info.pSetLayouts = raw_data(layouts[:])
  }

  ctx.descriptor_sets = make([dynamic]vk.DescriptorSet, MAX_FRAMES_IN_FLIGHT)
  if vk.AllocateDescriptorSets(ctx.logical_device, &alloc_info, raw_data(ctx.descriptor_sets)) != vk.Result.SUCCESS {
    panic("Failed to allocate descriptor sets")
  }

  for i in 0..<MAX_FRAMES_IN_FLIGHT {
    buffer_info: vk.DescriptorBufferInfo
    {
      buffer_info.buffer = ctx.uniform_buffers[i]
      buffer_info.offset = 0
      buffer_info.range = size_of(UBO)
    }

    descriptor_write: vk.WriteDescriptorSet
    {
      descriptor_write.sType = vk.StructureType.WRITE_DESCRIPTOR_SET
      descriptor_write.dstSet = ctx.descriptor_sets[i]
      descriptor_write.dstBinding = 0
      descriptor_write.dstArrayElement = 0
      descriptor_write.descriptorType = vk.DescriptorType.UNIFORM_BUFFER
      descriptor_write.descriptorCount = 1
      descriptor_write.pBufferInfo = &buffer_info
      descriptor_write.pImageInfo = nil
      descriptor_write.pTexelBufferView = nil
    }

    vk.UpdateDescriptorSets(ctx.logical_device, 1, &descriptor_write, 0, nil)
  }
}
