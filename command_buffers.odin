package main

import vk "vendor:vulkan"

begin_single_time_commands :: proc(ctx: ^Context) -> vk.CommandBuffer {
  allocate_info: vk.CommandBufferAllocateInfo
  {
    allocate_info.sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO
    allocate_info.level = vk.CommandBufferLevel.PRIMARY
    allocate_info.commandPool = ctx.command_pool
    allocate_info.commandBufferCount = 1
  }

  command_buffer: vk.CommandBuffer
  vk.AllocateCommandBuffers(ctx.logical_device, &allocate_info, &command_buffer)

  begin_info: vk.CommandBufferBeginInfo
  {
    begin_info.sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO
    begin_info.flags = { vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT }
  }

  vk.BeginCommandBuffer(command_buffer, &begin_info)
  
  return command_buffer
}

end_single_time_commands :: proc(ctx: ^Context, command_buffer: ^vk.CommandBuffer) {
  vk.EndCommandBuffer(command_buffer^)

  submit_info: vk.SubmitInfo
  {
    submit_info.sType = vk.StructureType.SUBMIT_INFO
    submit_info.commandBufferCount = 1
    submit_info.pCommandBuffers = command_buffer
  }

  vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, 0)
  vk.QueueWaitIdle(ctx.graphics_queue)
  vk.FreeCommandBuffers(ctx.logical_device, ctx.command_pool, 1, command_buffer)
}
