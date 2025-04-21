package main

import "core:fmt"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

Context :: struct {
  window: glfw.WindowHandle,
  instance : vk.Instance,
  enable_validation_layers: bool,
}

main :: proc () {
  ctx : Context
  ctx.enable_validation_layers = false
  when ODIN_DEBUG {
    ctx.enable_validation_layers = true
  }
  init_window(&ctx)
  init_vulkan(&ctx)

  extension_count : u32
  vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
  extensions := make([^]vk.ExtensionProperties, extension_count)
  vk.EnumerateInstanceExtensionProperties(nil, &extension_count, extensions)

  for i := u32(0); i < extension_count; i += 1 {
    fmt.printf("%s\n", extensions[i].extensionName)
  }

  fmt.printf("Got %d extensions\n", extension_count)

  main_loop(&ctx)
  cleanup(&ctx)
}
