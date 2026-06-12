#version 100

precision highp float;

attribute vec2 vertexPos;
attribute vec2 vertexUv;
attribute vec4 vertexColor;
attribute vec4 vertexFillMidColor;
attribute vec4 vertexFillStopColor;
attribute vec4 vertexSdfParams;
attribute vec4 vertexSdfRadii;
attribute float vertexSdfMode;
attribute vec2 vertexSdfFactors;
attribute float vertexSubpixelShift;
attribute vec4 vertexRectMaskParams;
attribute vec4 vertexRectMaskRadii;
attribute vec4 vertexRectMaskMatX;
attribute vec4 vertexRectMaskMatY;

uniform mat4 proj;

varying vec2 pos;
varying vec2 uv;
varying vec4 color;
varying vec4 fillMidColor;
varying vec4 fillStopColor;
varying vec4 sdfParams;
varying vec4 sdfRadii;
varying float sdfMode;
varying vec2 sdfFactors;
varying float subpixelShift;
varying vec4 rectMaskParams;
varying vec4 rectMaskRadii;
varying vec4 rectMaskMatX;
varying vec4 rectMaskMatY;

void main() {
  pos = vertexPos;
  uv = vertexUv;
  color = vertexColor;
  fillMidColor = vertexFillMidColor;
  fillStopColor = vertexFillStopColor;
  sdfParams = vertexSdfParams;
  sdfRadii = vertexSdfRadii;
  sdfMode = vertexSdfMode;
  sdfFactors = vertexSdfFactors;
  subpixelShift = vertexSubpixelShift;
  rectMaskParams = vertexRectMaskParams;
  rectMaskRadii = vertexRectMaskRadii;
  rectMaskMatX = vertexRectMaskMatX;
  rectMaskMatY = vertexRectMaskMatY;
  gl_Position = proj * vec4(vertexPos.x, vertexPos.y, 0.0, 1.0);
}
