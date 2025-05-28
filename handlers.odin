package main

import vk "vendor:vulkan"
import "core:fmt"

vk_handler :: proc(res: vk.Result) {
  if res != vk.Result.SUCCESS {
    fmt.printf("Vulkan error: (%d)\n", res)
    panic("Vulkan operation failed")
  }
}
