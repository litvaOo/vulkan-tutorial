package main

import vk "vendor:vulkan"
import stb "vendor:stb/image"
import "core:mem"

create_texture_image :: proc(ctx: ^Context) {
  tex_width, tex_height, tex_channels: i32
  pixels := stb.load("texture.jpg", &tex_width, &tex_height, &tex_channels, 0)
  defer   stb.image_free(pixels)

  image_size : = vk.DeviceSize(tex_width * tex_height * 4)
  if pixels == nil {
    panic("Failed to read texture")
  }

  staging_buffer: vk.Buffer
  staging_buffer_memory: vk.DeviceMemory
  create_buffer(ctx, image_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

  data: rawptr
  vk.MapMemory(ctx.logical_device, staging_buffer_memory, 0, image_size, {}, &data)
  mem.copy(data, pixels, int(image_size))
  vk.UnmapMemory(ctx.logical_device, staging_buffer_memory)

  create_image(ctx, tex_width, tex_height,
              vk.Format.R8G8B8A8_SRGB, vk.ImageTiling.OPTIMAL, {.TRANSFER_DST, .SAMPLED},
              {.DEVICE_LOCAL}, &ctx.texture_image, &ctx.texture_image_memory)

  transition_image_layout(ctx, ctx.texture_image, vk.Format.R8G8B8A8_SRGB, vk.ImageLayout.UNDEFINED, vk.ImageLayout.TRANSFER_DST_OPTIMAL)
  copy_buffer_to_image(ctx, staging_buffer, ctx.texture_image, tex_width, tex_height)

  transition_image_layout(ctx, ctx.texture_image, vk.Format.R8G8B8A8_SRGB, vk.ImageLayout.TRANSFER_DST_OPTIMAL, vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL)
}

create_image :: proc(ctx: ^Context,
                    width, height: i32, format: vk.Format, tiling: vk.ImageTiling,
                    usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags,
                    image: ^vk.Image, image_memory: ^vk.DeviceMemory) {
    image_info: vk.ImageCreateInfo
  {
    image_info.sType = vk.StructureType.IMAGE_CREATE_INFO
    image_info.imageType = vk.ImageType.D2
    image_info.extent.width = u32(width)
    image_info.extent.height = u32(height)
    image_info.extent.depth = 1
    image_info.mipLevels = 1
    image_info.arrayLayers = 1
    image_info.format = format
    image_info.tiling = tiling
    image_info.initialLayout = vk.ImageLayout.UNDEFINED
    image_info.usage = usage
    image_info.sharingMode = vk.SharingMode.EXCLUSIVE
    image_info.samples = { ._1 }
    image_info.flags = {}
  }

  if vk.CreateImage(ctx.logical_device, &image_info, nil, image) != vk.Result.SUCCESS {
    panic("Failed to create image")
  }

  mem_requirements: vk.MemoryRequirements
  vk.GetImageMemoryRequirements(ctx.logical_device, image^, &mem_requirements)

  alloc_info: vk.MemoryAllocateInfo
  {
    alloc_info.sType = vk.StructureType.MEMORY_ALLOCATE_INFO
    alloc_info.allocationSize = mem_requirements.size
    alloc_info.memoryTypeIndex = find_memory_type(ctx, mem_requirements.memoryTypeBits, properties)
  }

  if vk.AllocateMemory(ctx.logical_device, &alloc_info, nil, image_memory) != vk.Result.SUCCESS {
    panic("Failed to allocate memory for image")
  }

  vk.BindImageMemory(ctx.logical_device, image^, image_memory^, 0)
}

transition_image_layout :: proc(ctx: ^Context, image: vk.Image, format: vk.Format,
                                old_layout, new_layout: vk.ImageLayout) {
  command_buffer := begin_single_time_commands(ctx)
  defer end_single_time_commands(ctx, &command_buffer)

  barrier: vk.ImageMemoryBarrier
  {
    barrier.sType = vk.StructureType.IMAGE_MEMORY_BARRIER
    barrier.oldLayout = old_layout
    barrier.newLayout = new_layout
    barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
    barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
    barrier.image = image
    barrier.subresourceRange.aspectMask = { .COLOR }
    barrier.subresourceRange.baseMipLevel = 0
    barrier.subresourceRange.levelCount = 1
    barrier.subresourceRange.baseArrayLayer = 0
    barrier.subresourceRange.layerCount = 1
  }

  destination_stage, source_stage: vk.PipelineStageFlags
  if old_layout == vk.ImageLayout.UNDEFINED && new_layout == vk.ImageLayout.TRANSFER_DST_OPTIMAL {
    barrier.srcAccessMask = {}
    barrier.dstAccessMask = {.TRANSFER_WRITE}

    source_stage = {.TOP_OF_PIPE}
    destination_stage = {.TRANSFER}
  } else if old_layout == vk.ImageLayout.TRANSFER_DST_OPTIMAL && new_layout == vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL {
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstAccessMask = {.SHADER_READ}

    source_stage = {.TRANSFER}
    destination_stage = { .FRAGMENT_SHADER}
  } else {
    panic("Incorrect conversion of image")
  }

  vk.CmdPipelineBarrier(command_buffer, source_stage, destination_stage, {},
                        0, nil, 0, nil, 1, &barrier)
}

copy_buffer_to_image :: proc(ctx: ^Context, buffer: vk.Buffer, image: vk.Image,
                            width, height: i32) {
  command_buffer := begin_single_time_commands(ctx)
  defer end_single_time_commands(ctx, &command_buffer)

  region: vk.BufferImageCopy
  {
    region.bufferOffset = 0
    region.bufferRowLength = 0
    region.bufferImageHeight = 0

    region.imageSubresource.aspectMask = {.COLOR}
    region.imageSubresource.mipLevel = 0
    region.imageSubresource.baseArrayLayer = 0
    region.imageSubresource.layerCount = 1

    region.imageOffset = {0, 0, 0}
    region.imageExtent = {
      u32(width), u32(height), 1
    }
  }

  vk.CmdCopyBufferToImage(command_buffer, buffer, image, vk.ImageLayout.TRANSFER_DST_OPTIMAL, 1, &region)
}

create_texture_image_view :: proc(ctx: ^Context) {
  ctx.texture_image_view = create_image_view(ctx, ctx.texture_image, vk.Format.R8G8B8A8_SRGB)
}

create_image_view :: proc(ctx: ^Context, image: vk.Image, format: vk.Format) -> vk.ImageView {
  view_info: vk.ImageViewCreateInfo
  {
    view_info.sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO
    view_info.image = image
    view_info.viewType = vk.ImageViewType.D2
    view_info.format = format
    view_info.subresourceRange.aspectMask = {.COLOR}
    view_info.subresourceRange.baseMipLevel = 0
    view_info.subresourceRange.levelCount = 1
    view_info.subresourceRange.baseArrayLayer = 0
    view_info.subresourceRange.layerCount = 1
  }

  image_view: vk.ImageView
  if vk.CreateImageView(ctx.logical_device, &view_info, nil, &image_view) != vk.Result.SUCCESS {
    panic("Failed to create image view")
  }

  return image_view
}

create_texture_sampler :: proc(ctx: ^Context) {
  properties: vk.PhysicalDeviceProperties
  vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties)

  sampler_info: vk.SamplerCreateInfo
  {
    sampler_info.sType = vk.StructureType.SAMPLER_CREATE_INFO
    sampler_info.magFilter = vk.Filter.LINEAR
    sampler_info.minFilter = vk.Filter.LINEAR
    sampler_info.addressModeU = vk.SamplerAddressMode.REPEAT
    sampler_info.addressModeV = vk.SamplerAddressMode.REPEAT
    sampler_info.addressModeW = vk.SamplerAddressMode.REPEAT
    sampler_info.anisotropyEnable = true
    sampler_info.maxAnisotropy = properties.limits.maxSamplerAnisotropy
    sampler_info.borderColor = vk.BorderColor.INT_OPAQUE_BLACK
    sampler_info.unnormalizedCoordinates = false
    sampler_info.compareEnable = false
    sampler_info.compareOp = vk.CompareOp.ALWAYS
    sampler_info.mipmapMode = vk.SamplerMipmapMode.LINEAR
    sampler_info.mipLodBias = 0.0
    sampler_info.minLod = 0.0
    sampler_info.maxLod = 0.0
  }

  if vk.CreateSampler(ctx.logical_device, &sampler_info, nil, &ctx.texture_sampler) != vk.Result.SUCCESS {
    panic("Failed to create texture samplers")
  }
}
