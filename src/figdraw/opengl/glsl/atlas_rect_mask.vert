#version 330

in vec2 vertexPos;
in vec2 vertexUv;
in vec4 vertexColor;
in vec4 vertexFillMidColor;
in vec4 vertexFillStopColor;
in vec4 vertexSdfParams;
in vec4 vertexSdfRadii;
in float vertexSdfMode;
in vec4 vertexSdfFactors;
in vec4 vertexRectMaskParams;
in vec4 vertexRectMaskRadii;
in vec4 vertexRectMaskMatX;
in vec4 vertexRectMaskMatY;
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
in vec4 vertexRectMaskParams2;
in vec4 vertexRectMaskRadii2;
in vec4 vertexRectMaskMat2;
#endif

uniform mat4 proj;

out vec2 pos;
out vec2 uv;
out vec4 color;
out vec4 fillMidColor;
out vec4 fillStopColor;
out vec4 sdfParams;
out vec4 sdfRadii;
out float sdfMode;
out vec4 sdfFactors;
out vec4 rectMaskParams;
out vec4 rectMaskRadii;
out vec4 rectMaskMatX;
out vec4 rectMaskMatY;
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
out vec4 rectMaskParams2;
out vec4 rectMaskRadii2;
out vec4 rectMaskMat2;
#endif

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
  rectMaskParams = vertexRectMaskParams;
  rectMaskRadii = vertexRectMaskRadii;
  rectMaskMatX = vertexRectMaskMatX;
  rectMaskMatY = vertexRectMaskMatY;
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
  rectMaskParams2 = vertexRectMaskParams2;
  rectMaskRadii2 = vertexRectMaskRadii2;
  rectMaskMat2 = vertexRectMaskMat2;
#endif
  gl_Position = proj * vec4(vertexPos.x, vertexPos.y, 0.0, 1.0);
}
