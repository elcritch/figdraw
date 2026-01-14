#version 100

precision highp float;

attribute vec2 vertexPos;
attribute vec2 vertexUv;
attribute vec4 vertexColor;
attribute vec4 vertexSdfParams;
attribute vec4 vertexSdfRadii;
attribute float vertexSdfMode;
attribute vec2 vertexSdfFactors;

uniform mat4 proj;

varying vec2 pos;
varying vec2 uv;
varying vec4 color;
varying vec4 sdfParams;
varying vec4 sdfRadii;
varying float sdfMode;
varying vec2 sdfFactors;

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
