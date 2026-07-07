#version 100

precision highp float;

varying vec2 pos;
varying vec2 uv;
varying vec4 color;
varying vec4 sdfParams;
varying vec4 sdfRadii;
varying float sdfMode;
varying vec2 sdfFactors;
varying float subpixelShift;

uniform vec2 windowFrame;
uniform sampler2D atlasTex;
uniform sampler2D maskTex;
uniform float aaFactor;
uniform bool maskTexEnabled;

const int sdfModeAtlas = 0;
const int sdfModeBezierStrokeAA = 18;

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

void main() {
  float alpha;
  float packedSdfMode = sdfMode;
  float fillModeFloat = floor(packedSdfMode / 256.0);
  int sdfModeInt = int(packedSdfMode - fillModeFloat * 256.0);
  if (sdfModeInt == sdfModeAtlas) {
    alpha = texture2D(atlasTex, uv).a * color.a;
  } else {
    vec2 quadHalfExtents = sdfParams.xy;
    vec2 shapeHalfExtents = sdfParams.zw;
    vec2 p = vec2(
      (uv.x - 0.5) * 2.0 * quadHalfExtents.x,
      (uv.y - 0.5) * 2.0 * quadHalfExtents.y
    );
    float dist;
    if (sdfModeInt == sdfModeBezierStrokeAA) {
      dist = sdBezier(p, sdfParams.zw, sdfRadii.xy, sdfRadii.zw) -
        max(sdfFactors.x, 0.0) * 0.5;
    } else {
      dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, sdfRadii);
    }
    float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
    alpha = (1.0 - cl) * color.a;
  }

  vec2 normalizedPos = vec2(pos.x / windowFrame.x, 1.0 - pos.y / windowFrame.y);
  if (maskTexEnabled) {
    alpha *= texture2D(maskTex, normalizedPos).r;
  }
  gl_FragColor = vec4(alpha);
}
