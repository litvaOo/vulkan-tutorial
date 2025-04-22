package main

import glfw "vendor:glfw"
import vk "vendor:vulkan"

init_vulkan :: proc (ctx: ^Context) {
  // because odin does not automatically link correct vulkan addresses. sigh
  get_proc_addr := glfw.GetInstanceProcAddress(nil, "vkGetInstanceProcAddr")
  vk.load_proc_addresses_global(get_proc_addr)
  if !check_validation_layer_support(ctx) {
    panic("Missing required layers")
  }
  create_vk_instance(ctx)
  vk.load_proc_addresses_instance(ctx.instance)
  pick_physical_device(ctx)
  create_logical_device(ctx)
  vk.load_proc_addresses_device(ctx.logical_device)
}

main_loop :: proc(ctx: ^Context) {
  for !glfw.WindowShouldClose(ctx.window) {
    glfw.PollEvents()
  }

}

cleanup :: proc (ctx: ^Context) {
  vk.DestroyDevice(ctx.logical_device, nil)
  vk.DestroyInstance(ctx.instance, nil)
  glfw.DestroyWindow(ctx.window)
  glfw.Terminate()
}
