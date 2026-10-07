/* The living field behind everything: three depths of katakana bokeh with pointer and scroll parallax, press ripples, a glow around the eye; density and drift follow the data. */
import { PAL, NOISE } from "./glsl.js";

const FS = `precision highp float;
uniform vec2 uRes, uPar, uPan; uniform float uTime, uAct, uDrift, uZoom, uScroll, uAura, uK; uniform vec3 uEye; uniform vec4 uRip[4]; uniform sampler2D uAtlas;
out vec4 o;
${PAL}
${NOISE}
vec2 glyph(float id, vec2 c, float bl){
  vec2 uv = (vec2(mod(id, 8.0), floor(id / 8.0)) + 0.1 + clamp(c, 0.0, 1.0) * 0.8) / 8.0;
  return textureGrad(uAtlas, uv, vec2(bl * 0.1, 0.0), vec2(0.0, bl * 0.1)).rg;
}
void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
  float ring = 0.0;
  vec2 push = vec2(0.0);
  for (int i = 0; i < 4; i++) {
    vec4 R = uRip[i];
    float age = uTime - R.z;
    if (R.w <= 0.0 || age < 0.0 || age > 1.6) continue;
    vec2 d = uv - R.xy;
    float l = length(d), w = 0.035 + age * 0.06;
    float k = exp(-pow((l - age * 0.75) / w, 2.0)) * (1.0 - age / 1.6) * R.w;
    ring += k; push += d / max(l, 1e-3) * k * 0.012;
  }
  vec3 c = vec3(0.0);
  float dens = 0.08 + 0.1 * uAct;
  for (int l = 0; l < 3; l++) {
    float fl = float(l), d = 1.0 + fl * 1.3, k = 1.0 + (uZoom - 1.0) / d;
    vec2 q = (uv - push - uPan / d) / k - (uPar * 0.05 + vec2(0.0, -uScroll * 0.35)) / d;
    float sc = mix(2.6, 8.0, fl * 0.5);
    vec2 p = q * sc + vec2(fl * 0.37, -uDrift * mix(0.012, 0.04, fl * 0.5));
    vec2 ci = floor(p), cf = fract(p);
    float h = h12(ci + fl * 31.0);
    if (h > dens * (1.0 + 0.6 * fl)) continue;
    vec2 off = vec2(h12(ci + 7.0), h12(ci + 13.0)) * 0.4 + 0.3;
    vec2 gu = (cf - off) * mix(2.2, 3.0, fl * 0.5) + 0.5;
    float mask = 1.0 - smoothstep(0.3, 0.5, length(gu - 0.5));
    float bl = fl < 0.5 ? 0.62 : fl < 1.5 ? 0.16 : 0.3;
    vec2 g = glyph(floor(h12(ci + 3.0) * 60.0), gu, bl);
    float tw = 0.55 + 0.45 * sin(uTime * (0.3 + 1.6 * h / dens) + h * 600.0);
    float lit = fl < 0.5 ? 0.0012 : fl < 1.5 ? 0.009 : 0.0022;
    c += mix(VIO, MINT, step(dens * 0.22, h)) * (g.x * 0.7 + g.y * 0.8) * mask * tw * lit * (0.55 + 0.9 * uAct);
  }
  c *= 1.0 + 4.0 * ring;
  c += MINT * ring * 0.004;
  vec2 e = (gl_FragCoord.xy - uEye.xy) / max(uEye.z, 1.0);
  float er = length(e * vec2(1.0, 1.15));
  c += (MINT * 0.55 + VIO * 0.45) * uAura * 0.012 * (0.5 + uAct) * exp(-1.5 * max(er - 0.9, 0.0));
  c += (MINT * 0.4 + VIO * 0.6) * 0.0006 * exp(-length((uv - vec2(0.0, 0.62)) * vec2(0.8, 2.4)) * 1.7) * (0.6 + 0.7 * uAct);
  o = vec4(max(c, 0.0), 1.0);
}`;

/* The field as a full-screen pass; set(state) feeds it every frame. */
export function createField({ T, quad }, atlasTex) {
  const U = { uRes: { value: new T.Vector2() }, uPar: { value: new T.Vector2() }, uPan: { value: new T.Vector2() }, uTime: { value: 0 }, uAct: { value: 0 }, uDrift: { value: 0 },
    uZoom: { value: 1 }, uScroll: { value: 0 }, uAura: { value: 1 }, uK: { value: 1 }, uEye: { value: new T.Vector3() }, uRip: { value: [0, 1, 2, 3].map(() => new T.Vector4()) }, uAtlas: { value: atlasTex } };
  const mesh = quad(FS, U);
  return { U, mesh };
}
