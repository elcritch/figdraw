import std/os

const metalShaderSource* =
  staticRead(currentSourcePath().parentDir / "metal_shaders.metal")
