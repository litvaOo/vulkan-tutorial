package main

import vk "vendor:vulkan"
import "core:mem"
import "core:fmt"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Color :: [3]f32

Vertex :: struct {
  pos: Vec3,
  color: Color,
  tex_coord: Vec2,
}

get_binding_description :: proc(ctx: ^Context) -> vk.VertexInputBindingDescription {
  binding_description : vk.VertexInputBindingDescription
  {
    binding_description.binding = 0
    binding_description.stride = size_of(Vertex)
    binding_description.inputRate = vk.VertexInputRate.VERTEX
  }
  return binding_description
}

get_attribute_descriptions :: proc(ctx: ^Context) -> []vk.VertexInputAttributeDescription {
  attribute_descriptions := make([]vk.VertexInputAttributeDescription, 3)

  {
    attribute_descriptions[0].binding = 0
    attribute_descriptions[0].location = 0
    attribute_descriptions[0].format = vk.Format.R32G32B32_SFLOAT
    attribute_descriptions[0].offset = u32(offset_of(Vertex, pos))
  }
  {
    attribute_descriptions[1].binding = 0
    attribute_descriptions[1].location = 1
    attribute_descriptions[1].format = vk.Format.R32G32B32_SFLOAT
    attribute_descriptions[1].offset = u32(offset_of(Vertex, color))
  }
  {
    attribute_descriptions[2].binding = 0
    attribute_descriptions[2].location = 2
    attribute_descriptions[2].format = vk.Format.R32G32_SFLOAT
    attribute_descriptions[2].offset = u32(offset_of(Vertex, tex_coord))
  }

  return attribute_descriptions
}

create_vertex_buffer :: proc(ctx: ^Context) {
  buffer_size := vk.DeviceSize(size_of(ctx.vertices[0]) * len(ctx.vertices))

  staging_buffer: vk.Buffer
  staging_buffer_memory: vk.DeviceMemory
  create_buffer(ctx,
        buffer_size, {vk.BufferUsageFlag.VERTEX_BUFFER},
        {vk.MemoryPropertyFlag.HOST_VISIBLE, vk.MemoryPropertyFlag.HOST_COHERENT},
        &staging_buffer, &staging_buffer_memory)

  data: rawptr
  if vk.MapMemory(ctx.logical_device, staging_buffer_memory, 0, buffer_size, vk.MemoryMapFlags{vk.MemoryMapFlag.PLACED_EXT}, &data) != vk.Result.SUCCESS {
    panic("Failed to map memory")
  }
  mem.copy(data, raw_data(ctx.vertices), int(buffer_size))
  vk.UnmapMemory(ctx.logical_device, staging_buffer_memory)

  create_buffer(ctx, buffer_size,
    {vk.BufferUsageFlag.TRANSFER_DST, vk.BufferUsageFlag.VERTEX_BUFFER}, {vk.MemoryPropertyFlag.DEVICE_LOCAL},
    &ctx.vertex_buffer, &ctx.vertex_buffer_memory)

  copy_buffer(ctx, staging_buffer, ctx.vertex_buffer, buffer_size)
  vk.DestroyBuffer(ctx.logical_device, staging_buffer, nil)
  vk.FreeMemory(ctx.logical_device, staging_buffer_memory, nil)
}

create_index_buffer :: proc(ctx: ^Context) {
  buffer_size := vk.DeviceSize(size_of(ctx.indices[0])*len(ctx.indices))

  staging_buffer: vk.Buffer
  staging_buffer_memory: vk.DeviceMemory
  create_buffer(ctx,
        buffer_size, {vk.BufferUsageFlag.TRANSFER_SRC},
        {vk.MemoryPropertyFlag.HOST_VISIBLE, vk.MemoryPropertyFlag.HOST_COHERENT},
        &staging_buffer, &staging_buffer_memory)

  data: rawptr
  if vk.MapMemory(ctx.logical_device, staging_buffer_memory, 0, buffer_size, vk.MemoryMapFlags{vk.MemoryMapFlag.PLACED_EXT}, &data) != vk.Result.SUCCESS {
    panic("Failed to map memory")
  }
  mem.copy(data, raw_data(ctx.indices), int(buffer_size))
  vk.UnmapMemory(ctx.logical_device, staging_buffer_memory)

  create_buffer(ctx, buffer_size,
    {vk.BufferUsageFlag.TRANSFER_DST, vk.BufferUsageFlag.INDEX_BUFFER}, {vk.MemoryPropertyFlag.DEVICE_LOCAL},
    &ctx.index_buffer, &ctx.index_buffer_memory)

  copy_buffer(ctx, staging_buffer, ctx.index_buffer, buffer_size)
  vk.DestroyBuffer(ctx.logical_device, staging_buffer, nil)
  vk.FreeMemory(ctx.logical_device, staging_buffer_memory, nil)
}

create_buffer :: proc(ctx: ^Context,
      size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags,
      buffer: ^vk.Buffer, buffer_memory: ^vk.DeviceMemory) {
  buffer_info: vk.BufferCreateInfo
  {
    buffer_info.sType = vk.StructureType.BUFFER_CREATE_INFO
    buffer_info.size = size
    buffer_info.usage = usage
    buffer_info.sharingMode = vk.SharingMode.EXCLUSIVE
  }

  if vk.CreateBuffer(ctx.logical_device, &buffer_info, nil, buffer) != vk.Result.SUCCESS {
    panic("Failed to create new buffer")
  }

  mem_requirements: vk.MemoryRequirements
  vk.GetBufferMemoryRequirements(ctx.logical_device, buffer^, &mem_requirements)

  allocate_info: vk.MemoryAllocateInfo
  {
    allocate_info.sType = vk.StructureType.MEMORY_ALLOCATE_INFO
    allocate_info.allocationSize = mem_requirements.size
    allocate_info.memoryTypeIndex = find_memory_type(ctx, mem_requirements.memoryTypeBits, properties)
  }

  if res := vk.AllocateMemory(ctx.logical_device, &allocate_info, nil, buffer_memory); res != vk.Result.SUCCESS {
    fmt.println(res)
    panic("Failed to allocate memory")
  }

  vk.BindBufferMemory(ctx.logical_device, buffer^, buffer_memory^, 0)
}

copy_buffer :: proc(ctx: ^Context, src_buffer, dst_buffer: vk.Buffer, size: vk.DeviceSize) {
  command_buffer := begin_single_time_commands(ctx)

  copy_region: vk.BufferCopy
  {
    copy_region.srcOffset = 0
    copy_region.dstOffset = 0
    copy_region.size = size
  }
  vk.CmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region)

  end_single_time_commands(ctx, &command_buffer)
}

find_memory_type :: proc(ctx: ^Context, type_filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
  mem_properties: vk.PhysicalDeviceMemoryProperties
  vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_properties)
  for i := u32(0); i < mem_properties.memoryTypeCount; i += 1 {
    if (type_filter & (1 << i)) != 0 && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
          return i
      }
  }

  panic("Failed to find suitable memory")
}
