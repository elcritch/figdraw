#version 100

precision highp float;

attribute vec2 vertexPos;
attribute vec2 vertexUv;

varying vec2 uv;

void main() {
  uv = vertexUv;
  gl_Position = vec4(vertexPos, 0.0, 1.0);
}
