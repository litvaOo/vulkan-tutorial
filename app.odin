package main

import glfw "vendor:glfw"
import vk "vendor:vulkan"
import "core:c"

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
  create_command_pool(ctx)
  create_command_buffer(ctx)
  create_sync_objects(ctx)
}

main_loop :: proc(ctx: ^Context) {
  for !glfw.WindowShouldClose(ctx.window) {
    glfw.PollEvents()
    draw_frame(ctx)
  }

  vk.DeviceWaitIdle(ctx.logical_device)
}

draw_frame :: proc(ctx: ^Context) {
  vk.WaitForFences(ctx.logical_device, 1, &ctx.in_flight_fence, true, c.UINT64_MAX)
  vk.ResetFences(ctx.logical_device, 1, &ctx.in_flight_fence)

  image_index: u32
  vk.AcquireNextImageKHR(ctx.logical_device, ctx.swap_chain, c.UINT64_MAX, ctx.image_available_semaphore, 0, &image_index)

  vk.ResetCommandBuffer(ctx.command_buffer, vk.CommandBufferResetFlags{vk.CommandBufferResetFlag.RELEASE_RESOURCES})
  record_command_buffer(ctx, image_index)

  wait_semaphores := []vk.Semaphore{ctx.image_available_semaphore}
  wait_stages := []vk.PipelineStageFlags{vk.PipelineStageFlags{vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT}}
  signal_semaphores := []vk.Semaphore{ctx.render_finished_semaphore}

  submit_info: vk.SubmitInfo
  {
    submit_info.sType = vk.StructureType.SUBMIT_INFO
    submit_info.waitSemaphoreCount = 1
    submit_info.pWaitSemaphores = raw_data( wait_semaphores )
    submit_info.pWaitDstStageMask = raw_data( wait_stages )
    submit_info.commandBufferCount = 1
    submit_info.pCommandBuffers = &ctx.command_buffer
    submit_info.signalSemaphoreCount = 1
    submit_info.pSignalSemaphores = raw_data( signal_semaphores )
  }

  if vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, ctx.in_flight_fence) != vk.Result.SUCCESS {
    panic("Failed to submit queue")
  }

  swap_chains := []vk.SwapchainKHR{ctx.swap_chain}
  present_info: vk.PresentInfoKHR
  {
    present_info.sType = vk.StructureType.PRESENT_INFO_KHR
    present_info.waitSemaphoreCount = 1
    present_info.pWaitSemaphores = raw_data( signal_semaphores )
    present_info.swapchainCount = 1
    present_info.pSwapchains = raw_data( swap_chains )
    present_info.pImageIndices = &image_index
    present_info.pResults = nil
  }

  if vk.QueuePresentKHR(ctx.present_queue, &present_info) != vk.Result.SUCCESS {
    panic("Failed to present")
  }
}

cleanup :: proc (ctx: ^Context) {
  vk.DestroySemaphore(ctx.logical_device, ctx.image_available_semaphore, nil)
  vk.DestroySemaphore(ctx.logical_device, ctx.render_finished_semaphore, nil)
  vk.DestroyFence(ctx.logical_device, ctx.in_flight_fence, nil)
  vk.DestroyCommandPool(ctx.logical_device, ctx.command_pool, nil)
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
