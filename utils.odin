package main

import "core:os"

read_file :: proc(filename: string) -> []u8{
  file_handle := os.open(filename) or_else panic("Failed to find file")
  file_size := os.file_size(file_handle) or_else panic("Failed to get file size")
  buffer := make([]u8, file_size)
  total_read := os.read(file_handle, buffer) or_else panic("Failed to read file")
  return buffer
}
