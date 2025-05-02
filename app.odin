package main

import glfw "vendor:glfw"
import vk "vendor:vulkan"
import "core:c"
import "core:time"
import "core:fmt"

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
  create_descriptor_set_layout(ctx)
  create_graphics_pipeline(ctx)
  create_command_pool(ctx)
  create_depth_resources(ctx)
  create_framebuffers(ctx)
  create_texture_image(ctx)
  create_texture_image_view(ctx)
  create_texture_sampler(ctx)
  load_mesh_obj_data(ctx)
  create_vertex_buffer(ctx)
  create_index_buffer(ctx)
  create_uniform_buffer(ctx)
  create_descriptor_pool(ctx)
  create_descriptor_sets(ctx)
  create_command_buffers(ctx)
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
  vk.WaitForFences(ctx.logical_device, 1, &ctx.in_flight_fences[ctx.current_frame], true, c.UINT64_MAX)

  image_index: u32
  res := vk.AcquireNextImageKHR(ctx.logical_device, ctx.swap_chain, c.UINT64_MAX, ctx.image_available_semaphores[ctx.current_frame], 0, &image_index)
  if res == vk.Result.ERROR_OUT_OF_DATE_KHR || res == vk.Result.SUBOPTIMAL_KHR || ctx.framebuffer_resized {
    ctx.framebuffer_resized = false
    recreate_swap_chain(ctx)
    return
  } else if res != vk.Result.SUCCESS {
    panic("Failed to acquire next image")
  }

  vk.ResetFences(ctx.logical_device, 1, &ctx.in_flight_fences[ctx.current_frame])

  vk.ResetCommandBuffer(ctx.command_buffers[ctx.current_frame], vk.CommandBufferResetFlags{vk.CommandBufferResetFlag.RELEASE_RESOURCES})
  record_command_buffer(ctx, image_index)

  update_uniform_buffer(ctx)

  wait_semaphores := []vk.Semaphore{ctx.image_available_semaphores[ctx.current_frame]}
  wait_stages := []vk.PipelineStageFlags{vk.PipelineStageFlags{vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT}}
  signal_semaphores := []vk.Semaphore{ctx.render_finished_semaphores[ctx.current_frame]}

  submit_info: vk.SubmitInfo
  {
    submit_info.sType = vk.StructureType.SUBMIT_INFO
    submit_info.waitSemaphoreCount = 1
    submit_info.pWaitSemaphores = raw_data( wait_semaphores )
    submit_info.pWaitDstStageMask = raw_data( wait_stages )
    submit_info.commandBufferCount = 1
    submit_info.pCommandBuffers = &ctx.command_buffers[ctx.current_frame]
    submit_info.signalSemaphoreCount = 1
    submit_info.pSignalSemaphores = raw_data( signal_semaphores )
  }

  if res := vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, ctx.in_flight_fences[ctx.current_frame]); res != vk.Result.SUCCESS {
    fmt.println(res)
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

  ctx.current_frame = (ctx.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
}

cleanup :: proc (ctx: ^Context) {
  cleanup_swap_chain(ctx)

  for i in 0..<MAX_FRAMES_IN_FLIGHT {
    vk.DestroyBuffer(ctx.logical_device, ctx.uniform_buffers[i], nil)
    vk.FreeMemory(ctx.logical_device, ctx.uniform_buffers_memory[i], nil)
  }

  vk.DestroyDescriptorSetLayout(ctx.logical_device, ctx.descriptor_set_layout, nil)
  vk.DestroyPipeline(ctx.logical_device, ctx.graphics_pipeline, nil)
  vk.DestroyPipelineLayout(ctx.logical_device, ctx.pipeline_layout, nil)
  vk.DestroyRenderPass(ctx.logical_device, ctx.render_pass, nil)

  vk.DestroyBuffer(ctx.logical_device, ctx.vertex_buffer, nil)
  vk.FreeMemory(ctx.logical_device, ctx.vertex_buffer_memory, nil)

  for i := u32(0); i < MAX_FRAMES_IN_FLIGHT; i += 1 {
    vk.DestroySemaphore(ctx.logical_device, ctx.image_available_semaphores[i], nil)
    vk.DestroySemaphore(ctx.logical_device, ctx.render_finished_semaphores[i], nil)
    vk.DestroyFence(ctx.logical_device, ctx.in_flight_fences[i], nil)
  }

  vk.DestroyCommandPool(ctx.logical_device, ctx.command_pool, nil)
  vk.DestroyDevice(ctx.logical_device, nil)
  vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
  vk.DestroyInstance(ctx.instance, nil)
  glfw.DestroyWindow(ctx.window)
  glfw.Terminate()
}
