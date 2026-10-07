/* Shared GLSL for /next: palette, hashes and noise, the studio environment, AgX, the eye camera and the eye's data rings. */

export const PAL = `
const vec3 MINT = vec3(0.074, 1.0, 0.35);
const vec3 VIO = vec3(0.434, 0.074, 1.0);
const vec3 GOLD = vec3(1.0, 0.637, 0.133);
const vec3 ICE = vec3(0.347, 0.807, 1.0);
`;

export const NOISE = `
float h12(vec2 p){ vec3 q = fract(vec3(p.xyx) * .1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float h13(vec3 p){ p = fract(p * .1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
vec2 g2(vec2 p){ float a = h12(p) * 6.2831853; return vec2(cos(a), sin(a)); }
float pn(vec2 p, float per){
  vec2 i = floor(p), f = fract(p), u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float x0 = mod(i.x, per), x1 = mod(i.x + 1.0, per);
  float a = dot(g2(vec2(x0, i.y)), f), b = dot(g2(vec2(x1, i.y)), f - vec2(1.0, 0.0));
  float c = dot(g2(vec2(x0, i.y + 1.0)), f - vec2(0.0, 1.0)), d = dot(g2(vec2(x1, i.y + 1.0)), f - 1.0);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.4 + 0.5;
}
float vn3(vec3 p){
  vec3 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(h13(i), h13(i + vec3(1, 0, 0)), u.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), u.x), u.y),
             mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), u.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
vec2 sph(vec3 ro, vec3 rd, vec3 c, float r){
  vec3 oc = ro - c; float b = dot(oc, rd), h = b * b - dot(oc, oc) + r * r;
  if (h < 0.0) return vec2(-1.0);
  h = sqrt(h); return vec2(-b - h, -b + h);
}
`;

/* Studio of the eye: one softbox key with a mullion, a mint floor strip, a violet fill; HDR values. */
export const ENV = `
float rbox(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
vec3 panel(vec3 d, vec3 c, vec2 size, float soft){
  float k = dot(d, c);
  if (k <= 0.05) return vec3(0.0);
  vec3 q = d / k - c, rt = normalize(cross(vec3(0.0, 1.0, 0.0), c)), up = cross(c, rt);
  vec2 l = vec2(dot(q, rt), dot(q, up));
  return vec3(1.0 - smoothstep(-soft, soft, rbox(l, size, min(size.x, size.y) * 0.3)), l);
}
const vec3 KEY = vec3(-0.46, 0.5, 0.735);
vec3 env(vec3 d, float sharp){
  vec3 col = mix(vec3(0.0006, 0.0014, 0.001), vec3(0.003, 0.006, 0.0045), smoothstep(-0.7, 0.9, d.y));
  float s = mix(0.35, 0.006, sharp);
  vec2 ks = vec2(0.12, 0.08);
  vec3 k = panel(d, normalize(KEY), ks, s);
  float spread = ks.x * ks.y / ((ks.x + s) * (ks.y + s));
  float bar = mix(1.0, smoothstep(0.002, 0.008, abs(k.y + 0.014)), sharp * sharp);
  col += k.x * bar * spread * vec3(0.9, 1.0, 0.95) * 40.0;
  col += panel(d, normalize(vec3(0.1, -0.6, 0.8)), vec2(0.95, 0.03), s * 3.0 + 0.02).x * MINT * 0.35;
  col += panel(d, normalize(vec3(0.86, 0.12, 0.48)), vec2(0.16, 0.38), 0.22).x * VIO * 0.6;
  return col;
}
`;

export const AGX = `
const mat3 R2020_SRGB = mat3(vec3(1.6605, -0.1246, -0.0182), vec3(-0.5876, 1.1329, -0.1006), vec3(-0.0728, -0.0083, 1.1187));
const mat3 SRGB_R2020 = mat3(vec3(0.6274, 0.0691, 0.0164), vec3(0.3293, 0.9195, 0.0880), vec3(0.0433, 0.0113, 0.8956));
vec3 agxCurve(vec3 x){ vec3 x2 = x * x, x4 = x2 * x2; return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232; }
vec3 agx(vec3 c, float punch){
  const mat3 IN = mat3(vec3(0.856627153315983, 0.137318972929847, 0.11189821299995), vec3(0.0951212405381588, 0.761241990602591, 0.0767994186031903), vec3(0.0482516061458583, 0.101439036467562, 0.811302368396859));
  const mat3 OUT = mat3(vec3(1.1271005818144368, -0.1413297634984383, -0.14132976349843826), vec3(-0.11060664309660323, 1.157823702216272, -0.11060664309660294), vec3(-0.016493938717834573, -0.016493938717834257, 1.2519364065950405));
  c = IN * (SRGB_R2020 * c);
  c = clamp((log2(max(c, 1e-10)) + 12.47393) / 16.5, 0.0, 1.0);
  c = agxCurve(c);
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  vec3 p = pow(max(c, 0.0), vec3(mix(1.0, 1.35, punch)));
  c = l + mix(1.0, 1.4, punch) * (p - l);
  c = OUT * c;
  c = pow(max(c, 0.0), vec3(2.2));
  return clamp(R2020_SRGB * c, 0.0, 1.0);
}
vec3 srgb(vec3 c){ return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
`;

export const VS_TRI = `
in vec3 position;
void main(){ gl_Position = vec4(position.xy, 0.0, 1.0); }
`;

/* Glyph lookup in the 8×8 atlas: red = the sharp glyph, green = its glow. */
export const GLYPH = `
vec2 glyph(float id, vec2 c, vec2 dx, vec2 dy){
  vec2 uv = (vec2(mod(id, 8.0), floor(id / 8.0)) + 0.1 + clamp(c, 0.0, 1.0) * 0.8) / 8.0;
  return textureGrad(uAtlas, uv, dx * 0.1, dy * 0.1).rg;
}
`;

/* The eye camera: the eye has radius 1 at the origin, the camera sits at distance D, uEye = (centre px, radius px). */
export const EYECAM = `
const float D = 7.0, PI2 = 6.2831853;
mat3 camRot(){ float cy = cos(uCam.x), sy = sin(uCam.x), cp = cos(uCam.y), sp = sin(uCam.y);
  return mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy) * mat3(1.0, 0.0, 0.0, 0.0, cp, -sp, 0.0, sp, cp); }
void camera(out vec2 uv, out vec3 ro, out vec3 rd){
  uv = (gl_FragCoord.xy - uEye.xy) / uEye.z;
  mat3 Rc = camRot();
  ro = Rc * vec3(0.0, 0.0, D); rd = Rc * normalize(vec3(uv * 1.0104, -D));
}
`;

/* Data rings in the plane with normal uRingN: up to 8 rings (radius, value 0..1, kind, flash); kind 0 gauge, 1 gold gauge, 2 orbit, 3 countdown. */
export const RINGS = `
vec3 rings(vec3 ro, vec3 rd, out float tR){
  tR = 1e9;
  if (uRingK < 0.5) return vec3(0.0);
  vec3 n = uRingN;
  float den = dot(rd, n);
  if (abs(den) < 1e-4) return vec3(0.0);
  float t = -dot(ro, n) / den;
  if (t <= 0.0) return vec3(0.0);
  tR = t;
  vec3 x = ro + rd * t, ax = normalize(cross(n, vec3(0.0, 0.0, 1.0)) + vec3(1e-5, 0.0, 0.0)), ay = cross(n, ax);
  vec2 q = vec2(dot(x, ax), dot(x, ay));
  float rr = length(q), px = fwidth(rr) + 1e-4;
  float a = fract(0.25 - atan(q.y, q.x) / PI2);
  float face = smoothstep(0.0, 0.25, abs(den));
  float depth = mix(0.45, 1.0, smoothstep(-1.5, 1.5, x.z));
  vec3 c = vec3(0.0);
  for (int i = 0; i < 8; i++) {
    if (float(i) >= uRingK) break;
    vec4 R = uRing[i];
    float d = abs(rr - R.x), kind = R.z;
    if (d > 0.12) continue;
    float line = smoothstep(px * 1.3, 0.0, d);
    if (kind > 1.5 && kind < 2.5) {
      float dash = step(0.55, fract(a * 72.0 - uSpin * 11.46));
      c += MINT * line * (0.05 + 0.1 * dash) * (0.6 + 0.6 * uAct);
      continue;
    }
    vec3 hue = kind > 0.5 && kind < 1.5 ? GOLD : kind > 2.5 ? mix(MINT, ICE, 0.35) : MINT;
    float v = clamp(R.y, 0.0, 1.0);
    float lit = step(a, v);
    float trail = lit * mix(0.2, 1.0, pow(clamp(a / max(v, 1e-3), 0.0, 1.0), 2.2));
    float tick = step(fract(a * 60.0), 0.07) * smoothstep(px, 0.0, d - 0.02) * 0.4;
    float core = smoothstep(px * 1.2 + 0.005, 0.0, d);
    float da = (a - v) * rr * PI2, head = exp(-length(vec2(da, d)) / 0.028) * step(0.004, v);
    c += hue * (core * trail * 1.2 + exp(-d / 0.022) * trail * 0.2) * (1.0 + 2.5 * R.w);
    c += mix(hue, vec3(1.0), 0.55) * head * 2.4;
    c += vec3(0.03, 0.06, 0.045) * line * (1.0 - lit) + hue * tick * (0.25 + 0.8 * lit);
  }
  return c * face * depth;
}
`;

/* Everything an eye shader starts with: the shared uniforms, palette, noise, studio, glyphs, camera and rings. */
export const HEAD = `precision highp float;
uniform vec2 uRes; uniform vec3 uEye; uniform vec2 uCam; uniform vec3 uGaze; uniform vec4 uLid; uniform vec4 uFlash;
uniform float uPupil, uTime, uAct, uQ, uSpin, uRingK, uSleep, uHalo; uniform sampler2D uAtlas; uniform vec3 uRingN; uniform vec4 uRing[8];
out vec4 oCol;
${PAL}
${NOISE}
${ENV}
${GLYPH}
${EYECAM}
${RINGS}
mat3 basis(vec3 g){ vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), g)); return mat3(r, cross(g, r), g); }
vec3 clean(vec3 c){ return any(isnan(c)) || any(isinf(c)) ? vec3(0.0) : max(c, 0.0); }
`;
