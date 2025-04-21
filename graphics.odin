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
