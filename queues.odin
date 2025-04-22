package main

import vk "vendor:vulkan"

QueueFamilyIndices :: struct {
  graphics_family: u32
}

find_queue_families :: proc (ctx: ^Context, device: vk.PhysicalDevice) -> (QueueFamilyIndices, bool) {
  indices: QueueFamilyIndices

  queue_family_count := u32(0)
  vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

  queue_families := make([^]vk.QueueFamilyProperties, queue_family_count)
  vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families)

  for i := u32(0); i < queue_family_count; i += 1 {
    if vk.QueueFlag.GRAPHICS in queue_families[i].queueFlags {
      indices.graphics_family = i
      return indices, true
    }
  }

  return indices, false
}
