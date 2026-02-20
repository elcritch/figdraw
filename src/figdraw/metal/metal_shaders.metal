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

float shadowProfile(float sd, float blurRadius) {
  // CSS-like calibration: sigma ~= blurRadius / 2
  float sigma = max(0.5 * blurRadius, 0.5);
  float z = sd / sigma;
  return exp(-0.5 * z * z);
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
    texture2d<float> maskTex [[texture(1)]],
    texture2d<float> backdropTex [[texture(2)]]) {
  const int sdfModeAtlas = 0;
  const int sdfModeClipAA = 3;
  const int sdfModeDropShadow = 7;
  const int sdfModeDropShadowAA = 8;
  const int sdfModeInsetShadow = 9;
  const int sdfModeAnnular = 11;
  const int sdfModeAnnularAA = 12;
  const int sdfModeMsdf = 13;
  const int sdfModeMtsdf = 14;
  const int sdfModeMsdfAnnular = 15;
  const int sdfModeMtsdfAnnular = 16;
  const int sdfModeBackdropBlur = 17;

  int sdfModeInt = int(in.sdfMode);
  float2 quadHalfExtents = in.sdfParams.xy;
  bool insetMode = (sdfModeInt == sdfModeInsetShadow);
  float2 shapeHalfExtents = insetMode ? quadHalfExtents : in.sdfParams.zw;

  float2 p = float2(
    (in.uv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (in.uv.y - 0.5) * 2.0 * quadHalfExtents.y
  );

  float dist = sdRoundedBox(float2(p.x, -p.y), shapeHalfExtents, in.sdfRadii);

  float sdfFactor = in.sdfFactors.x;
  float sdfSpread = in.sdfFactors.y;

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
        float sd = dist - sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        alpha = (sd > 0.0) ? min(a, 1.0) : 1.0;
        break;
      }
      case sdfModeDropShadowAA: {
        float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
        float insideAlpha = 1.0 - cl;
        float sd = dist - sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        alpha = (sd >= 0.0) ? min(a, 1.0) : insideAlpha;
        break;
      }
      case sdfModeInsetShadow: {
        float2 qClip = float2(p.x, -p.y);
        float2 shadowOffset = float2(in.sdfParams.z, -in.sdfParams.w);
        float2 qShadow = qClip - shadowOffset;
        float clipDist = sdRoundedBox(qClip, quadHalfExtents, in.sdfRadii);
        float clipAlpha = 1.0 - clamp(u.aaFactor * clipDist + 0.5, 0.0, 1.0);
        float shadowDist = sdRoundedBox(qShadow, quadHalfExtents, in.sdfRadii);
        float sd = shadowDist + sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        float insetAlpha = (sd < 0.0) ? min(a, 1.0) : 1.0;
        alpha = clipAlpha * insetAlpha;
        break;
      }
      case sdfModeBackdropBlur: {
        float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        float2 normalizedPos = float2(in.pos.x / u.windowFrame.x, in.pos.y / u.windowFrame.y);
        float4 blur = backdropTex.sample(s, normalizedPos);
        fragColor = float4(blur.xyz, blur.w * alpha);
        break;
      }
      default: {
        float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
    }

    if (sdfModeInt != sdfModeBackdropBlur) {
      fragColor = float4(in.color.x, in.color.y, in.color.z, in.color.w * alpha);
    }
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

struct BlurUniforms {
  float2 texelStep;
  float blurRadius;
  float pad0;
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

fragment float4 fs_blur(
    BlitVSOut in [[stage_in]],
    constant BlurUniforms& u [[buffer(0)]],
    texture2d<float> src [[texture(0)]]) {
  float radius = clamp(u.blurRadius, 0.0, 64.0);
  if (radius <= 0.5) {
    return src.sample(s, in.uv);
  }

  const int tapRadius = 8;
  float sigma = max(0.5 * radius, 0.5);
  float stepPx = max(radius / float(tapRadius), 1.0);

  float4 acc = float4(0.0);
  float weightSum = 0.0;
  for (int i = -tapRadius; i <= tapRadius; ++i) {
    float x = float(i) * stepPx;
    float w = exp(-0.5 * (x * x) / (sigma * sigma));
    acc += src.sample(s, in.uv + u.texelStep * x) * w;
    weightSum += w;
  }
  return acc / max(weightSum, 1e-5);
}
