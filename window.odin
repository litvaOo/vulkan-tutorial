package main

import glfw "vendor:glfw"
import "core:fmt"
import "base:runtime"

WIDTH :: 800
HEIGHT :: 600

MODEL_PATH :: "models/f22.obj"
TEXTURE_PATH :: "textures/f22.png"


glfw_error_callback :: proc "c" (error: i32, description: cstring ){
  context = runtime.default_context()
  fmt.println(description)
  panic("Failed with error on glfw")
}

framebuffer_resize_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
  ctx := transmute(^Context)glfw.GetWindowUserPointer(window)
  ctx.framebuffer_resized = true
}

init_window :: proc (ctx: ^Context) {
  glfw.SetErrorCallback(glfw_error_callback)
  glfw.Init()
  glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

  ctx.window = glfw.CreateWindow(WIDTH, HEIGHT, "Vulkan", nil, nil)
  glfw.SetWindowUserPointer(ctx.window, ctx)
  glfw.SetFramebufferSizeCallback(ctx.window, framebuffer_resize_callback)
}
