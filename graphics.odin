package main

import "core:fmt"
import "core:strings"
import "base:runtime"
import "core:slice"
import vk "vendor:vulkan"
import glfw "vendor:glfw"
import glfw_bindings "vendor:glfw/bindings"


device_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

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
  check_device_extension_support(ctx, device) or_return

  swap_chain_support := query_swap_chain_support(ctx, device)
  if (swap_chain_support.formats == nil || swap_chain_support.present_modes == nil) do return false
  return true
}

check_device_extension_support :: proc(ctx: ^Context, device: vk.PhysicalDevice) -> bool {
  extension_count := u32(0)
  vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)
  available_extensions := make([]vk.ExtensionProperties, extension_count)
  vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(available_extensions))

  outer_loop: for device_extension in device_extensions {
    for extension in available_extensions {
      bytes := extension.extensionName
      ext_name := strings.clone_from_bytes(bytes[:len(device_extension)])
      if string(device_extension) == ext_name {
        continue outer_loop
      }
    }
    return false
  }
  return true
}

create_logical_device :: proc (ctx: ^Context) {
  queue_family_indices := find_queue_families(ctx, ctx.physical_device) or_else panic("No queue indices")

  unique_queue_families := make(map[u32]int)
  unique_queue_families[queue_family_indices.graphics_family] = 0
  unique_queue_families[queue_family_indices.present_family] = 0

  queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo)

  for queue in unique_queue_families {
    queue_create_info : vk.DeviceQueueCreateInfo
    queue_create_info.sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO
    queue_create_info.queueFamilyIndex = queue_family_indices.graphics_family
    queue_create_info.queueCount = 1
    queue_priorities := make([^]f32, 1)
    queue_priorities[0] = 1.0
    queue_create_info.pQueuePriorities = queue_priorities
    append(&queue_create_infos, queue_create_info)
  }

  device_features : vk.PhysicalDeviceFeatures
  device_create_info : vk.DeviceCreateInfo
  {
    device_create_info.sType = vk.StructureType.DEVICE_CREATE_INFO
    device_create_info.pQueueCreateInfos = raw_data(queue_create_infos)
    device_create_info.queueCreateInfoCount = u32(len(&queue_create_infos))
    device_create_info.pEnabledFeatures = &device_features
    device_create_info.enabledExtensionCount = u32(len(device_extensions))
    device_create_info.ppEnabledExtensionNames = raw_data(device_extensions)
    device_create_info.enabledLayerCount = 0
  }

  if vk.CreateDevice(ctx.physical_device, &device_create_info, nil, &ctx.logical_device) != vk.Result.SUCCESS {
    panic("Failed to create a logical device")
  }

  vk.GetDeviceQueue(ctx.logical_device, queue_family_indices.graphics_family, 0, &ctx.graphics_queue)
  vk.GetDeviceQueue(ctx.logical_device, queue_family_indices.present_family, 0, &ctx.present_queue)
}

create_surface :: proc (ctx: ^Context) {
  if glfw.CreateWindowSurface(ctx.instance, ctx.window, nil, &ctx.surface) != vk.Result.SUCCESS {
    panic("Failed to create window surface")
  }
}

create_swap_chain :: proc(ctx: ^Context) {
  swap_chain_support := query_swap_chain_support(ctx, ctx.physical_device)

  surface_format := choose_swap_surface_format(ctx, swap_chain_support.formats)
  present_mode := choose_swap_present_mode(ctx, swap_chain_support.present_modes)
  extent := choose_swap_extent(ctx, &swap_chain_support.capabilities)
  
  image_count := swap_chain_support.capabilities.minImageCount + 1

  if swap_chain_support.capabilities.maxImageCount > 0 &&
    image_count > swap_chain_support.capabilities.maxImageCount {
      image_count = swap_chain_support.capabilities.maxImageCount
    }

  swapchain_create_info : vk.SwapchainCreateInfoKHR
  { 
    swapchain_create_info.sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR
    swapchain_create_info.surface = ctx.surface
    swapchain_create_info.minImageCount = image_count
    swapchain_create_info.imageFormat = surface_format.format
    swapchain_create_info.imageColorSpace = surface_format.colorSpace
    swapchain_create_info.imageExtent = extent
    swapchain_create_info.imageArrayLayers = 1
    swapchain_create_info.imageUsage = vk.ImageUsageFlags{vk.ImageUsageFlag.COLOR_ATTACHMENT}

    {
      indices := find_queue_families(ctx, ctx.physical_device) or_else panic("No queue families")
      if indices.graphics_family != indices.present_family {
        swapchain_create_info.imageSharingMode = vk.SharingMode.CONCURRENT
        swapchain_create_info.queueFamilyIndexCount = 2
        swapchain_create_info.pQueueFamilyIndices = raw_data([]u32{indices.graphics_family, indices.present_family})
      } else {
        swapchain_create_info.imageSharingMode = vk.SharingMode.EXCLUSIVE
        swapchain_create_info.queueFamilyIndexCount = 0
        swapchain_create_info.pQueueFamilyIndices = nil
      }
    }

    swapchain_create_info.preTransform = swap_chain_support.capabilities.currentTransform
    swapchain_create_info.compositeAlpha = vk.CompositeAlphaFlagsKHR{vk.CompositeAlphaFlagKHR.OPAQUE}
    swapchain_create_info.presentMode = present_mode
    swapchain_create_info.clipped = true
    swapchain_create_info.oldSwapchain = 0
  }

  if vk.CreateSwapchainKHR(ctx.logical_device, &swapchain_create_info, nil, &ctx.swap_chain) != vk.Result.SUCCESS {
    panic("Failed to create swapchain")
  }

  vk.GetSwapchainImagesKHR(ctx.logical_device, ctx.swap_chain, &image_count, nil)
  ctx.swap_chain_images = make([dynamic]vk.Image, image_count)
  vk.GetSwapchainImagesKHR(ctx.logical_device, ctx.swap_chain, &image_count, raw_data(ctx.swap_chain_images))
  ctx.swap_chain_image_format = surface_format.format
  ctx.swap_chain_extent = extent
}

create_graphics_pipeline :: proc(ctx: ^Context) {
  
}
