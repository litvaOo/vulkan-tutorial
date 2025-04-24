package main

import vk "vendor:vulkan"
import "core:math/bits"
import "vendor:glfw"

SwapChainSupportDetails :: struct {
  capabilities: vk.SurfaceCapabilitiesKHR,
  formats: [dynamic]vk.SurfaceFormatKHR,
  present_modes: [dynamic]vk.PresentModeKHR,
}

query_swap_chain_support :: proc(ctx: ^Context, device: vk.PhysicalDevice) -> SwapChainSupportDetails {
  details: SwapChainSupportDetails
  vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, ctx.surface, &details.capabilities)

  format_count: u32
  vk.GetPhysicalDeviceSurfaceFormatsKHR(device, ctx.surface, &format_count, nil)

  if format_count != 0 {
    details.formats = make([dynamic]vk.SurfaceFormatKHR, format_count)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device, ctx.surface, &format_count, raw_data(details.formats))
  }

  present_mode_count: u32
  vk.GetPhysicalDeviceSurfacePresentModesKHR(device, ctx.surface, &present_mode_count, nil)

  if present_mode_count != 0 {
    details.present_modes = make([dynamic]vk.PresentModeKHR, present_mode_count)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device, ctx.surface, &present_mode_count, raw_data(details.present_modes))
  }
  return details
}

choose_swap_surface_format :: proc(ctx: ^Context, available_formats: [dynamic]vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
  for available_format in available_formats {
    if available_format.format == vk.Format.B8G8R8_SRGB && available_format.colorSpace == vk.ColorSpaceKHR.COLORSPACE_SRGB_NONLINEAR {
      return available_format
    }
  }
  return available_formats[0]
}

choose_swap_present_mode :: proc(ctx: ^Context, available_present_modes: [dynamic]vk.PresentModeKHR) -> vk.PresentModeKHR {
  for present_mode in available_present_modes {
    if present_mode == vk.PresentModeKHR.MAILBOX {
      return present_mode
    }
  }

  return vk.PresentModeKHR.FIFO
}

choose_swap_extent :: proc(ctx: ^Context, capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
  if capabilities.currentExtent.width != bits.U32_MAX do return capabilities.currentExtent;

  width, height := glfw.GetFramebufferSize(ctx.window)
  actual_extent := vk.Extent2D{
    clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
    clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
  }

  return actual_extent
}

create_image_views :: proc(ctx: ^Context) {
  ctx.swap_chain_image_views = make([dynamic]vk.ImageView, len(ctx.swap_chain_images))
  for i := 0; i < len(ctx.swap_chain_images); i+=1 {
    image_view_create_info : vk.ImageViewCreateInfo
    image_view_create_info.sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO
    image_view_create_info.image = ctx.swap_chain_images[i]
    image_view_create_info.viewType = vk.ImageViewType.D2
    image_view_create_info.format = ctx.swap_chain_image_format
    image_view_create_info.components.r = vk.ComponentSwizzle.IDENTITY
    image_view_create_info.components.g = vk.ComponentSwizzle.IDENTITY
    image_view_create_info.components.b = vk.ComponentSwizzle.IDENTITY
    image_view_create_info.components.a = vk.ComponentSwizzle.IDENTITY
    image_view_create_info.subresourceRange.aspectMask = vk.ImageAspectFlags{vk.ImageAspectFlag.COLOR}
    image_view_create_info.subresourceRange.baseMipLevel = 0
    image_view_create_info.subresourceRange.levelCount = 1
    image_view_create_info.subresourceRange.baseArrayLayer = 0
    image_view_create_info.subresourceRange.layerCount = 1
    if vk.CreateImageView(ctx.logical_device, &image_view_create_info, nil, &ctx.swap_chain_image_views[i]) != vk.Result.SUCCESS {
      panic("Failed to create image views")
    }
  }
}
