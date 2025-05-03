package main

import vk "vendor:vulkan"

get_max_usable_sample_count :: proc(ctx: ^Context) -> vk.SampleCountFlags {
  physical_device_properties: vk.PhysicalDeviceProperties
  vk.GetPhysicalDeviceProperties(ctx.physical_device, &physical_device_properties)

  counts := ( physical_device_properties.limits.framebufferColorSampleCounts
      & physical_device_properties.limits.framebufferDepthSampleCounts )
  if counts & {._64} != {} do return {._64}
  if counts & {._32} != {} do return {._32}
  if counts & {._16} != {} do return {._16}
  if counts & {._8} != {} do return {._8}
  if counts & {._4} != {} do return {._4}
  if counts & {._2} != {} do return {._2}

  return {._1}
}

create_color_resources :: proc(ctx: ^Context) {
  color_format := ctx.swap_chain_image_format
  
  create_image(ctx, i32(ctx.swap_chain_extent.width), i32(ctx.swap_chain_extent.height), 1,
               ctx.msaa_samples, color_format, .OPTIMAL, {.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT},
               { .DEVICE_LOCAL }, &ctx.color_image, &ctx.color_image_memory)
  ctx.color_image_view = create_image_view(ctx, ctx.color_image, color_format, {.COLOR}, 1)
}
