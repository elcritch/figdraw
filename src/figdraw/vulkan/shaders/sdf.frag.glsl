#version 450

layout(set = 0, binding = 1) uniform FSUniforms {
  vec2 windowFrame;
  float aaFactor;
  uint maskTexEnabled;
} uFS;

layout(set = 0, binding = 2) uniform sampler2D atlasTex;
layout(set = 0, binding = 3) uniform sampler2D maskTex;
layout(set = 0, binding = 4) uniform sampler2D backdropTex;

layout(location = 0) in vec2 vPos;
layout(location = 1) in vec2 vUv;
layout(location = 2) in vec4 vColor;
layout(location = 3) in vec4 vFillMidColor;
layout(location = 4) in vec4 vFillStopColor;
layout(location = 5) in vec4 vSdfParams;
layout(location = 6) in vec4 vSdfRadii;
layout(location = 7) flat in uint vSdfMode;
layout(location = 8) in vec2 vSdfFactors;
layout(location = 9) in vec4 vRectMaskParams;
layout(location = 10) in vec4 vRectMaskRadii;
layout(location = 11) in vec4 vRectMaskMatX;
layout(location = 12) in vec4 vRectMaskMatY;

layout(location = 0) out vec4 fragColor;

const uint sdfModeAtlas = 0u;
const uint sdfModeDropShadow = 7u;
const uint sdfModeDropShadowAA = 8u;
const uint sdfModeInsetShadow = 9u;
const uint sdfModeAnnular = 11u;
const uint sdfModeAnnularAA = 12u;
const uint sdfModeMsdf = 13u;
const uint sdfModeMtsdf = 14u;
const uint sdfModeMsdfAnnular = 15u;
const uint sdfModeMtsdfAnnular = 16u;
const uint sdfModeBackdropBlur = 17u;
const uint sdfModeBezierStrokeAA = 18u;
const uint sdfModeBezierStrokeButtAA = 19u;
const uint sdfModeBezierStrokeSquareAA = 20u;
const uint sdfFillModeShift = 256u;

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

float dot2(vec2 v) {
  return dot(v, v);
}

float sdBezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
  vec2 a = B - A;
  vec2 b = A - 2.0 * B + C;
  float bb = dot(b, b);
  if (bb <= 0.000001) {
    vec2 ba = C - A;
    float h = clamp(dot(pos - A, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return length(pos - (A + ba * h));
  }

  vec2 c = a * 2.0;
  vec2 d = A - pos;
  float kk = 1.0 / bb;
  float kx = kk * dot(a, b);
  float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
  float kz = kk * dot(d, a);
  float p = ky - kx * kx;
  float p3 = p * p * p;
  float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
  float h = q * q + 4.0 * p3;
  float res = 0.0;
  if (h >= 0.0) {
    h = sqrt(h);
    vec2 x = vec2((h - q) / 2.0, (-h - q) / 2.0);
    vec2 roots = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
    float t = clamp(roots.x + roots.y - kx, 0.0, 1.0);
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
    res = min(res1, res2);
  }
  return sqrt(res);
}

bool isBezierStrokeMode(uint sdfModeInt) {
  return (
    sdfModeInt == sdfModeBezierStrokeAA ||
    sdfModeInt == sdfModeBezierStrokeButtAA ||
    sdfModeInt == sdfModeBezierStrokeSquareAA
  );
}

float cross2(vec2 a, vec2 b) {
  return a.x * b.y - a.y * b.x;
}

vec2 safeNormalize(vec2 v, vec2 fallback) {
  float len = length(v);
  return (len <= 0.000001) ? fallback : v / len;
}

float bezierStrokeSd(
    float dist,
    vec2 pos,
    vec2 A,
    vec2 B,
    vec2 C,
    float halfW,
    uint sdfModeInt) {
  if (sdfModeInt == sdfModeBezierStrokeAA) {
    return dist - halfW;
  }

  vec2 chord = C - A;
  vec2 fallback = safeNormalize(chord, vec2(1.0, 0.0));
  vec2 startT = safeNormalize(B - A, fallback);
  vec2 endT = safeNormalize(C - B, fallback);
  float startProj = dot(pos - A, startT);
  float endProj = dot(pos - C, endT);
  float trim = (sdfModeInt == sdfModeBezierStrokeSquareAA) ? halfW : 0.0;
  float tubeDist = dist;
  if (sdfModeInt == sdfModeBezierStrokeSquareAA) {
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

float rectMaskAlpha(vec2 pixelPos) {
  if (vRectMaskParams.z <= 0.0 || vRectMaskParams.w <= 0.0) {
    return 1.0;
  }

  vec2 local = vec2(
    dot(vRectMaskMatX.xy, pixelPos) + vRectMaskMatX.z,
    dot(vRectMaskMatY.xy, pixelPos) + vRectMaskMatY.z
  );
  vec2 q = local - vRectMaskParams.xy;
  float dist = sdRoundedBox(vec2(q.x, -q.y), vRectMaskParams.zw, vRectMaskRadii);
  return 1.0 - clamp(uFS.aaFactor * dist + 0.5, 0.0, 1.0);
}

float shadowProfile(float sd, float blurRadius) {
  // CSS-like calibration: sigma ~= blurRadius / 2
  float sigma = max(0.5 * blurRadius, 0.5);
  float z = sd / sigma;
  return exp(-0.5 * z * z);
}

float linear3T(uint fillMode, vec2 uv) {
  switch (fillMode) {
    case 1u:
      return uv.x;
    case 2u:
      return uv.y;
    case 3u:
      return 0.5 * (uv.x + uv.y);
    case 4u:
      return 0.5 * (uv.x + (1.0 - uv.y));
    default:
      return 0.0;
  }
}

vec4 evalFillColor(
    vec4 color,
    vec4 midColor,
    vec4 stopColor,
    uint fillMode,
    float midPos,
    vec2 uv) {
  if (fillMode == 0u) {
    return color;
  }

  float t = clamp(linear3T(fillMode, uv), 0.0, 1.0);
  float mid = clamp(midPos, 0.01, 0.99);
  if (t <= mid) {
    return mix(color, midColor, t / mid);
  }
  return mix(midColor, stopColor, (t - mid) / (1.0 - mid));
}

void main() {
  uint fillMode = vSdfMode / sdfFillModeShift;
  uint sdfModeInt = vSdfMode - fillMode * sdfFillModeShift;
  vec2 quadHalfExtents = vSdfParams.xy;
  bool insetMode = (sdfModeInt == sdfModeInsetShadow);
  vec2 shapeHalfExtents = insetMode ? quadHalfExtents : vSdfParams.zw;

  vec2 p = vec2(
    (vUv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (vUv.y - 0.5) * 2.0 * quadHalfExtents.y
  );
  float dist;
  if (isBezierStrokeMode(sdfModeInt)) {
    dist = sdBezier(p, vSdfParams.zw, vSdfRadii.xy, vSdfRadii.zw);
  } else {
    dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, vSdfRadii);
  }

  float sdfFactor = vSdfFactors.x;
  float sdfSpread = vSdfFactors.y;
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
    switch (sdfModeInt) {
      case sdfModeBezierStrokeAA:
      case sdfModeBezierStrokeButtAA:
      case sdfModeBezierStrokeSquareAA: {
        float sd = bezierStrokeSd(
          dist,
          p,
          vSdfParams.zw,
          vSdfRadii.xy,
          vSdfRadii.zw,
          max(sdfFactor, 0.0) * 0.5,
          sdfModeInt
        );
        float cl = clamp(uFS.aaFactor * sd + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
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
        float cl = clamp(uFS.aaFactor * sd + 0.5, 0.0, 1.0);
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
        float cl = clamp(uFS.aaFactor * dist + 0.5, 0.0, 1.0);
        float insideAlpha = 1.0 - cl;
        float sd = dist - sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        alpha = (sd >= 0.0) ? min(a, 1.0) : insideAlpha;
        break;
      }
      case sdfModeInsetShadow: {
        vec2 qClip = vec2(p.x, -p.y);
        vec2 shadowOffset = vec2(vSdfParams.z, -vSdfParams.w);
        vec2 qShadow = qClip - shadowOffset;
        float clipDist = sdRoundedBox(qClip, quadHalfExtents, vSdfRadii);
        float clipAlpha = 1.0 - clamp(uFS.aaFactor * clipDist + 0.5, 0.0, 1.0);
        float shadowDist = sdRoundedBox(qShadow, quadHalfExtents, vSdfRadii);
        float sd = shadowDist + sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        float insetAlpha = (sd < 0.0) ? min(a, 1.0) : 1.0;
        alpha = clipAlpha * insetAlpha;
        break;
      }
      case sdfModeBackdropBlur: {
        float cl = clamp(uFS.aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        vec2 normalizedPos = vec2(vPos.x / uFS.windowFrame.x, vPos.y / uFS.windowFrame.y);
        vec4 blur = texture(backdropTex, normalizedPos);
        fragColor = vec4(blur.rgb, blur.a * alpha);
        break;
      }
      default: {
        float cl = clamp(uFS.aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
    }

    if (sdfModeInt != sdfModeBackdropBlur) {
      vec4 fillColor = evalFillColor(
        vColor, vFillMidColor, vFillStopColor, fillMode, vSdfFactors.y, vUv
      );
      fragColor = vec4(fillColor.rgb, fillColor.a * alpha);
    }
  }

  fragColor.a *= rectMaskAlpha(vPos);

  if (uFS.maskTexEnabled != 0u) {
    vec2 normalizedPos = vec2(vPos.x / uFS.windowFrame.x, 1.0 - vPos.y / uFS.windowFrame.y);
    fragColor.a *= texture(maskTex, normalizedPos).r;
  }
}
