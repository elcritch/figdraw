#version 330
in vec2 uv;
out vec4 fragColor;
uniform sampler2D srcTex;
uniform sampler2D maskTex;
uniform bool maskTexEnabled;
uniform float opacity;
uniform float aaFactor;
uniform vec2 windowFrame;
uniform vec4 rectMaskParams, rectMaskRadii, rectMaskMatX, rectMaskMatY;
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

float sdEllipse(vec2 p, vec2 radii) {
  vec2 safeRadii = max(radii, vec2(0.000001));
  float k0 = length(p / safeRadii);
  if (k0 <= 0.000001) {
    return -min(safeRadii.x, safeRadii.y);
  }
  float k1 = length(p / (safeRadii * safeRadii));
  return k0 * (k0 - 1.0) / max(k1, 0.000001);
}

float selectCornerRadius(vec4 radii, vec2 p) {
  if (p.x > 0.0) {
    return (p.y > 0.0) ? radii.x : radii.y;
  }
  return (p.y > 0.0) ? radii.z : radii.w;
}

vec2 decodeEllipticalCornerRadii(vec4 packedRadii, vec2 halfExtents, vec2 p) {
  float packedValue = floor(selectCornerRadius(packedRadii, p));
  return vec2(
    mod(packedValue, 4096.0) * halfExtents.x / 4095.0,
    floor(packedValue / 4096.0) * halfExtents.y / 4095.0
  );
}

float sdEllipticalRoundedBox(vec2 p, vec2 b, vec4 packedRadii) {
  float selectedRadius = selectCornerRadius(packedRadii, p);
  if (selectedRadius < 0.0) {
    return sdRoundedBox(p, b, vec4(-selectedRadius - 1.0));
  }
  vec2 radii = decodeEllipticalCornerRadii(packedRadii, b, p);
  if (radii.x <= 0.0 || radii.y <= 0.0) {
    vec2 q = abs(p) - b;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0)));
  }
  if (radii.x == radii.y) {
    return sdRoundedBox(p, b, vec4(radii.x));
  }

  vec2 q = abs(p) - b + radii;
  if (q.x > 0.0 && q.y > 0.0) {
    return sdEllipse(q, radii);
  }
  return max(q.x - radii.x, q.y - radii.y);
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
  float dist = rectMaskMatY.w > 0.5 ?
    sdEllipticalRoundedBox(vec2(q.x, -q.y), rectMaskParams.zw, rectMaskRadii) :
    sdRoundedBox(vec2(q.x, -q.y), rectMaskParams.zw, rectMaskRadii);
  return 1.0 - clamp(aaFactor * dist + 0.5, 0.0, 1.0);
}

void main() {
  float coverage = rectMaskAlpha(vec2(uv.x, 1.0 - uv.y) * windowFrame);
  if (maskTexEnabled) coverage *= texture(maskTex, uv).r;
  fragColor = texture(srcTex, uv) * (opacity * coverage);
}
