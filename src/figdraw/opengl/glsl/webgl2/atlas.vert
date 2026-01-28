#version 300 es

precision highp float;

in vec2 vertexPos;
in vec2 vertexUv;
in vec4 vertexColor;
in vec4 vertexSdfParams;
in vec4 vertexSdfRadii;
in float vertexSdfMode;
in vec2 vertexSdfFactors;

uniform mat4 proj;

out vec2 pos;
out vec2 uv;
out vec4 color;
out vec4 sdfParams;
out vec4 sdfRadii;
out float sdfMode;
out vec2 sdfFactors;

void main() {
  pos = vertexPos;
  uv = vertexUv;
  color = vertexColor;
  sdfParams = vertexSdfParams;
  sdfRadii = vertexSdfRadii;
  sdfMode = vertexSdfMode;
  sdfFactors = vertexSdfFactors;
  gl_Position = proj * vec4(vertexPos.x, vertexPos.y, 0.0, 1.0);
}
