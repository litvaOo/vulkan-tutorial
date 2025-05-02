package main

import vk "vendor:vulkan"
import "core:os"
import "core:strings"
import "core:fmt"
import "core:strconv"

load_mesh_obj_data :: proc(ctx: ^Context) {
  obj_data := read_file(MODEL_PATH)
  obj_string := strings.clone_from_bytes(obj_data)
  lines := strings.split_lines(obj_string)
  model_vertices := make([dynamic]Vec3)
  model_tex_coords := make([dynamic]Vec2)
  for line in lines {
    if len(line) == 0 do continue
    if line[0] == 'v' {
      if line[1] == ' ' {
        coords := strings.split(line[2:], " ")
        new_vertex := Vec3{
          strconv.parse_f32(coords[0]) or_else panic("Failed to convert"),
          strconv.parse_f32(coords[1]) or_else panic("Failed to convert"),
          strconv.parse_f32(coords[2]) or_else panic("Failed to convert"),
        }
        append(&model_vertices, new_vertex)
      }
      if line[1] == 't' {
        coords := strings.split(line[3:], " ")
        new_tex_coord := Vec2{
          strconv.parse_f32(coords[0]) or_else panic("Failed to convert"),
          strconv.parse_f32(coords[1]) or_else panic("Failed to convert"),
        }
        append(&model_tex_coords, new_tex_coord)
      }
    }
    if line[0] == 'f' {
      new_vertex: Vertex
      new_vertex.color = {1.0, 1.0, 1.0}
      for vertex in strings.split(line[2:], " ") {
        face_indices := strings.split(vertex, "/")
        new_vertex_pos_ind := strconv.parse_u64(face_indices[0]) or_else panic("Failed to convert")
        new_vertex_tex_ind := strconv.parse_u64(face_indices[1]) or_else panic("Failed to convert")
        new_vertex.pos = model_vertices[new_vertex_pos_ind-1]
        new_vertex.tex_coord = model_tex_coords[new_vertex_tex_ind-1]
        new_vertex.tex_coord[1] = 1.0 - new_vertex.tex_coord[1]
        append(&ctx.vertices, new_vertex)
        append(&ctx.indices, u32(len(ctx.indices)))
        }
    }
  }
}
