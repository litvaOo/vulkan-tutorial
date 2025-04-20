package main

import glfw "vendor:glfw"

WIDTH :: 800
HEIGHT :: 600

init_window :: proc (ctx: ^Context) {
  glfw.Init()
  glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
  glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

  ctx.window = glfw.CreateWindow(WIDTH, HEIGHT, "Vulkan", nil, nil)
}
