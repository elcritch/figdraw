#version 330

in vec2 vertexPos;
in vec2 vertexUv;

out vec2 uv;

void main() {
  uv = vertexUv;
  gl_Position = vec4(vertexPos, 0.0, 1.0);
}
