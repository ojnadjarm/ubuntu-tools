/* Shared GLSL for the eye lab: hashes, periodic gradient noise, the procedural studio environment, AgX and sRGB output. */

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

/* Studio of the eye: one bright softbox key with a mullion (the dashboard, reflected), a mint floor strip, a violet fill; HDR values, blur spreads the key's energy. */
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

/* Everything an eye shader starts with: the shared uniforms, palette, noise, studio, glyph lookup, camera and the far glyph bokeh. */
export const HEAD = `precision highp float;
uniform vec2 uRes; uniform vec3 uEye; uniform vec2 uCam; uniform vec3 uGaze; uniform vec4 uLid; uniform vec4 uFlash;
uniform float uPupil, uTime, uAct, uQ; uniform sampler2D uAtlas;
out vec4 oCol;
${PAL}
${NOISE}
${ENV}
const float D = 7.0, PI2 = 6.2831853;
mat3 basis(vec3 g){ vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), g)); return mat3(r, cross(g, r), g); }
vec2 glyph(float id, vec2 c, vec2 dx, vec2 dy){
  vec2 uv = (vec2(mod(id, 8.0), floor(id / 8.0)) + 0.1 + c * 0.8) / 8.0;
  return textureGrad(uAtlas, uv, dx * 0.1, dy * 0.1).rg;
}
vec3 clean(vec3 c){ return any(isnan(c)) || any(isinf(c)) ? vec3(0.0) : max(c, 0.0); }
void camera(out vec2 uv, out vec3 ro, out vec3 rd, float zoom){
  uv = (gl_FragCoord.xy - uEye.xy) / uEye.z * zoom;
  float cy = cos(uCam.x), sy = sin(uCam.x), cp = cos(uCam.y), sp = sin(uCam.y);
  mat3 Rc = mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy) * mat3(1.0, 0.0, 0.0, 0.0, cp, -sp, 0.0, sp, cp);
  ro = Rc * vec3(0.0, 0.0, D); rd = Rc * normalize(vec3(uv * 1.0104, -D));
}
vec3 bokeh(vec2 uv){
  vec3 c = vec3(0.0);
  for (int l = 0; l < 2; l++) {
    float fl = float(l), sc = mix(3.0, 5.0, fl);
    vec2 p = uv * sc + uCam * mix(8.0, 16.0, fl) + vec2(fl * 0.37, -uTime * mix(0.025, 0.05, fl));
    vec2 ci = floor(p), cf = fract(p);
    float h = h12(ci + fl * 31.0);
    if (h > 0.2) continue;
    vec2 o = vec2(h12(ci + 7.0), h12(ci + 13.0)) * 0.4 + 0.3;
    vec2 gu = (cf - o) * mix(2.4, 3.2, fl) + 0.5;
    float mask = 1.0 - smoothstep(0.3, 0.5, length(gu - 0.5));
    float bl = mix(0.34, 0.2, fl);
    vec2 g = glyph(floor(h12(ci + 3.0) * 61.0), clamp(gu, 0.0, 1.0), vec2(bl, 0.0), vec2(0.0, bl));
    float tw = 0.55 + 0.45 * sin(uTime * (0.4 + 2.0 * h) + h * 60.0);
    c += mix(VIO, MINT, step(0.09, h)) * (g.x + g.y * 0.5) * mask * tw * mix(0.035, 0.06, fl);
  }
  return c * (0.6 + 0.6 * uAct);
}
`;
