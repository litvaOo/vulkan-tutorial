package main

import vk "vendor:vulkan"

QueueFamilyIndices :: struct {
  graphics_family: u32,
  present_family: u32,
}

find_queue_families :: proc (ctx: ^Context, device: vk.PhysicalDevice) -> (QueueFamilyIndices, bool) {
  indices: QueueFamilyIndices

  queue_family_count := u32(0)
  vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

  queue_families := make([^]vk.QueueFamilyProperties, queue_family_count)
  vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families)

  graphics_index := false
  present_support : b32 = false
  for i := u32(0); i < queue_family_count; i += 1 {
    if vk.QueueFlag.GRAPHICS in queue_families[i].queueFlags {
      indices.graphics_family = i
      graphics_index = true
    }

    vk.GetPhysicalDeviceSurfaceSupportKHR(device, i, ctx.surface, &present_support)
    if present_support {
      indices.present_family = i  
    }

    if graphics_index && present_support do break
  }

  return indices, graphics_index && present_support
}
