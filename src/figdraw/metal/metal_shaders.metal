#include <metal_stdlib>
using namespace metal;

struct VSOut {
  float4 position [[position]];
  float2 pos;
  float2 uv;
  float4 color;
  float4 sdfParams;
  float4 sdfRadii;
  float sdfMode;
  float2 sdfFactors;
};

struct VSUniforms {
  float4x4 proj;
};

struct FSUniforms {
  float2 windowFrame;
  float aaFactor;
  uint maskTexEnabled;
};

constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);

float median(float a, float b, float c) {
  return max(min(a, b), min(max(a, b), c));
}

float msdfScreenPxRange(texture2d<float> atlasTex, float2 uv, float pxRange) {
  float2 unitRange = float2(pxRange) /
    float2((float)atlasTex.get_width(), (float)atlasTex.get_height());
  float2 screenTexSize = float2(1.0) / fwidth(uv);
  return max(0.5 * dot(unitRange, screenTexSize), 1.0);
}

float sdRoundedBox(float2 p, float2 b, float4 r) {
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

  float2 q = abs(p) - b + float2(rr, rr);
  return min(max(q.x, q.y), 0.0) + length(max(q, float2(0.0))) - rr;
}

float gaussian(float x, float s) {
  return 1.0 / (s * sqrt(6.283185307179586)) *
    exp(-1.0 * (x * x) / (2.0 * s * s));
}

vertex VSOut vs_main(
    uint vid [[vertex_id]],
    const device float2* positions [[buffer(0)]],
    const device float2* uvs [[buffer(1)]],
    const device uchar4* colors [[buffer(2)]],
    const device float4* sdfParams [[buffer(3)]],
    const device float4* sdfRadii [[buffer(4)]],
    const device ushort* sdfMode [[buffer(5)]],
    const device float2* sdfFactors [[buffer(6)]],
    constant VSUniforms& u [[buffer(7)]]) {
  VSOut out;
  float2 p = positions[vid];
  out.position = u.proj * float4(p.x, p.y, 0.0, 1.0);
  out.pos = p;
  out.uv = uvs[vid];
  out.color = float4(colors[vid]) / 255.0;
  out.sdfParams = sdfParams[vid];
  out.sdfRadii = sdfRadii[vid];
  out.sdfMode = float(sdfMode[vid]);
  out.sdfFactors = sdfFactors[vid];
  return out;
}

fragment float4 fs_main(
    VSOut in [[stage_in]],
    constant FSUniforms& u [[buffer(0)]],
    texture2d<float> atlasTex [[texture(0)]],
    texture2d<float> maskTex [[texture(1)]]) {
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

  float2 quadHalfExtents = in.sdfParams.xy;
  float2 shapeHalfExtents = in.sdfParams.zw;

  float2 p = float2(
    (in.uv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (in.uv.y - 0.5) * 2.0 * quadHalfExtents.y
  );

  float dist = sdRoundedBox(float2(p.x, -p.y), shapeHalfExtents, in.sdfRadii);

  float sdfFactor = in.sdfFactors.x;
  float sdfSpread = in.sdfFactors.y;
  int sdfModeInt = int(in.sdfMode);

  float4 fragColor;
  float alpha = 0.0;
  if (sdfModeInt == sdfModeAtlas) {
    float4 tex = atlasTex.sample(s, in.uv);
    fragColor = float4(
      tex.x * in.color.x,
      tex.y * in.color.y,
      tex.z * in.color.z,
      tex.w * in.color.w
    );
  } else if (
    sdfModeInt == sdfModeMsdf ||
    sdfModeInt == sdfModeMtsdf ||
    sdfModeInt == sdfModeMsdfAnnular ||
    sdfModeInt == sdfModeMtsdfAnnular
  ) {
    float pxRange = in.sdfFactors.x;
    float sdThreshold = in.sdfFactors.y;

    float4 tex = atlasTex.sample(s, in.uv, level(0.0));
    bool isMtsdf = (sdfModeInt == sdfModeMtsdf || sdfModeInt == sdfModeMtsdfAnnular);
    bool isStroke =
      (sdfModeInt == sdfModeMsdfAnnular || sdfModeInt == sdfModeMtsdfAnnular);
    float sd = isMtsdf ? tex.w : median(tex.x, tex.y, tex.z);
    float screenPxDistance =
      msdfScreenPxRange(atlasTex, in.uv, pxRange) * (sd - sdThreshold);

    if (isStroke) {
      float strokeW = max(in.sdfParams.y, 0.0);
      float halfW = strokeW * 0.5;
      alpha = clamp(halfW - abs(screenPxDistance) + 0.5, 0.0, 1.0);
    } else {
      alpha = clamp(screenPxDistance + 0.5, 0.0, 1.0);
    }
    fragColor = float4(in.color.xyz, in.color.w * alpha);
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
        float cl = clamp(u.aaFactor * sd + 0.5, 0.0, 1.0);
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
        float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
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
        float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
    }

    fragColor = float4(in.color.x, in.color.y, in.color.z, in.color.w * alpha);
  }

  float2 normalizedPos =
    float2(in.pos.x / u.windowFrame.x, in.pos.y / u.windowFrame.y);
  if (u.maskTexEnabled != 0) {
    fragColor.w *= maskTex.sample(s, normalizedPos).x;
  }
  return fragColor;
}

fragment float4 fs_mask(
    VSOut in [[stage_in]],
    constant FSUniforms& u [[buffer(0)]],
    texture2d<float> atlasTex [[texture(0)]],
    texture2d<float> maskTex [[texture(1)]]) {
  const int sdfModeAtlas = 0;

  float alpha;
  int sdfModeInt = int(in.sdfMode);
  if (sdfModeInt == sdfModeAtlas) {
    alpha = atlasTex.sample(s, in.uv).a * in.color.a;
  } else {
    float2 quadHalfExtents = in.sdfParams.xy;
    float2 shapeHalfExtents = in.sdfParams.zw;
    float2 p = float2(
      (in.uv.x - 0.5) * 2.0 * quadHalfExtents.x,
      (in.uv.y - 0.5) * 2.0 * quadHalfExtents.y
    );
    float dist = sdRoundedBox(float2(p.x, -p.y), shapeHalfExtents, in.sdfRadii);
    float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
    alpha = (1.0 - cl) * in.color.a;
  }

  float2 normalizedPos =
    float2(in.pos.x / u.windowFrame.x, in.pos.y / u.windowFrame.y);
  if (u.maskTexEnabled != 0) {
    alpha *= maskTex.sample(s, normalizedPos).r;
  }
  return float4(alpha);
}

struct BlitVSOut {
  float4 position [[position]];
  float2 uv;
};

vertex BlitVSOut vs_blit(uint vid [[vertex_id]]) {
  // Fullscreen triangle.
  float2 pos;
  float2 uv;
  if (vid == 0) { pos = float2(-1.0, -1.0); uv = float2(0.0, 1.0); }
  else if (vid == 1) { pos = float2(3.0, -1.0); uv = float2(2.0, 1.0); }
  else { pos = float2(-1.0, 3.0); uv = float2(0.0, -1.0); }
  BlitVSOut out;
  out.position = float4(pos, 0.0, 1.0);
  out.uv = uv;
  return out;
}

fragment float4 fs_blit(
    BlitVSOut in [[stage_in]],
    texture2d<float> src [[texture(0)]]) {
  return src.sample(s, in.uv);
}
