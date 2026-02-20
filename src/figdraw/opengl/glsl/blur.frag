#version 330

in vec2 uv;

uniform sampler2D srcTex;
uniform vec2 texelStep;
uniform float blurRadius;

out vec4 fragColor;

void main() {
  float radius = clamp(blurRadius, 0.0, 64.0);
  if (radius <= 0.5) {
    fragColor = texture(srcTex, uv);
    return;
  }

  const int tapRadius = 8;
  float sigma = max(0.5 * radius, 0.5);
  float stepPx = max(radius / float(tapRadius), 1.0);

  vec4 acc = vec4(0.0);
  float weightSum = 0.0;
  for (int i = -tapRadius; i <= tapRadius; i++) {
    float x = float(i) * stepPx;
    float w = exp(-0.5 * (x * x) / (sigma * sigma));
    acc += texture(srcTex, uv + texelStep * x) * w;
    weightSum += w;
  }

  fragColor = acc / max(weightSum, 1e-5);
}
