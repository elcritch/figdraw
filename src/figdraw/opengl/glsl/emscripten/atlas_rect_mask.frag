#version 100

#extension GL_OES_standard_derivatives : enable
precision highp float;

varying vec2 pos;
varying vec2 uv;
varying vec4 color;
varying vec4 fillMidColor;
varying vec4 fillStopColor;
varying vec4 sdfParams;
varying vec4 sdfRadii;
varying float sdfMode;
varying vec4 sdfFactors;
varying vec4 rectMaskParams;
varying vec4 rectMaskRadii;
varying vec4 rectMaskMatX;
varying vec4 rectMaskMatY;
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
varying vec4 rectMaskParams2;
varying vec4 rectMaskRadii2;
varying vec4 rectMaskMat2;
#endif

uniform vec2 windowFrame;
uniform sampler2D atlasTex;
uniform sampler2D maskTex;
uniform sampler2D backdropTex;
uniform vec2 atlasTexelSize;
uniform float aaFactor;
uniform bool maskTexEnabled;
uniform bool subpixelPositioningEnabled;

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

float median(float a, float b, float c) {
  return max(min(a, b), min(max(a, b), c));
}

float msdfScreenPxRange(float pxRange) {
  float atlasSize = sdfParams.x;
  vec2 unitRange = vec2(pxRange / atlasSize);
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

float shadowProfile(float sd, float blurRadius) {
  // CSS-like calibration: sigma ~= blurRadius / 2
  float sigma = max(0.5 * blurRadius, 0.5);
  float z = sd / sigma;
  return exp(-0.5 * z * z);
}

float rectMaskAlphaOne(
    vec2 pixelPos,
    vec4 params,
    vec4 radii,
    vec4 matX,
    vec4 matY) {
  if (params.z < 0.0 || params.w < 0.0) {
    return 1.0;
  }

  vec2 local = vec2(
    dot(matX.xy, pixelPos) + matX.z,
    dot(matY.xy, pixelPos) + matY.z
  );
  vec2 q = local - params.xy;
  float dist = sdRoundedBox(vec2(q.x, -q.y), params.zw, radii);
  return 1.0 - clamp(aaFactor * dist + 0.5, 0.0, 1.0);
}

float rectMaskAlpha(vec2 pixelPos) {
  float alpha =
    rectMaskAlphaOne(pixelPos, rectMaskParams, rectMaskRadii, rectMaskMatX, rectMaskMatY);
#if FIGDRAW_FAST_RECT_MASK_LIMIT >= 2
  vec4 matY2 = vec4(rectMaskMat2.w, rectMaskMatX.w, rectMaskMatY.w, 0.0);
  alpha *= rectMaskAlphaOne(pixelPos, rectMaskParams2, rectMaskRadii2, rectMaskMat2, matY2);
#endif
  return alpha;
}

float linear3T(int fillMode, vec2 uv) {
  if (fillMode == 1) {
    return uv.x;
  } else if (fillMode == 2) {
    return uv.y;
  } else if (fillMode == 3) {
    return 0.5 * (uv.x + uv.y);
  } else if (fillMode == 4) {
    return 0.5 * (uv.x + (1.0 - uv.y));
  }
  return 0.0;
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
  float packedSdfMode = sdfMode;
  float fillModeFloat = floor(packedSdfMode / 256.0);
  int fillMode = int(fillModeFloat);
  int sdfModeInt = int(packedSdfMode - fillModeFloat * 256.0);
  vec2 quadHalfExtents = sdfParams.xy;
  bool insetMode = (sdfModeInt == sdfModeInsetShadow);
  vec2 shapeHalfExtents = insetMode ? quadHalfExtents : sdfParams.zw;

  vec2 p = vec2(
    (uv.x - 0.5) * 2.0 * quadHalfExtents.x,
    (uv.y - 0.5) * 2.0 * quadHalfExtents.y
  );

  float dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, sdfRadii);

  float sdfFactor = sdfFactors.x;
  float sdfSpread = (fillMode == 0) ? sdfFactors.y : 0.0;
  vec4 fillColor =
    evalFillColor(color, fillMidColor, fillStopColor, fillMode, sdfFactors.y, uv);

  float alpha = 0.0;
  vec4 fragColor;
  if (sdfModeInt == sdfModeAtlas) {
    vec2 atlasUv = uv;
    if (subpixelPositioningEnabled) {
      atlasUv.x -= sdfFactors.z * atlasTexelSize.x;
    }
    vec4 tex = texture2D(atlasTex, atlasUv);
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

    vec4 tex = texture2D(atlasTex, uv);
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
    fragColor = vec4(fillColor.rgb, fillColor.a * alpha);
  } else {
    if (sdfModeInt == sdfModeAnnular) {
      float f = sdfFactor * 0.5;
      float sd = abs(dist + f) - f;
      alpha = (sd < 0.0) ? 1.0 : 0.0;
    } else if (sdfModeInt == sdfModeAnnularAA) {
      float f = sdfFactor * 0.5;
      float sd = abs(dist + f) - f;
      float cl = clamp(aaFactor * sd + 0.5, 0.0, 1.0);
      alpha = 1.0 - cl;
    } else if (sdfModeInt == sdfModeDropShadow) {
      float sd = dist - sdfSpread;
      float a = shadowProfile(sd, sdfFactor);
      alpha = (sd > 0.0) ? min(a, 1.0) : 1.0;
    } else if (sdfModeInt == sdfModeDropShadowAA) {
      float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
      float insideAlpha = 1.0 - cl;
      float sd = dist - sdfSpread;
      float a = shadowProfile(sd, sdfFactor);
      alpha = (sd >= 0.0) ? min(a, 1.0) : insideAlpha;
    } else if (sdfModeInt == sdfModeInsetShadow) {
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
    } else if (sdfModeInt == sdfModeBackdropBlur) {
      float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
      alpha = 1.0 - cl;
      vec2 normalizedPos = vec2(pos.x / windowFrame.x, 1.0 - pos.y / windowFrame.y);
      vec4 blur = texture2D(backdropTex, normalizedPos);
      fragColor = vec4(blur.rgb, blur.a * alpha);
    } else {
      float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
      alpha = 1.0 - cl;
    }

    if (sdfModeInt != sdfModeBackdropBlur) {
      fragColor = vec4(fillColor.x, fillColor.y, fillColor.z, fillColor.w * alpha);
    }
  }

  vec2 normalizedPos = vec2(pos.x / windowFrame.x, 1.0 - pos.y / windowFrame.y);
  if (maskTexEnabled) {
    fragColor.a *= texture2D(maskTex, normalizedPos).r;
  }
  fragColor.a *= rectMaskAlpha(pos);
  gl_FragColor = fragColor;
}
