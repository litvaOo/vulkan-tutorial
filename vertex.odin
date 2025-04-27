package main

import vk "vendor:vulkan"
import "core:mem"
import "core:fmt"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Color :: [3]f32

Vertex :: struct {
  pos: Vec2,
  color: Color
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
  attribute_descriptions := make([]vk.VertexInputAttributeDescription, 2)

  {
    attribute_descriptions[0].binding = 0
    attribute_descriptions[0].location = 0
    attribute_descriptions[0].format = vk.Format.R32G32_SFLOAT
    attribute_descriptions[0].offset = u32(offset_of(Vertex, pos))
  }
  {
    attribute_descriptions[1].binding = 0
    attribute_descriptions[1].location = 1
    attribute_descriptions[1].format = vk.Format.R32G32B32_SFLOAT
    attribute_descriptions[1].offset = u32(offset_of(Vertex, color))
  }

  return attribute_descriptions
}

create_vertex_buffer :: proc(ctx: ^Context) {
  vertices := []Vertex{
    {{0.0, -0.5}, {1.0, 0.0, 0.0}},
    {{0.5, 0.5}, {0.0, 1.0, 0.0}},
    {{-0.5, 0.5}, {0.0, 0.0, 1.0}}
  }

  buffer_size := vk.DeviceSize(size_of(vertices[0]) * len(vertices))
  create_bufer(ctx,
        buffer_size, {vk.BufferUsageFlag.VERTEX_BUFFER},
        {vk.MemoryPropertyFlag.HOST_VISIBLE, vk.MemoryPropertyFlag.HOST_COHERENT},
        &ctx.vertex_buffer, &ctx.vertex_buffer_memory)

  data: rawptr
  if vk.MapMemory(ctx.logical_device, ctx.vertex_buffer_memory, 0, buffer_size, vk.MemoryMapFlags{vk.MemoryMapFlag.PLACED_EXT}, &data) != vk.Result.SUCCESS {
    panic("Failed to map memory")
  }
  mem.copy(data, raw_data(vertices), int(buffer_size))
  vk.UnmapMemory(ctx.logical_device, ctx.vertex_buffer_memory)
}

create_bufer :: proc(ctx: ^Context,
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

  if vk.AllocateMemory(ctx.logical_device, &allocate_info, nil, buffer_memory) != vk.Result.SUCCESS {
    panic("Failed to allocate memory")
  }

  vk.BindBufferMemory(ctx.logical_device, buffer^, buffer_memory^, 0)
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
