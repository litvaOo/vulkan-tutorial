package main

import glfw "vendor:glfw"
import vk "vendor:vulkan"

init_vulkan :: proc (ctx: ^Context) {
  // because odin does not automatically link correct vulkan addresses. sigh
  get_proc_addr := glfw.GetInstanceProcAddress(nil, "vkGetInstanceProcAddr")
  vk.load_proc_addresses_global(get_proc_addr)
  if !check_validation_layer_support(ctx) {
    panic("Missing required layers")
  }
  create_vk_instance(ctx)
  vk.load_proc_addresses_instance(ctx.instance)
  create_surface(ctx)
  pick_physical_device(ctx)
  create_logical_device(ctx)
  vk.load_proc_addresses_device(ctx.logical_device)
  create_swap_chain(ctx)
  create_image_views(ctx)
  create_render_pass(ctx)
  create_graphics_pipeline(ctx)
  create_framebuffers(ctx)
}

main_loop :: proc(ctx: ^Context) {
  for !glfw.WindowShouldClose(ctx.window) {
    glfw.PollEvents()
  }

  vk.DeviceWaitIdle(ctx.logical_device)
}

cleanup :: proc (ctx: ^Context) {
  for framebuffer in ctx.swap_chain_framebuffers {
    vk.DestroyFramebuffer(ctx.logical_device, framebuffer, nil)
  }
  vk.DestroyPipeline(ctx.logical_device, ctx.graphics_pipeline, nil)
  vk.DestroyPipelineLayout(ctx.logical_device, ctx.pipeline_layout, nil)
  vk.DestroyRenderPass(ctx.logical_device, ctx.render_pass, nil)
  for image_view in ctx.swap_chain_image_views {
    vk.DestroyImageView(ctx.logical_device, image_view, nil)
  }
  vk.DestroySwapchainKHR(ctx.logical_device, ctx.swap_chain, nil)
  vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
  vk.DestroyDevice(ctx.logical_device, nil)
  vk.DestroyInstance(ctx.instance, nil)
  glfw.DestroyWindow(ctx.window)
  glfw.Terminate()
}
