package main

import "core:fmt"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT : u32 = 2

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
  render_pass: vk.RenderPass,
  pipeline_layout : vk.PipelineLayout,
  graphics_pipeline: vk.Pipeline,
  swap_chain_framebuffers: [dynamic]vk.Framebuffer,
  command_pool: vk.CommandPool,
  command_buffers: [dynamic]vk.CommandBuffer,
  image_available_semaphores: [dynamic]vk.Semaphore,
  render_finished_semaphores: [dynamic]vk.Semaphore,
  in_flight_fences: [dynamic]vk.Fence,
  current_frame: u32,
  framebuffer_resized: bool,
  vertex_buffer: vk.Buffer,
  vertex_buffer_memory: vk.DeviceMemory,
}

main :: proc () {
  ctx : Context
  ctx.current_frame = 0
  ctx.enable_validation_layers = false
  ctx.framebuffer_resized = false
  when ODIN_DEBUG {
    ctx.enable_validation_layers = true
  }
  init_window(&ctx)
  init_vulkan(&ctx)

  main_loop(&ctx)
  cleanup(&ctx)
}
