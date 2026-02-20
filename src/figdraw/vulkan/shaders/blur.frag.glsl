#version 450

layout(set = 0, binding = 0) uniform sampler2D srcTex;

layout(set = 0, binding = 1) uniform BlurUniforms {
  vec2 texelStep;
  float blurRadius;
  float pad0;
} uBlur;

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 fragColor;

void main() {
  float radius = clamp(uBlur.blurRadius, 0.0, 64.0);
  if (radius <= 0.5) {
    fragColor = texture(srcTex, vUv);
    return;
  }

  const int tapRadius = 8;
  float sigma = max(0.5 * radius, 0.5);
  float stepPx = max(radius / float(tapRadius), 1.0);

  vec4 acc = vec4(0.0);
  float weightSum = 0.0;
  for (int i = -tapRadius; i <= tapRadius; ++i) {
    float x = float(i) * stepPx;
    float w = exp(-0.5 * (x * x) / (sigma * sigma));
    acc += texture(srcTex, vUv + uBlur.texelStep * x) * w;
    weightSum += w;
  }

  fragColor = acc / max(weightSum, 1e-5);
}
