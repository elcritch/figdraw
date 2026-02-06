#version 450

layout(set = 0, binding = 0) uniform VSUniforms {
  mat4 proj;
} uVS;

layout(location = 0) in vec2 vertexPos;
layout(location = 1) in vec2 vertexUv;
layout(location = 2) in vec4 vertexColor;
layout(location = 3) in vec4 vertexSdfParams;
layout(location = 4) in vec4 vertexSdfRadii;
layout(location = 5) in uint vertexSdfMode;
layout(location = 6) in vec2 vertexSdfFactors;

layout(location = 0) out vec2 vPos;
layout(location = 1) out vec2 vUv;
layout(location = 2) out vec4 vColor;
layout(location = 3) out vec4 vSdfParams;
layout(location = 4) out vec4 vSdfRadii;
layout(location = 5) flat out uint vSdfMode;
layout(location = 6) out vec2 vSdfFactors;

void main() {
  vPos = vertexPos;
  vUv = vertexUv;
  vColor = vertexColor;
  vSdfParams = vertexSdfParams;
  vSdfRadii = vertexSdfRadii;
  vSdfMode = vertexSdfMode;
  vSdfFactors = vertexSdfFactors;

  vec4 p = uVS.proj * vec4(vertexPos.xy, 0.0, 1.0);
  p.y = -p.y;
  gl_Position = p;
}
