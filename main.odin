package main

import "core:fmt"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

main :: proc () {
  glfw.Init()
  glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
  window := glfw.CreateWindow(800, 600, "Vulkan Window", nil, nil)

  // because odin does not automatically link correct vulkan addresses. sigh
  get_proc_addr := glfw.GetInstanceProcAddress(nil, "vkGetInstanceProcAddr")
  vk.load_proc_addresses_global(get_proc_addr)

  extension_count : u32
  vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)  

  fmt.printf("Got %d extensions\n", extension_count)


  for !glfw.WindowShouldClose(window) {
    glfw.PollEvents()
  }

  glfw.DestroyWindow(window)
  glfw.Terminate()

}
