#include <metal_stdlib>
using namespace metal;

struct VSOut {
  float4 position [[position]];
  float2 pos;
  float2 uv;
  float4 color;
  float4 fillMidColor;
  float4 fillStopColor;
  float4 sdfParams;
  float4 sdfRadii;
  float sdfMode;
  float2 sdfFactors;
};

struct RectMaskVSOut {
  float4 position [[position]];
  float2 pos;
  float2 uv;
  float4 color;
  float4 fillMidColor;
  float4 fillStopColor;
  float4 sdfParams;
  float4 sdfRadii;
  float sdfMode;
  float2 sdfFactors;
  float4 rectMaskParams;
  float4 rectMaskRadii;
  float4 rectMaskMatX;
  float4 rectMaskMatY;
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

float dot2(float2 v) {
  return dot(v, v);
}

float signedPowThird(float x) {
  return (x < 0.0 ? -1.0 : 1.0) * pow(abs(x), 1.0 / 3.0);
}

float2 bezierDistanceT(float2 pos, float2 A, float2 B, float2 C) {
  float2 a = B - A;
  float2 b = A - 2.0 * B + C;
  float bb = dot(b, b);
  if (bb <= 0.000001) {
    float2 ba = C - A;
    float h = clamp(dot(pos - A, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return float2(length(pos - (A + ba * h)), h);
  }

  float2 c = a * 2.0;
  float2 d = A - pos;
  float kk = 1.0 / bb;
  float kx = kk * dot(a, b);
  float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
  float kz = kk * dot(d, a);
  float p = ky - kx * kx;
  float p3 = p * p * p;
  float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
  float h = q * q + 4.0 * p3;
  float res = 0.0;
  float closestT = 0.0;
  if (h >= 0.0) {
    h = sqrt(h);
    float2 x = float2((h - q) / 2.0, (-h - q) / 2.0);
    float2 roots = float2(signedPowThird(x.x), signedPowThird(x.y));
    float t = clamp(roots.x + roots.y - kx, 0.0, 1.0);
    closestT = t;
    res = dot2(d + (c + b * t) * t);
  } else {
    float z = sqrt(-p);
    float v = acos(clamp(q / (p * z * 2.0), -1.0, 1.0)) / 3.0;
    float m = cos(v);
    float n = sin(v) * 1.732050808;
    float t1 = clamp((m + m) * z - kx, 0.0, 1.0);
    float t2 = clamp((-n - m) * z - kx, 0.0, 1.0);
    float res1 = dot2(d + (c + b * t1) * t1);
    float res2 = dot2(d + (c + b * t2) * t2);
    if (res1 <= res2) {
      closestT = t1;
      res = res1;
    } else {
      closestT = t2;
      res = res2;
    }
  }
  return float2(sqrt(res), closestT);
}

float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
  return bezierDistanceT(pos, A, B, C).x;
}

bool isBezierStrokeMode(int sdfModeInt) {
  return sdfModeInt == 18 || sdfModeInt == 19 || sdfModeInt == 20;
}

bool isBezierFillFringeMode(int sdfModeInt) {
  return sdfModeInt == 21;
}

bool isBezierMode(int sdfModeInt) {
  return isBezierStrokeMode(sdfModeInt) || isBezierFillFringeMode(sdfModeInt);
}

float cross2(float2 a, float2 b) {
  return a.x * b.y - a.y * b.x;
}

float2 safeNormalize(float2 v, float2 fallback) {
  float len = length(v);
  return (len <= 0.000001) ? fallback : v / len;
}

float bezierStrokeSd(
    float dist,
    float2 pos,
    float2 A,
    float2 B,
    float2 C,
    float halfW,
    int sdfModeInt) {
  if (sdfModeInt == 18) {
    return dist - halfW;
  }

  float2 chord = C - A;
  float2 fallback = safeNormalize(chord, float2(1.0, 0.0));
  float2 startT = safeNormalize(B - A, fallback);
  float2 endT = safeNormalize(C - B, fallback);
  float startProj = dot(pos - A, startT);
  float endProj = dot(pos - C, endT);
  float trim = (sdfModeInt == 20) ? halfW : 0.0;
  float tubeDist = dist;
  if (sdfModeInt == 20) {
    if (startProj < 0.0) {
      tubeDist = min(tubeDist, abs(cross2(pos - A, startT)));
    }
    if (endProj > 0.0) {
      tubeDist = min(tubeDist, abs(cross2(pos - C, endT)));
    }
  }
  float capDist = max(-startProj - trim, endProj - trim);
  return max(tubeDist - halfW, capDist);
}

float bezierFillFringeAlpha(
    float2 pos,
    float2 A,
    float2 B,
    float2 C,
    float insideSign,
    float aaFactor) {
  float2 distanceT = bezierDistanceT(pos, A, B, C);
  float t = distanceT.y;
  float invT = 1.0 - t;
  float2 curvePoint = A * invT * invT + B * 2.0 * invT * t + C * t * t;
  float2 chord = C - A;
  float chordLength = length(chord);
  if (chordLength <= 0.000001) {
    return 0.0;
  }

  float2 chordDirection = chord / chordLength;
  float2 tangent = safeNormalize(
    2.0 * ((B - A) * invT + (C - B) * t),
    chordDirection
  );
  float side = cross2(tangent, pos - curvePoint);
  float orientedDistance =
    (abs(side) <= 0.000001)
      ? 0.0
      : -insideSign * (side < 0.0 ? -distanceT.x : distanceT.x);
  float exactCoverage = clamp(0.5 - aaFactor * orientedDistance, 0.0, 1.0);

  float chordOutsideDistance =
    -insideSign * cross2(chordDirection, pos - A);
  float polygonOutside =
    clamp(aaFactor * chordOutsideDistance + 0.5, 0.0, 1.0);

  float chordPosition = dot(pos - A, chordDirection);
  float capOutsideDistance =
    max(-chordPosition, chordPosition - chordLength);
  float spanCoverage =
    1.0 - clamp(aaFactor * capOutsideDistance, 0.0, 1.0);
  return exactCoverage * polygonOutside * spanCoverage;
}

float shadowProfile(float sd, float blurRadius) {
  // CSS-like calibration: sigma ~= blurRadius / 2
  float sigma = max(0.5 * blurRadius, 0.5);
  float z = sd / sigma;
  return exp(-0.5 * z * z);
}

float rectMaskAlpha(
    float2 pos,
    float4 params,
    float4 radii,
    float4 matX,
    float4 matY,
    float aaFactor) {
  if (params.z < 0.0 || params.w < 0.0) {
    return 1.0;
  }

  float2 local = float2(
    dot(matX.xy, pos) + matX.z,
    dot(matY.xy, pos) + matY.z
  );
  float2 q = local - params.xy;
  float dist = sdRoundedBox(float2(q.x, -q.y), params.zw, radii);
  return 1.0 - clamp(aaFactor * dist + 0.5, 0.0, 1.0);
}

float linear3T(int fillMode, float2 uv) {
  switch (fillMode) {
    case 1:
      return uv.x;
    case 2:
      return uv.y;
    case 3:
      return 0.5 * (uv.x + uv.y);
    case 4:
      return 0.5 * (uv.x + (1.0 - uv.y));
    default:
      return 0.0;
  }
}

float4 evalFillColor(
    float4 color,
    float4 midColor,
    float4 stopColor,
    int fillMode,
    float midPos,
    float2 uv) {
  if (fillMode == 0) {
    return color;
  }

  float t = clamp(linear3T(fillMode, uv), 0.0, 1.0);
  float mid = clamp(midPos, 0.01, 0.99);
  if (t <= mid) {
    return mix(color, midColor, t / mid);
  }
  return mix(midColor, stopColor, (t - mid) / (1.0 - mid));
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
    const device uchar4* fillMidColors [[buffer(7)]],
    const device uchar4* fillStopColors [[buffer(8)]],
    constant VSUniforms& u [[buffer(9)]]) {
  VSOut out;
  float2 p = positions[vid];
  out.position = u.proj * float4(p.x, p.y, 0.0, 1.0);
  out.pos = p;
  out.uv = uvs[vid];
  out.color = float4(colors[vid]) / 255.0;
  out.fillMidColor = float4(fillMidColors[vid]) / 255.0;
  out.fillStopColor = float4(fillStopColors[vid]) / 255.0;
  out.sdfParams = sdfParams[vid];
  out.sdfRadii = sdfRadii[vid];
  out.sdfMode = float(sdfMode[vid]);
  out.sdfFactors = sdfFactors[vid];
  return out;
}

vertex RectMaskVSOut vs_rect_mask(
    uint vid [[vertex_id]],
    const device float2* positions [[buffer(0)]],
    const device float2* uvs [[buffer(1)]],
    const device uchar4* colors [[buffer(2)]],
    const device float4* sdfParams [[buffer(3)]],
    const device float4* sdfRadii [[buffer(4)]],
    const device ushort* sdfMode [[buffer(5)]],
    const device float2* sdfFactors [[buffer(6)]],
    const device uchar4* fillMidColors [[buffer(7)]],
    const device uchar4* fillStopColors [[buffer(8)]],
    const device float4* rectMaskParams [[buffer(9)]],
    const device float4* rectMaskRadii [[buffer(10)]],
    const device float4* rectMaskMatX [[buffer(11)]],
    const device float4* rectMaskMatY [[buffer(12)]],
    constant VSUniforms& u [[buffer(13)]]) {
  RectMaskVSOut out;
  float2 p = positions[vid];
  out.position = u.proj * float4(p.x, p.y, 0.0, 1.0);
  out.pos = p;
  out.uv = uvs[vid];
  out.color = float4(colors[vid]) / 255.0;
  out.fillMidColor = float4(fillMidColors[vid]) / 255.0;
  out.fillStopColor = float4(fillStopColors[vid]) / 255.0;
  out.sdfParams = sdfParams[vid];
  out.sdfRadii = sdfRadii[vid];
  out.sdfMode = float(sdfMode[vid]);
  out.sdfFactors = sdfFactors[vid];
  out.rectMaskParams = rectMaskParams[vid];
  out.rectMaskRadii = rectMaskRadii[vid];
  out.rectMaskMatX = rectMaskMatX[vid];
  out.rectMaskMatY = rectMaskMatY[vid];
  return out;
}

float4 evalMainFragment(
    float2 pos,
    float2 uv,
    float4 color,
    float4 fillMidColor,
    float4 fillStopColor,
    float4 sdfParams,
    float4 sdfRadii,
    float sdfMode,
    float2 sdfFactors,
    constant FSUniforms& u,
    texture2d<float> atlasTex,
    texture2d<float> maskTex,
    texture2d<float> backdropTex) {
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
  const int sdfModeBezierStrokeAA = 18;
  const int sdfModeBezierStrokeButtAA = 19;
  const int sdfModeBezierStrokeSquareAA = 20;
  const int sdfModeBezierFillFringeAA = 21;

  int packedSdfMode = int(sdfMode);
  int fillMode = packedSdfMode / 256;
  int sdfModeInt = packedSdfMode - fillMode * 256;
  float2 quadHalfExtents = sdfParams.xy;
  bool insetMode = (sdfModeInt == sdfModeInsetShadow);
  float2 shapeHalfExtents = insetMode ? quadHalfExtents : sdfParams.zw;

  float2 p = float2(
    (uv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (uv.y - 0.5) * 2.0 * quadHalfExtents.y
  );

  float dist;
  if (isBezierMode(sdfModeInt)) {
    dist = sdBezier(p, sdfParams.zw, sdfRadii.xy, sdfRadii.zw);
  } else {
    dist = sdRoundedBox(float2(p.x, -p.y), shapeHalfExtents, sdfRadii);
  }

  float sdfFactor = sdfFactors.x;
  float sdfSpread = (fillMode == 0) ? sdfFactors.y : 0.0;
  float4 fillColor =
    evalFillColor(color, fillMidColor, fillStopColor, fillMode, sdfFactors.y, uv);

  float4 fragColor;
  float alpha = 0.0;
  if (sdfModeInt == sdfModeAtlas) {
    float4 tex = atlasTex.sample(s, uv);
    fragColor = float4(
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

    float4 tex = atlasTex.sample(s, uv, level(0.0));
    bool isMtsdf = (sdfModeInt == sdfModeMtsdf || sdfModeInt == sdfModeMtsdfAnnular);
    bool isStroke =
      (sdfModeInt == sdfModeMsdfAnnular || sdfModeInt == sdfModeMtsdfAnnular);
    float sd = isMtsdf ? tex.w : median(tex.x, tex.y, tex.z);
    float screenPxDistance =
      msdfScreenPxRange(atlasTex, uv, pxRange) * (sd - sdThreshold);

    if (isStroke) {
      float strokeW = max(sdfParams.y, 0.0);
      float halfW = strokeW * 0.5;
      alpha = clamp(halfW - abs(screenPxDistance) + 0.5, 0.0, 1.0);
    } else {
      alpha = clamp(screenPxDistance + 0.5, 0.0, 1.0);
    }
    fragColor = float4(fillColor.xyz, fillColor.w * alpha);
  } else {
    switch (sdfModeInt) {
      case sdfModeBezierStrokeAA:
      case sdfModeBezierStrokeButtAA:
      case sdfModeBezierStrokeSquareAA: {
        float sd = bezierStrokeSd(
          dist,
          p,
          sdfParams.zw,
          sdfRadii.xy,
          sdfRadii.zw,
          max(sdfFactor, 0.0) * 0.5,
          sdfModeInt
        );
        float cl = clamp(u.aaFactor * sd + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
      case sdfModeBezierFillFringeAA: {
        alpha = bezierFillFringeAlpha(
          p,
          sdfParams.zw,
          sdfRadii.xy,
          sdfRadii.zw,
          (sdfFactor < 0.0) ? -1.0 : 1.0,
          u.aaFactor
        );
        break;
      }
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
        float2 shadowOffset = float2(sdfParams.z, -sdfParams.w);
        float2 qShadow = qClip - shadowOffset;
        float clipDist = sdRoundedBox(qClip, quadHalfExtents, sdfRadii);
        float clipAlpha = 1.0 - clamp(u.aaFactor * clipDist + 0.5, 0.0, 1.0);
        float shadowDist = sdRoundedBox(qShadow, quadHalfExtents, sdfRadii);
        float sd = shadowDist + sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        float insetAlpha = (sd < 0.0) ? min(a, 1.0) : 1.0;
        alpha = clipAlpha * insetAlpha;
        break;
      }
      case sdfModeBackdropBlur: {
        float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        float2 normalizedPos = float2(pos.x / u.windowFrame.x, pos.y / u.windowFrame.y);
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
      fragColor = float4(fillColor.x, fillColor.y, fillColor.z, fillColor.w * alpha);
    }
  }

  float2 normalizedPos =
    float2(pos.x / u.windowFrame.x, pos.y / u.windowFrame.y);
  if (u.maskTexEnabled != 0) {
    fragColor.w *= maskTex.sample(s, normalizedPos).x;
  }
  return fragColor;
}

fragment float4 fs_main(
    VSOut in [[stage_in]],
    constant FSUniforms& u [[buffer(0)]],
    texture2d<float> atlasTex [[texture(0)]],
    texture2d<float> maskTex [[texture(1)]],
    texture2d<float> backdropTex [[texture(2)]]) {
  return evalMainFragment(
    in.pos,
    in.uv,
    in.color,
    in.fillMidColor,
    in.fillStopColor,
    in.sdfParams,
    in.sdfRadii,
    in.sdfMode,
    in.sdfFactors,
    u,
    atlasTex,
    maskTex,
    backdropTex
  );
}

fragment float4 fs_rect_mask(
    RectMaskVSOut in [[stage_in]],
    constant FSUniforms& u [[buffer(0)]],
    texture2d<float> atlasTex [[texture(0)]],
    texture2d<float> maskTex [[texture(1)]],
    texture2d<float> backdropTex [[texture(2)]]) {
  float4 fragColor = evalMainFragment(
    in.pos,
    in.uv,
    in.color,
    in.fillMidColor,
    in.fillStopColor,
    in.sdfParams,
    in.sdfRadii,
    in.sdfMode,
    in.sdfFactors,
    u,
    atlasTex,
    maskTex,
    backdropTex
  );
  fragColor.w *= rectMaskAlpha(
    in.pos,
    in.rectMaskParams,
    in.rectMaskRadii,
    in.rectMaskMatX,
    in.rectMaskMatY,
    u.aaFactor
  );
  return fragColor;
}

fragment float4 fs_mask(
    VSOut in [[stage_in]],
    constant FSUniforms& u [[buffer(0)]],
    texture2d<float> atlasTex [[texture(0)]],
    texture2d<float> maskTex [[texture(1)]]) {
  const int sdfModeAtlas = 0;

  float alpha;
  int packedSdfMode = int(in.sdfMode);
  int fillMode = packedSdfMode / 256;
  int sdfModeInt = packedSdfMode - fillMode * 256;
  if (sdfModeInt == sdfModeAtlas) {
    alpha = atlasTex.sample(s, in.uv).a * in.color.a;
  } else {
    float2 quadHalfExtents = in.sdfParams.xy;
    float2 shapeHalfExtents = in.sdfParams.zw;
    float2 p = float2(
      (in.uv.x - 0.5) * 2.0 * quadHalfExtents.x,
      (in.uv.y - 0.5) * 2.0 * quadHalfExtents.y
    );
    float dist;
    if (isBezierStrokeMode(sdfModeInt)) {
      float bezierDist = sdBezier(p, in.sdfParams.zw, in.sdfRadii.xy, in.sdfRadii.zw);
      dist = bezierStrokeSd(
        bezierDist,
        p,
        in.sdfParams.zw,
        in.sdfRadii.xy,
        in.sdfRadii.zw,
        max(in.sdfFactors.x, 0.0) * 0.5,
        sdfModeInt
      );
    } else if (isBezierFillFringeMode(sdfModeInt)) {
      alpha = bezierFillFringeAlpha(
        p,
        in.sdfParams.zw,
        in.sdfRadii.xy,
        in.sdfRadii.zw,
        (in.sdfFactors.x < 0.0) ? -1.0 : 1.0,
        u.aaFactor
      ) * in.color.a;
      dist = 0.0;
    } else {
      dist = sdRoundedBox(float2(p.x, -p.y), shapeHalfExtents, in.sdfRadii);
    }
    if (!isBezierFillFringeMode(sdfModeInt)) {
      float cl = clamp(u.aaFactor * dist + 0.5, 0.0, 1.0);
      alpha = (1.0 - cl) * in.color.a;
    }
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
