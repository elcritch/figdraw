#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(std430, binding = 0) readonly buffer InputPixels {
  uint pixels[];
} inputPixels;

layout(std430, binding = 1) writeonly buffer OutputPixels {
  uint pixels[];
} outputPixels;

layout(push_constant) uniform PushConstants {
  uint count;
} pc;

void main() {
  uint idx = gl_GlobalInvocationID.x;
  if (idx >= pc.count) {
    return;
  }
  outputPixels.pixels[idx] = inputPixels.pixels[idx];
}
