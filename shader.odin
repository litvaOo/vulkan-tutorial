package main

import vk "vendor:vulkan"

create_shader_module :: proc(ctx: ^Context, code: []u8) -> vk.ShaderModule {
  shader_create_info : vk.ShaderModuleCreateInfo
  shader_create_info.sType = vk.StructureType.SHADER_MODULE_CREATE_INFO
  shader_create_info.codeSize = len(code)
  shader_create_info.pCode = raw_data(transmute([]u32)code)

  shader_module : vk.ShaderModule
  if vk.CreateShaderModule(ctx.logical_device, &shader_create_info, nil, &shader_module) != vk.Result.SUCCESS {
    panic("Failed to create shader")
  }

  return shader_module
}
