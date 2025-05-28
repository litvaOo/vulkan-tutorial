package main

import "core:os"

read_file :: proc(filename: string) -> []u8{
  return os.read_entire_file_or_err(filename) or_else panic("Failed to read file ")
}
