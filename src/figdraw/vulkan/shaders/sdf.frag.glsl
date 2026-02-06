#version 450

layout(set = 0, binding = 1) uniform FSUniforms {
  vec2 windowFrame;
  float aaFactor;
  uint maskTexEnabled;
} uFS;

layout(set = 0, binding = 2) uniform sampler2D atlasTex;
layout(set = 0, binding = 3) uniform sampler2D maskTex;

layout(location = 0) in vec2 vPos;
layout(location = 1) in vec2 vUv;
layout(location = 2) in vec4 vColor;
layout(location = 3) in vec4 vSdfParams;
layout(location = 4) in vec4 vSdfRadii;
layout(location = 5) flat in uint vSdfMode;
layout(location = 6) in vec2 vSdfFactors;

layout(location = 0) out vec4 fragColor;

const uint sdfModeAtlas = 0u;
const uint sdfModeDropShadow = 7u;
const uint sdfModeDropShadowAA = 8u;
const uint sdfModeInsetShadow = 9u;
const uint sdfModeInsetShadowAnnular = 10u;
const uint sdfModeAnnular = 11u;
const uint sdfModeAnnularAA = 12u;
const uint sdfModeMsdf = 13u;
const uint sdfModeMtsdf = 14u;
const uint sdfModeMsdfAnnular = 15u;
const uint sdfModeMtsdfAnnular = 16u;

float median(float a, float b, float c) {
  return max(min(a, b), min(max(a, b), c));
}

float msdfScreenPxRange(float pxRange, vec2 uv) {
  vec2 unitRange = vec2(pxRange) / vec2(textureSize(atlasTex, 0));
  vec2 screenTexSize = vec2(1.0) / fwidth(uv);
  return max(0.5 * dot(unitRange, screenTexSize), 1.0);
}

float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
  float rr;
  if (p.x > 0.0) {
    rr = (p.y > 0.0) ? r.x : r.y;
  } else {
    rr = (p.y > 0.0) ? r.z : r.w;
  }

  vec2 q = abs(p) - b + vec2(rr, rr);
  return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rr;
}

float gaussian(float x, float s) {
  return 1.0 / (s * sqrt(6.283185307179586)) *
    exp(-1.0 * (x * x) / (2.0 * s * s));
}

void main() {
  vec2 quadHalfExtents = vSdfParams.xy;
  vec2 shapeHalfExtents = vSdfParams.zw;

  vec2 p = vec2(
    (vUv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (vUv.y - 0.5) * 2.0 * quadHalfExtents.y
  );
  float dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, vSdfRadii);

  float sdfFactor = vSdfFactors.x;
  float sdfSpread = vSdfFactors.y;
  uint sdfModeInt = vSdfMode;
  float alpha = 0.0;

  if (sdfModeInt == sdfModeAtlas) {
    vec4 tex = texture(atlasTex, vUv);
    fragColor = vec4(tex.rgb * vColor.rgb, tex.a * vColor.a);
  } else if (
    sdfModeInt == sdfModeMsdf ||
    sdfModeInt == sdfModeMtsdf ||
    sdfModeInt == sdfModeMsdfAnnular ||
    sdfModeInt == sdfModeMtsdfAnnular
  ) {
    float pxRange = vSdfFactors.x;
    float sdThreshold = vSdfFactors.y;

    vec4 tex = textureLod(atlasTex, vUv, 0.0);
    bool isMtsdf = (sdfModeInt == sdfModeMtsdf || sdfModeInt == sdfModeMtsdfAnnular);
    bool isStroke = (sdfModeInt == sdfModeMsdfAnnular || sdfModeInt == sdfModeMtsdfAnnular);
    float sd = isMtsdf ? tex.w : median(tex.r, tex.g, tex.b);
    float screenPxDistance = msdfScreenPxRange(pxRange, vUv) * (sd - sdThreshold);

    if (isStroke) {
      float strokeW = max(vSdfParams.y, 0.0);
      float halfW = strokeW * 0.5;
      alpha = clamp(halfW - abs(screenPxDistance) + 0.5, 0.0, 1.0);
    } else {
      alpha = clamp(screenPxDistance + 0.5, 0.0, 1.0);
    }
    fragColor = vec4(vColor.rgb, vColor.a * alpha);
  } else {
    float stdDevFactor = 1.0 / 2.2;
    switch (sdfModeInt) {
      case sdfModeAnnular: {
        float f = sdfFactor * 0.5;
        float sd = abs(dist + f) - f;
        alpha = (sd < 0.0) ? 1.0 : 0.0;
        break;
      }
      case sdfModeAnnularAA: {
        float f = sdfFactor * 0.5;
        float sd = abs(dist + f) - f;
        float cl = clamp(uFS.aaFactor * sd + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
      case sdfModeDropShadow: {
        float sd = dist - sdfSpread + 1.0;
        float x = sd / (sdfFactor + 0.5);
        float a = 1.1 * gaussian(x, stdDevFactor);
        alpha = (sd > 0.0) ? min(a, 1.0) : 1.0;
        break;
      }
      case sdfModeDropShadowAA: {
        float cl = clamp(uFS.aaFactor * dist + 0.5, 0.0, 1.0);
        float insideAlpha = 1.0 - cl;
        float sd = dist - sdfSpread + 1.0;
        float x = sd / (sdfFactor + 0.5);
        float a = 1.1 * gaussian(x, stdDevFactor);
        alpha = (sd >= 0.0) ? min(a, 1.0) : insideAlpha;
        break;
      }
      case sdfModeInsetShadow: {
        float sd = dist + sdfSpread + 1.0;
        float x = sd / (sdfFactor + 0.5);
        float a = 1.1 * gaussian(x, stdDevFactor);
        alpha = (sd < 0.0) ? min(a, 1.0) : 1.0;
        break;
      }
      case sdfModeInsetShadowAnnular: {
        float sd = dist + sdfSpread + 1.0;
        float x = sd / (sdfFactor + 0.5);
        float a = 1.1 * gaussian(x, stdDevFactor);
        alpha = (sd < 0.0) ? min(a, 1.0) : 0.0;
        break;
      }
      default: {
        float cl = clamp(uFS.aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
    }

    fragColor = vec4(vColor.rgb, vColor.a * alpha);
  }

  if (uFS.maskTexEnabled != 0u) {
    vec2 normalizedPos = vec2(vPos.x / uFS.windowFrame.x, 1.0 - vPos.y / uFS.windowFrame.y);
    fragColor.a *= texture(maskTex, normalizedPos).r;
  }
}
