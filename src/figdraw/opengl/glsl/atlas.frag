#version 330

in vec2 pos;
in vec2 uv;
in vec4 color;
in vec4 sdfParams;
in vec4 sdfRadii;
in float sdfMode;
in vec2 sdfFactors;

uniform vec2 windowFrame;
uniform sampler2D atlasTex;
uniform sampler2D maskTex;
uniform float aaFactor;
uniform bool maskTexEnabled;

out vec4 fragColor;

const int sdfModeAtlas = 0;
const int sdfModeClipAA = 3;
const int sdfModeDropShadow = 7;
const int sdfModeDropShadowAA = 8;
const int sdfModeInsetShadow = 9;
const int sdfModeInsetShadowAnnular = 10;
const int sdfModeAnnular = 11;
const int sdfModeAnnularAA = 12;
const int sdfModeMsdf = 13;
const int sdfModeMtsdf = 14;
const int sdfModeMsdfAnnular = 15;
const int sdfModeMtsdfAnnular = 16;

float median(float a, float b, float c) {
  return max(min(a, b), min(max(a, b), c));
}

float msdfScreenPxRange(float pxRange) {
  vec2 unitRange = vec2(pxRange) / vec2(textureSize(atlasTex, 0));
  vec2 screenTexSize = vec2(1.0) / fwidth(uv);
  return max(0.5 * dot(unitRange, screenTexSize), 1.0);
}

float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
  float rr;
  if (p.x > 0.0) {
    if (p.y > 0.0) {
      rr = r.x;
    } else {
      rr = r.y;
    }
  } else {
    if (p.y > 0.0) {
      rr = r.z;
    } else {
      rr = r.w;
    }
  }

  vec2 q = abs(p) - b + vec2(rr, rr);
  return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rr;
}

float gaussian(float x, float s) {
  return 1.0 / (s * sqrt(6.283185307179586)) *
    exp(-1.0 * (x * x) / (2.0 * s * s));
}

void main() {
  vec2 quadHalfExtents = sdfParams.xy;
  vec2 shapeHalfExtents = sdfParams.zw;

  vec2 p = vec2(
    (uv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (uv.y - 0.5) * 2.0 * quadHalfExtents.y
  );

  float dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, sdfRadii);

  float sdfFactor = sdfFactors.x;
  float sdfSpread = sdfFactors.y;
  int sdfModeInt = int(sdfMode);

  float alpha = 0.0;
  if (sdfModeInt == sdfModeAtlas) {
    vec4 tex = texture(atlasTex, uv);
    fragColor = vec4(
      tex.x * color.x,
      tex.y * color.y,
      tex.z * color.z,
      tex.w * color.w
    );
  } else if (
    sdfModeInt == sdfModeMsdf ||
    sdfModeInt == sdfModeMtsdf ||
    sdfModeInt == sdfModeMsdfAnnular ||
    sdfModeInt == sdfModeMtsdfAnnular
  ) {
    float pxRange = sdfFactors.x;
    float sdThreshold = sdfFactors.y;

    vec4 tex = textureLod(atlasTex, uv, 0.0);
    bool isMtsdf = (sdfModeInt == sdfModeMtsdf || sdfModeInt == sdfModeMtsdfAnnular);
    bool isStroke = (sdfModeInt == sdfModeMsdfAnnular || sdfModeInt == sdfModeMtsdfAnnular);
    float sd = isMtsdf ? tex.w : median(tex.x, tex.y, tex.z);
    float screenPxDistance = msdfScreenPxRange(pxRange) * (sd - sdThreshold);

    if (isStroke) {
      float strokeW = max(sdfParams.y, 0.0);
      float halfW = strokeW * 0.5;
      alpha = clamp(halfW - abs(screenPxDistance) + 0.5, 0.0, 1.0);
    } else {
      alpha = clamp(screenPxDistance + 0.5, 0.0, 1.0);
    }
    fragColor = vec4(color.xyz, color.w * alpha);
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
        float cl = clamp(aaFactor * sd + 0.5, 0.0, 1.0);
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
        float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
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
        float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
    }

    fragColor = vec4(color.x, color.y, color.z, color.w * alpha);
  }

  vec2 normalizedPos = vec2(pos.x / windowFrame.x, 1.0 - pos.y / windowFrame.y);
  if (maskTexEnabled) {
    fragColor.w *= texture(maskTex, normalizedPos).x;
  }
}
