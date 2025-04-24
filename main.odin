package main

import "core:fmt"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

Context :: struct {
  window: glfw.WindowHandle,
  instance : vk.Instance,
  enable_validation_layers: bool,
  surface: vk.SurfaceKHR,
  physical_device: vk.PhysicalDevice,
  logical_device: vk.Device,
  graphics_queue: vk.Queue,
  present_queue: vk.Queue,
  swap_chain: vk.SwapchainKHR,
  swap_chain_images: [dynamic]vk.Image,
  swap_chain_image_format: vk.Format,
  swap_chain_extent: vk.Extent2D,
  swap_chain_image_views: [dynamic]vk.ImageView,
}

main :: proc () {
  ctx : Context
  ctx.enable_validation_layers = false
  when ODIN_DEBUG {
    ctx.enable_validation_layers = true
  }
  init_window(&ctx)
  init_vulkan(&ctx)

  extension_count : u32
  vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
  extensions := make([^]vk.ExtensionProperties, extension_count)
  vk.EnumerateInstanceExtensionProperties(nil, &extension_count, extensions)

  for i := u32(0); i < extension_count; i += 1 {
    fmt.printf("%s\n", extensions[i].extensionName)
  }

  fmt.printf("Got %d extensions\n", extension_count)

  main_loop(&ctx)
  cleanup(&ctx)
}
