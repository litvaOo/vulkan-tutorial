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

create_swap_chain :: proc(ctx: ^Context) {
  swap_chain_support := query_swap_chain_support(ctx, ctx.physical_device)

  surface_format := choose_swap_surface_format(ctx, swap_chain_support.formats)
  present_mode := choose_swap_present_mode(ctx, swap_chain_support.present_modes)
  extent := choose_swap_extent(ctx, &swap_chain_support.capabilities)
  
  image_count := swap_chain_support.capabilities.minImageCount + 1

  if swap_chain_support.capabilities.maxImageCount > 0 &&
    image_count > swap_chain_support.capabilities.maxImageCount {
      image_count = swap_chain_support.capabilities.maxImageCount
    }

  swapchain_create_info : vk.SwapchainCreateInfoKHR
  { 
    swapchain_create_info.sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR
    swapchain_create_info.surface = ctx.surface
    swapchain_create_info.minImageCount = image_count
    swapchain_create_info.imageFormat = surface_format.format
    swapchain_create_info.imageColorSpace = surface_format.colorSpace
    swapchain_create_info.imageExtent = extent
    swapchain_create_info.imageArrayLayers = 1
    swapchain_create_info.imageUsage = vk.ImageUsageFlags{vk.ImageUsageFlag.COLOR_ATTACHMENT}

    {
      indices := find_queue_families(ctx, ctx.physical_device) or_else panic("No queue families")
      if indices.graphics_family != indices.present_family {
        swapchain_create_info.imageSharingMode = vk.SharingMode.CONCURRENT
        swapchain_create_info.queueFamilyIndexCount = 2
        swapchain_create_info.pQueueFamilyIndices = raw_data([]u32{indices.graphics_family, indices.present_family})
      } else {
        swapchain_create_info.imageSharingMode = vk.SharingMode.EXCLUSIVE
        swapchain_create_info.queueFamilyIndexCount = 0
        swapchain_create_info.pQueueFamilyIndices = nil
      }
    }

    swapchain_create_info.preTransform = swap_chain_support.capabilities.currentTransform
    swapchain_create_info.compositeAlpha = vk.CompositeAlphaFlagsKHR{vk.CompositeAlphaFlagKHR.OPAQUE}
    swapchain_create_info.presentMode = present_mode
    swapchain_create_info.clipped = true
    swapchain_create_info.oldSwapchain = 0
  }

  if res := vk.CreateSwapchainKHR(ctx.logical_device, &swapchain_create_info, nil, &ctx.swap_chain); res != vk.Result.SUCCESS {
    panic("Failed to create swapchain")
  }

  vk.GetSwapchainImagesKHR(ctx.logical_device, ctx.swap_chain, &image_count, nil)
  ctx.swap_chain_images = make([dynamic]vk.Image, image_count)
  vk.GetSwapchainImagesKHR(ctx.logical_device, ctx.swap_chain, &image_count, raw_data(ctx.swap_chain_images))
  ctx.swap_chain_image_format = surface_format.format
  ctx.swap_chain_extent = extent
}

create_image_views :: proc(ctx: ^Context) {
  ctx.swap_chain_image_views = make([dynamic]vk.ImageView, len(ctx.swap_chain_images))
  for i := 0; i < len(ctx.swap_chain_images); i+=1 {
    // image_view_create_info : vk.ImageViewCreateInfo
    // image_view_create_info.sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO
    // image_view_create_info.image = ctx.swap_chain_images[i]
    // image_view_create_info.viewType = vk.ImageViewType.D2
    // image_view_create_info.format = ctx.swap_chain_image_format
    // image_view_create_info.components.r = vk.ComponentSwizzle.IDENTITY
    // image_view_create_info.components.g = vk.ComponentSwizzle.IDENTITY
    // image_view_create_info.components.b = vk.ComponentSwizzle.IDENTITY
    // image_view_create_info.components.a = vk.ComponentSwizzle.IDENTITY
    // image_view_create_info.subresourceRange.aspectMask = vk.ImageAspectFlags{vk.ImageAspectFlag.COLOR}
    // image_view_create_info.subresourceRange.baseMipLevel = 0
    // image_view_create_info.subresourceRange.levelCount = 1
    // image_view_create_info.subresourceRange.baseArrayLayer = 0
    // image_view_create_info.subresourceRange.layerCount = 1
    // if vk.CreateImageView(ctx.logical_device, &image_view_create_info, nil, &ctx.swap_chain_image_views[i]) != vk.Result.SUCCESS {
    //   panic("Failed to create image views")
    // }
    ctx.swap_chain_image_views[i] = create_image_view(ctx, ctx.swap_chain_images[i], ctx.swap_chain_image_format, { .COLOR }, ctx.mip_levels)
  }
}

recreate_swap_chain :: proc(ctx: ^Context) {
  width, height: i32 = glfw.GetFramebufferSize(ctx.window)

  for width == 0 || height == 0 {
    width, height = glfw.GetFramebufferSize(ctx.window)
    glfw.WaitEvents()
  }

  vk.DeviceWaitIdle(ctx.logical_device)

  cleanup_swap_chain(ctx)

  create_swap_chain(ctx)
  create_image_views(ctx)
  create_color_resources(ctx)
  create_depth_resources(ctx)
  create_framebuffers(ctx)
}

cleanup_swap_chain :: proc(ctx: ^Context) {
  vk.DestroyImageView(ctx.logical_device, ctx.color_image_view, nil)
  vk.DestroyImage(ctx.logical_device, ctx.color_image, nil)
  vk.FreeMemory(ctx.logical_device, ctx.color_image_memory, nil)
  for framebuffer in ctx.swap_chain_framebuffers {
    vk.DestroyFramebuffer(ctx.logical_device, framebuffer, nil)
  }
  for image_view in ctx.swap_chain_image_views {
    vk.DestroyImageView(ctx.logical_device, image_view, nil)
  }
  vk.DestroySwapchainKHR(ctx.logical_device, ctx.swap_chain, nil)

}
