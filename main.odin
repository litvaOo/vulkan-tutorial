package main

import "core:time"
import "core:math/linalg"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: u32(2)

when ODIN_OS == .Darwin {
  // just.. i just hate this device
	@(require, extra_linker_flags = "-rpath /opt/homebrew/lib -rpath /usr/local/lib")
	foreign import __ "system:System.framework"
}

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
  descriptor_set_layout: vk.DescriptorSetLayout,
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
  index_buffer: vk.Buffer,
  index_buffer_memory: vk.DeviceMemory,
  uniform_buffers: [dynamic]vk.Buffer,
  uniform_buffers_memory: [dynamic]vk.DeviceMemory,
  uniform_buffers_mapped: [dynamic]rawptr,
  start_time: time.Time,
  descriptor_pool: vk.DescriptorPool,
  descriptor_sets: [dynamic]vk.DescriptorSet,
  ubo: UBO,
  mip_levels: u32,
  texture_image: vk.Image,
  texture_image_memory: vk.DeviceMemory,
  texture_image_view: vk.ImageView,
  texture_sampler: vk.Sampler,
  depth_image: vk.Image,
  depth_image_memory: vk.DeviceMemory,
  depth_image_view: vk.ImageView,
  vertices: [dynamic]Vertex,
  indices: [dynamic]u32,
  msaa_samples: vk.SampleCountFlags,
  color_image: vk.Image,
  color_image_memory: vk.DeviceMemory,
  color_image_view: vk.ImageView,
}

main :: proc () {
  ctx : Context
  ctx.current_frame = 0
  ctx.enable_validation_layers = false
  ctx.framebuffer_resized = false
  ctx.start_time = time.now()
  ctx.mip_levels = 1
  ctx.msaa_samples = {._1}
  when ODIN_DEBUG {
    ctx.enable_validation_layers = true
  }
  init_window(&ctx)
  init_vulkan(&ctx)

  main_loop(&ctx)
  cleanup(&ctx)
}
