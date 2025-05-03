package main

import vk "vendor:vulkan"
import stb "vendor:stb/image"
import "core:mem"
import "core:math"

create_texture_image :: proc(ctx: ^Context) {
  tex_width, tex_height, tex_channels: i32
  // stbi_rgb_alpha = 4 for desired_channel
  pixels := stb.load(TEXTURE_PATH, &tex_width, &tex_height, &tex_channels, 4)
  defer stb.image_free(pixels)
  ctx.mip_levels = u32(math.floor(math.log2(f32(max(tex_width, tex_height))))) + 1
  image_size : = vk.DeviceSize(tex_width * tex_height * 4)
  if pixels == nil {
    panic("Failed to read texture")
  }

  staging_buffer: vk.Buffer
  staging_buffer_memory: vk.DeviceMemory
  create_buffer(ctx, image_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, &staging_buffer_memory)

  data := mem.alloc(int(image_size)) or_else panic("Failed to alloc data for texture")
  if vk.MapMemory(ctx.logical_device, staging_buffer_memory, 0, image_size, {}, &data) != vk.Result.SUCCESS {
    panic("Failed to map memory")
  }
  mem.copy(data, pixels, int(image_size))
  vk.UnmapMemory(ctx.logical_device, staging_buffer_memory)

  create_image(ctx, tex_width, tex_height, ctx.mip_levels,
              vk.Format.R8G8B8A8_SRGB, vk.ImageTiling.OPTIMAL, {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
              {.DEVICE_LOCAL}, &ctx.texture_image, &ctx.texture_image_memory)

  transition_image_layout(ctx, ctx.texture_image, vk.Format.R8G8B8A8_SRGB, vk.ImageLayout.UNDEFINED, vk.ImageLayout.TRANSFER_DST_OPTIMAL, ctx.mip_levels)
  copy_buffer_to_image(ctx, staging_buffer, ctx.texture_image, tex_width, tex_height)

  generate_mipmaps(ctx, ctx.texture_image, .R8G8B8A8_SRGB, u32(tex_width), u32(tex_height), ctx.mip_levels)
 
  // transition_image_layout(ctx, ctx.texture_image, vk.Format.R8G8B8A8_SRGB, vk.ImageLayout.TRANSFER_DST_OPTIMAL, vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL, ctx.mip_levels)
}

create_image :: proc(ctx: ^Context,
                    width, height: i32, mip_levels: u32, format: vk.Format, tiling: vk.ImageTiling,
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
      image_info.mipLevels = mip_levels
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
                                old_layout, new_layout: vk.ImageLayout, mip_levels: u32) {
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
    barrier.subresourceRange.levelCount = mip_levels
    barrier.subresourceRange.baseArrayLayer = 0
    barrier.subresourceRange.layerCount = 1
  }

  if new_layout == vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
    barrier.subresourceRange.aspectMask = {.DEPTH}

    if has_stencil_component(ctx, format) {
      barrier.subresourceRange.aspectMask = {.DEPTH, .STENCIL}
    }
  } else {
    barrier.subresourceRange.aspectMask = {.COLOR}
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
  } else if old_layout == vk.ImageLayout.UNDEFINED && new_layout == vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
    barrier.srcAccessMask = {}
    barrier.dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}

    source_stage = {.TOP_OF_PIPE}
    destination_stage = {.EARLY_FRAGMENT_TESTS}

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
  ctx.texture_image_view = create_image_view(ctx, ctx.texture_image, vk.Format.R8G8B8A8_SRGB, {.COLOR}, ctx.mip_levels)
}

create_image_view :: proc(ctx: ^Context, image: vk.Image, format: vk.Format, aspectFlags: vk.ImageAspectFlags, mip_levels: u32) -> vk.ImageView {
  view_info: vk.ImageViewCreateInfo
  {
    view_info.sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO
    view_info.image = image
    view_info.viewType = vk.ImageViewType.D2
    view_info.format = format
    view_info.subresourceRange.aspectMask = aspectFlags
    view_info.subresourceRange.baseMipLevel = 0
    view_info.subresourceRange.levelCount = mip_levels
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
    sampler_info.maxLod = f32( ctx.mip_levels )
  }

  if vk.CreateSampler(ctx.logical_device, &sampler_info, nil, &ctx.texture_sampler) != vk.Result.SUCCESS {
    panic("Failed to create texture samplers")
  }
}

create_depth_resources :: proc(ctx: ^Context) {
  depth_format := find_depth_format(ctx)

  create_image(ctx, i32(ctx.swap_chain_extent.width), i32(ctx.swap_chain_extent.height), ctx.mip_levels,
                depth_format, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL},
                &ctx.depth_image, &ctx.depth_image_memory)
  ctx.depth_image_view = create_image_view(ctx, ctx.depth_image, depth_format, { .DEPTH }, ctx.mip_levels)

  transition_image_layout(ctx, ctx.depth_image, depth_format, vk.ImageLayout.UNDEFINED, vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL, ctx.mip_levels)
}

find_supported_format :: proc(ctx: ^Context, candidates: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format {
  for format in candidates {
    props: vk.FormatProperties
    vk.GetPhysicalDeviceFormatProperties(ctx.physical_device, format, &props)

    if tiling == vk.ImageTiling.LINEAR && props.linearTilingFeatures & features == features {
      return format
    }
    if tiling == vk.ImageTiling.OPTIMAL && props.optimalTilingFeatures & features == features {
      return format
    }
  }
  panic("Failed to find supported format")
}

find_depth_format :: proc(ctx: ^Context) -> vk.Format {
  return find_supported_format(ctx, {.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, vk.ImageTiling.OPTIMAL, { .DEPTH_STENCIL_ATTACHMENT })
}

has_stencil_component :: proc(ctx: ^Context, format: vk.Format) -> bool {
  return format == vk.Format.D32_SFLOAT_S8_UINT || format == vk.Format.D24_UNORM_S8_UINT
}

generate_mipmaps :: proc(ctx: ^Context, image: vk.Image, image_format: vk.Format, tex_width, tex_height, mip_levels: u32) {
  format_properties: vk.FormatProperties
  vk.GetPhysicalDeviceFormatProperties(ctx.physical_device, image_format, &format_properties)
  if format_properties.optimalTilingFeatures & { .SAMPLED_IMAGE_FILTER_LINEAR } == {} {
    panic("Image format does not support linear blitting")
  }

  command_buffer := begin_single_time_commands(ctx)

  barrier: vk.ImageMemoryBarrier
  {
    barrier.sType = vk.StructureType.IMAGE_MEMORY_BARRIER
    barrier.image = image
    barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
    barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
    barrier.subresourceRange.aspectMask = {.COLOR}
    barrier.subresourceRange.baseArrayLayer = 0
    barrier.subresourceRange.layerCount = 1
    barrier.subresourceRange.levelCount = 1
  }

  mip_width, mip_height := i32(tex_width), i32(tex_height)

  for i in 1..<mip_levels {
    barrier.subresourceRange.baseMipLevel = i - 1
    barrier.oldLayout = vk.ImageLayout.TRANSFER_DST_OPTIMAL
    barrier.newLayout = vk.ImageLayout.TRANSFER_SRC_OPTIMAL
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstAccessMask = {.TRANSFER_READ}

    vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

    blit: vk.ImageBlit
    {
      blit.srcOffsets[0] = {0, 0, 0}
      blit.srcOffsets[1] = {mip_width, mip_height, 1}
      blit.srcSubresource.aspectMask = {.COLOR}
      blit.srcSubresource.mipLevel = i - 1
      blit.srcSubresource.baseArrayLayer = 0
      blit.srcSubresource.layerCount = 1
      blit.dstOffsets[0] = {0, 0, 0}
      blit.dstOffsets[1] = { mip_width > 1 ? mip_width / 2 : 1,
                             mip_height > 1 ? mip_height / 2 : 1,
                             1}
      blit.dstSubresource.aspectMask = {.COLOR}
      blit.dstSubresource.mipLevel = i
      blit.dstSubresource.baseArrayLayer = 0
      blit.dstSubresource.layerCount = 1
    }
    vk.CmdBlitImage(command_buffer, image, .TRANSFER_SRC_OPTIMAL, image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

    barrier.oldLayout = vk.ImageLayout.TRANSFER_DST_OPTIMAL
    barrier.newLayout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
    barrier.srcAccessMask = {.TRANSFER_READ}
    barrier.dstAccessMask = {.SHADER_READ}

    vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)
    if mip_width > 1 do mip_width /= 2
    if mip_height > 1 do mip_height /= 2
  }

  barrier.subresourceRange.baseMipLevel = mip_levels - 1
  barrier.oldLayout = vk.ImageLayout.TRANSFER_DST_OPTIMAL
  barrier.newLayout = vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
  barrier.srcAccessMask = {.TRANSFER_READ}
  barrier.dstAccessMask = {.SHADER_READ}

  vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)


  end_single_time_commands(ctx, &command_buffer)
}

