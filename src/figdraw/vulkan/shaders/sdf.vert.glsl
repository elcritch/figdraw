#version 450

layout(set = 0, binding = 0) uniform VSUniforms {
  mat4 proj;
} uVS;

layout(location = 0) in vec2 vertexPos;
layout(location = 1) in vec2 vertexUv;
layout(location = 2) in vec4 vertexColor;
layout(location = 3) in vec4 vertexFillMidColor;
layout(location = 4) in vec4 vertexFillStopColor;
layout(location = 5) in vec4 vertexSdfParams;
layout(location = 6) in vec4 vertexSdfRadii;
layout(location = 7) in uint vertexSdfMode;
layout(location = 8) in vec2 vertexSdfFactors;
layout(location = 9) in vec4 vertexRectMaskParams;
layout(location = 10) in vec4 vertexRectMaskRadii;
layout(location = 11) in vec4 vertexRectMaskMatX;
layout(location = 12) in vec4 vertexRectMaskMatY;
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
layout(location = 13) in vec4 vertexRectMaskParams2;
layout(location = 14) in vec4 vertexRectMaskRadii2;
layout(location = 15) in vec4 vertexRectMaskMatX2;
layout(location = 16) in vec4 vertexRectMaskMatY2;
#endif

layout(location = 0) out vec2 vPos;
layout(location = 1) out vec2 vUv;
layout(location = 2) out vec4 vColor;
layout(location = 3) out vec4 vFillMidColor;
layout(location = 4) out vec4 vFillStopColor;
layout(location = 5) out vec4 vSdfParams;
layout(location = 6) out vec4 vSdfRadii;
layout(location = 7) flat out uint vSdfMode;
layout(location = 8) out vec2 vSdfFactors;
layout(location = 9) out vec4 vRectMaskParams;
layout(location = 10) out vec4 vRectMaskRadii;
layout(location = 11) out vec4 vRectMaskMatX;
layout(location = 12) out vec4 vRectMaskMatY;
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
layout(location = 13) out vec4 vRectMaskParams2;
layout(location = 14) out vec4 vRectMaskRadii2;
layout(location = 15) out vec4 vRectMaskMatX2;
layout(location = 16) out vec4 vRectMaskMatY2;
#endif

void main() {
  vPos = vertexPos;
  vUv = vertexUv;
  vColor = vertexColor;
  vFillMidColor = vertexFillMidColor;
  vFillStopColor = vertexFillStopColor;
  vSdfParams = vertexSdfParams;
  vSdfRadii = vertexSdfRadii;
  vSdfMode = vertexSdfMode;
  vSdfFactors = vertexSdfFactors;
  vRectMaskParams = vertexRectMaskParams;
  vRectMaskRadii = vertexRectMaskRadii;
  vRectMaskMatX = vertexRectMaskMatX;
  vRectMaskMatY = vertexRectMaskMatY;
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
  vRectMaskParams2 = vertexRectMaskParams2;
  vRectMaskRadii2 = vertexRectMaskRadii2;
  vRectMaskMatX2 = vertexRectMaskMatX2;
  vRectMaskMatY2 = vertexRectMaskMatY2;
#endif

  vec4 p = uVS.proj * vec4(vertexPos.xy, 0.0, 1.0);
  p.y = -p.y;
  gl_Position = p;
}
