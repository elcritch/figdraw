#version 330

in vec2 pos;
in vec2 uv;
in vec4 color;
in vec4 fillMidColor;
in vec4 fillStopColor;
in vec4 sdfParams;
in vec4 sdfRadii;
in float sdfMode;
in vec2 sdfFactors;
in float subpixelShift;
in vec4 rectMaskParams;
in vec4 rectMaskRadii;
in vec4 rectMaskMatX;
in vec4 rectMaskMatY;

uniform vec2 windowFrame;
uniform sampler2D atlasTex;
uniform sampler2D maskTex;
uniform sampler2D backdropTex;
uniform vec2 atlasTexelSize;
uniform float aaFactor;
uniform bool maskTexEnabled;
uniform bool subpixelPositioningEnabled;

out vec4 fragColor;

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

float shadowProfile(float sd, float blurRadius) {
  // CSS-like calibration: sigma ~= blurRadius / 2
  float sigma = max(0.5 * blurRadius, 0.5);
  float z = sd / sigma;
  return exp(-0.5 * z * z);
}

float rectMaskAlpha(vec2 pixelPos) {
  if (rectMaskParams.z < 0.0 || rectMaskParams.w < 0.0) {
    return 1.0;
  }

  vec2 local = vec2(
    dot(rectMaskMatX.xy, pixelPos) + rectMaskMatX.z,
    dot(rectMaskMatY.xy, pixelPos) + rectMaskMatY.z
  );
  vec2 q = local - rectMaskParams.xy;
  float dist = sdRoundedBox(vec2(q.x, -q.y), rectMaskParams.zw, rectMaskRadii);
  return 1.0 - clamp(aaFactor * dist + 0.5, 0.0, 1.0);
}

float linear3T(int fillMode, vec2 uv) {
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

vec4 evalFillColor(
    vec4 color,
    vec4 midColor,
    vec4 stopColor,
    int fillMode,
    float midPos,
    vec2 uv) {
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

void main() {
  int packedSdfMode = int(sdfMode);
  int fillMode = packedSdfMode / 256;
  int sdfModeInt = packedSdfMode - fillMode * 256;
  vec2 quadHalfExtents = sdfParams.xy;
  bool insetMode = (sdfModeInt == sdfModeInsetShadow);
  vec2 shapeHalfExtents = insetMode ? quadHalfExtents : sdfParams.zw;

  vec2 p = vec2(
    (uv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (uv.y - 0.5) * 2.0 * quadHalfExtents.y
  );

  float dist;
  if (sdfModeInt == sdfModeBezierStrokeAA) {
    dist = sdBezier(p, sdfParams.zw, sdfRadii.xy, sdfRadii.zw);
  } else {
    dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, sdfRadii);
  }

  float sdfFactor = sdfFactors.x;
  float sdfSpread = (fillMode == 0) ? sdfFactors.y : 0.0;
  vec4 fillColor =
    evalFillColor(color, fillMidColor, fillStopColor, fillMode, sdfFactors.y, uv);

  float alpha = 0.0;
  if (sdfModeInt == sdfModeAtlas) {
    vec2 atlasUv = uv;
    if (subpixelPositioningEnabled) {
      atlasUv.x -= subpixelShift * atlasTexelSize.x;
    }
    vec4 tex = texture(atlasTex, atlasUv);
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
    fragColor = vec4(fillColor.xyz, fillColor.w * alpha);
  } else {
    switch (sdfModeInt) {
      case sdfModeBezierStrokeAA: {
        float sd = dist - max(sdfFactor, 0.0) * 0.5;
        float cl = clamp(aaFactor * sd + 0.5, 0.0, 1.0);
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
        float cl = clamp(aaFactor * sd + 0.5, 0.0, 1.0);
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
        float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
        float insideAlpha = 1.0 - cl;
        float sd = dist - sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        alpha = (sd >= 0.0) ? min(a, 1.0) : insideAlpha;
        break;
      }
      case sdfModeInsetShadow: {
        vec2 qClip = vec2(p.x, -p.y);
        vec2 shadowOffset = vec2(sdfParams.z, -sdfParams.w);
        vec2 qShadow = qClip - shadowOffset;
        float clipDist = sdRoundedBox(qClip, quadHalfExtents, sdfRadii);
        float clipAlpha = 1.0 - clamp(aaFactor * clipDist + 0.5, 0.0, 1.0);
        float shadowDist = sdRoundedBox(qShadow, quadHalfExtents, sdfRadii);
        float sd = shadowDist + sdfSpread;
        float a = shadowProfile(sd, sdfFactor);
        float insetAlpha = (sd < 0.0) ? min(a, 1.0) : 1.0;
        alpha = clipAlpha * insetAlpha;
        break;
      }
      case sdfModeBackdropBlur: {
        float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        vec2 normalizedPos = vec2(pos.x / windowFrame.x, 1.0 - pos.y / windowFrame.y);
        vec4 blur = texture(backdropTex, normalizedPos);
        fragColor = vec4(blur.rgb, blur.a * alpha);
        break;
      }
      default: {
        float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
        alpha = 1.0 - cl;
        break;
      }
    }

    if (sdfModeInt != sdfModeBackdropBlur) {
      fragColor = vec4(fillColor.x, fillColor.y, fillColor.z, fillColor.w * alpha);
    }
  }

  vec2 normalizedPos = vec2(pos.x / windowFrame.x, 1.0 - pos.y / windowFrame.y);
  if (maskTexEnabled) {
    fragColor.w *= texture(maskTex, normalizedPos).x;
  }
  fragColor.w *= rectMaskAlpha(pos);
}
