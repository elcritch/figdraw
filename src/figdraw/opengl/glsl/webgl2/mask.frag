#version 300 es

precision highp float;

in vec2 pos;
in vec2 uv;
in vec4 color;
in vec4 sdfParams;
in vec4 sdfRadii;
in float sdfMode;

uniform vec2 windowFrame;
uniform sampler2D atlasTex;
uniform sampler2D maskTex;
uniform float aaFactor;
uniform bool maskTexEnabled;

out vec4 fragColor;

const int sdfModeAtlas = 0;

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

void main() {
  float alpha;
  int sdfModeInt = int(sdfMode);
  if (sdfModeInt == sdfModeAtlas) {
    alpha = texture(atlasTex, uv).a * color.a;
  } else {
    vec2 quadHalfExtents = sdfParams.xy;
    vec2 shapeHalfExtents = sdfParams.zw;
    vec2 p = vec2(
      (uv.x - 0.5) * 2.0 * quadHalfExtents.x,
      (uv.y - 0.5) * 2.0 * quadHalfExtents.y
    );
    float dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, sdfRadii);
    float cl = clamp(aaFactor * dist + 0.5, 0.0, 1.0);
    alpha = (1.0 - cl) * color.a;
  }

  vec2 normalizedPos = vec2(pos.x / windowFrame.x, 1.0 - pos.y / windowFrame.y);
  if (maskTexEnabled) {
    alpha *= texture(maskTex, normalizedPos).r;
  }
  fragColor = vec4(alpha);
}
