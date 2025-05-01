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

  sampler_layout_binding: vk.DescriptorSetLayoutBinding
  {
    sampler_layout_binding.binding = 1
    sampler_layout_binding.descriptorCount = 1
    sampler_layout_binding.descriptorType = vk.DescriptorType.COMBINED_IMAGE_SAMPLER
    sampler_layout_binding.pImmutableSamplers = nil
    sampler_layout_binding.stageFlags = { .FRAGMENT }
  }

  bindings := []vk.DescriptorSetLayoutBinding{ubo_layout_binding, sampler_layout_binding}

  layout_info: vk.DescriptorSetLayoutCreateInfo
  {
    layout_info.sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_CREATE_INFO
    layout_info.bindingCount = u32(len(bindings))
    layout_info.pBindings = raw_data(bindings)
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
    ctx.ubo.model = linalg.matrix_mul(linalg.identity(matrix[4,4]f32), linalg.matrix4_rotate_f32(90.0*f32(diff_time/20), [3]f32{1.0, 0.0, 1.0}))
    ctx.ubo.view = linalg.matrix_mul(linalg.identity(matrix[4,4]f32), linalg.matrix4_look_at_f32([3]f32{2.0, 2.0, 2.0}, [3]f32{0.0, 0.0, 0.0}, [3]f32{0.0, 0.0, 1.0}))
    ctx.ubo.proj = linalg.matrix_mul(linalg.identity(matrix[4,4]f32), linalg.matrix4_perspective_f32(45.0, f32(ctx.swap_chain_extent.width)/f32(ctx.swap_chain_extent.height), 0.1, 10))
    ctx.ubo.proj[1][1] *= -1
  }

  mem.copy(ctx.uniform_buffers_mapped[ctx.current_frame], &ctx.ubo, size_of(ctx.ubo))
}

create_descriptor_pool :: proc(ctx: ^Context) {
  pool_sizes : [2]vk.DescriptorPoolSize
  {
    pool_sizes[0].type = vk.DescriptorType.UNIFORM_BUFFER
    pool_sizes[0].descriptorCount = MAX_FRAMES_IN_FLIGHT
    pool_sizes[1].type = vk.DescriptorType.COMBINED_IMAGE_SAMPLER
    pool_sizes[1].descriptorCount = MAX_FRAMES_IN_FLIGHT
  }

  pool_info: vk.DescriptorPoolCreateInfo
  {
    pool_info.sType = vk.StructureType.DESCRIPTOR_POOL_CREATE_INFO
    pool_info.poolSizeCount = u32(len(pool_sizes))
    pool_info.pPoolSizes = raw_data(&pool_sizes)
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

    image_info: vk.DescriptorImageInfo
    {
      image_info.imageLayout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
      image_info.imageView = ctx.texture_image_view
      image_info.sampler = ctx.texture_sampler
    }

    descriptor_writes: [2]vk.WriteDescriptorSet
    {
      {
        descriptor_writes[0].sType = vk.StructureType.WRITE_DESCRIPTOR_SET
        descriptor_writes[0].dstSet = ctx.descriptor_sets[i]
        descriptor_writes[0].dstBinding = 0
        descriptor_writes[0].dstArrayElement = 0
        descriptor_writes[0].descriptorType = vk.DescriptorType.UNIFORM_BUFFER
        descriptor_writes[0].descriptorCount = 1
        descriptor_writes[0].pBufferInfo = &buffer_info
        descriptor_writes[0].pImageInfo = nil
        descriptor_writes[0].pTexelBufferView = nil
      }

      {
        descriptor_writes[1].sType = vk.StructureType.WRITE_DESCRIPTOR_SET
        descriptor_writes[1].dstSet = ctx.descriptor_sets[i]
        descriptor_writes[1].dstBinding = 1
        descriptor_writes[1].dstArrayElement = 0
        descriptor_writes[1].descriptorType = vk.DescriptorType.COMBINED_IMAGE_SAMPLER
        descriptor_writes[1].descriptorCount = 1
        descriptor_writes[1].pImageInfo = &image_info
        descriptor_writes[1].pBufferInfo = nil
        descriptor_writes[1].pTexelBufferView = nil
      }
    }

    vk.UpdateDescriptorSets(ctx.logical_device, len(descriptor_writes), raw_data(&descriptor_writes), 0, nil)
  }
}
