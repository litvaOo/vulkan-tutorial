package main

import "core:fmt"
import vk "vendor:vulkan"
import glfw "vendor:glfw"
import glfw_bindings "vendor:glfw/bindings"

create_vk_instance :: proc(ctx: ^Context) {
  app_info: vk.ApplicationInfo

  {
    app_info.sType = vk.StructureType.APPLICATION_INFO
    app_info.pApplicationName = "Hello Triangle"
    app_info.applicationVersion = vk.MAKE_VERSION(1, 0, 0);
    app_info.pEngineName = "NoEngine"
    app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = vk.API_VERSION_1_4
  }

  create_info: vk.InstanceCreateInfo
  glfw_extension_count : u32
  glfw_extensions := glfw_bindings.GetRequiredInstanceExtensions(&glfw_extension_count)
  {
    create_info.sType = vk.StructureType.INSTANCE_CREATE_INFO
    create_info.pApplicationInfo = &app_info
    create_info.enabledExtensionCount = glfw_extension_count
    create_info.ppEnabledExtensionNames = glfw_extensions
    create_info.enabledLayerCount = 0
  }

  vk_result := vk.CreateInstance(&create_info, nil, &ctx.instance)
  if vk_result != vk.Result.SUCCESS {
    fmt.println(vk_result)
    panic("Failed creation")
  }
}

check_validation_layer_support :: proc (ctx: ^Context) -> bool {
  when ODIN_DEBUG {
    validation_layers : [][256]u8 // uninitialized because no default validation_layers are available
    layer_count : u32
    vk.EnumerateInstanceLayerProperties(&layer_count, nil)

    available_layers := make([^]vk.LayerProperties, layer_count)
    vk.EnumerateInstanceLayerProperties(&layer_count, available_layers)

    for i := u32(0); i < layer_count; i += 1 {
      fmt.printf("%s\n", available_layers[i].layerName)
    }
    fmt.println("Finished layer properties")

    for layer in validation_layers {
      layer_found := false

      for i := u32(0); i < layer_count; i += 1 {
        if available_layers[i].layerName == layer {
          layer_found = true
          break
        }
      }
      
      if !layer_found {
        return false
      }
    }
    return true
  }
  return true
}

pick_physical_device :: proc (ctx: ^Context) {
  device_count : u32
  vk.EnumeratePhysicalDevices(ctx.instance, &device_count, nil)
  if device_count == 0 {
    panic("No vulkan devices")
  }
  devices := make([^]vk.PhysicalDevice, device_count)
  vk.EnumeratePhysicalDevices(ctx.instance, &device_count, devices)
  for i := u32(0); i < device_count; i += 1 {
    if (is_device_suitable(ctx, devices[i])) {
      ctx.physical_device = devices[i]
      break
    }
  }
  if ctx.physical_device == nil {
    panic("No suitable vulkan device")
  }
}

is_device_suitable :: proc (ctx: ^Context, device: vk.PhysicalDevice) -> bool {
  device_properties : vk.PhysicalDeviceProperties
  device_features : vk.PhysicalDeviceFeatures
  vk.GetPhysicalDeviceProperties(device, &device_properties)
  vk.GetPhysicalDeviceFeatures(device, &device_features)

  find_queue_families(ctx, device) or_return
  // using INTEGRATED_GPU instead of DISCRETE_GPU because developing on asahi
  return device_properties.deviceType == vk.PhysicalDeviceType.INTEGRATED_GPU && device_features.geometryShader == true
}


create_logical_device :: proc (ctx: ^Context) {
  queue_create_info : vk.DeviceQueueCreateInfo
  queue_family_indices := find_queue_families(ctx, ctx.physical_device) or_else panic("No queue indices")

  {
    queue_create_info.sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO
    queue_create_info.queueFamilyIndex = queue_family_indices.graphics_family
    queue_create_info.queueCount = 1
    queue_priorities := make([^]f32, 1)
    queue_priorities[0] = 1.0
    queue_create_info.pQueuePriorities = queue_priorities
  }

  device_features : vk.PhysicalDeviceFeatures
  device_create_info : vk.DeviceCreateInfo
  {
    device_create_info.sType = vk.StructureType.DEVICE_CREATE_INFO
    device_create_info.pQueueCreateInfos = &queue_create_info
    device_create_info.queueCreateInfoCount = 1
    device_create_info.pEnabledFeatures = &device_features
    device_create_info.enabledExtensionCount = 0
    device_create_info.enabledLayerCount = 0
  }

  if vk.CreateDevice(ctx.physical_device, &device_create_info, nil, &ctx.logical_device) != vk.Result.SUCCESS {
    panic("Failed to create a logical device")
  }

  vk.GetDeviceQueue(ctx.logical_device, queue_family_indices.graphics_family, 0, &ctx.graphics_queue)
}
