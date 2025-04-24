package main

import glfw "vendor:glfw"
import "core:fmt"
import "base:runtime"

WIDTH :: 800
HEIGHT :: 600



init_window :: proc (ctx: ^Context) {
  glfw_error_callback : glfw.ErrorProc
  glfw_error_callback = proc "c" (error: i32, description: cstring ){
    context = runtime.default_context()
    fmt.println(description)
    panic("Failed with error on glfw")
  }
  glfw.SetErrorCallback(glfw_error_callback)
  glfw.Init()
  glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
  glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

  ctx.window = glfw.CreateWindow(WIDTH, HEIGHT, "Vulkan", nil, nil)
}
