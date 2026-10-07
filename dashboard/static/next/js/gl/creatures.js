/* Agent creatures on the stage: instanced ray-marched 3D bodies from each agent's genome, lit by the studio and the eye; they breathe, blink, glance at the eye, leap when they finish; glyph streams run from the eye to the working ones. */
import { PAL } from "./glsl.js";
import { project, ringPoint, D } from "./cam.js";
import { params } from "../avatar.js";

const VS = `precision highp float;
in vec3 position;
in vec4 iPos, iCol, iShp, iMor, iDec, iSt, iMo, iLt;
uniform vec2 uRes;
out vec2 vL;
flat out vec4 vCol, vShp, vMor, vDec, vSt, vMo, vLt;
flat out float vPx, vFade;
const float Q = 2.2;
void main(){
  vec2 px = iPos.xy + position.xy * iPos.z * 0.5 * Q;
  gl_Position = vec4(px / uRes * 2.0 - 1.0, 0.0, 1.0);
  vL = position.xy * Q;
  vPx = 2.0 / max(iPos.z, 1.0);
  vFade = iPos.w;
  vCol = iCol; vShp = iShp; vMor = iMor; vDec = iDec; vSt = iSt; vMo = iMo; vLt = iLt;
}`;

const FS = `precision highp float;
in vec2 vL;
flat in vec4 vCol, vShp, vMor, vDec, vSt, vMo, vLt;
flat in float vPx, vFade;
uniform float uTime; uniform sampler2D uAtlas;
out vec4 o;
${PAL}
float W, H, LOB, WOB, PH, SQ, NE, TOP, SX, SY, ES, EY, SEED;
vec3 EC0, EC1, EC2; bool OPEN;
float hs(float x){ return fract(sin(x * 91.345 + SEED * 311.7) * 43758.5453); }
float smin(float a, float b, float k){ float h = max(k - abs(a - b), 0.0) / k; return min(a, b) - h * h * k * 0.25; }
float sdEll(vec3 p, vec3 r){ float k0 = length(p / r), k1 = length(p / (r * r)); return k0 * (k0 - 1.0) / max(k1, 1e-5); }
float sdCap(vec3 p, vec3 a, vec3 b, float r){ vec3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) - r; }
float sdCone(vec3 p, vec3 a, vec3 b, float r1, float r2){ vec3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) - mix(r1, r2, h); }
float body(vec3 p){
  float rho = length(vec2(p.x / W, p.z / (W * 0.8))), y = p.y / H;
  float a = atan(y, max(rho, 1e-4)), c = abs(cos(a)), s = abs(sin(a));
  float k = pow(pow(c, SQ) + pow(s, SQ), -1.0 / SQ);
  float rr = k * (1.0 + WOB * sin(LOB * a + PH)) * mix(0.96, 1.05, smoothstep(0.25, -0.35, y));
  return (length(vec2(rho, y)) - rr) * min(W * 0.8, H) * 0.86;
}
float feet(vec3 p){ return sdEll(vec3(abs(p.x), p.y, p.z) - vec3(0.4 * W, -0.98 * H, 0.2), vec3(0.25, 0.13, 0.21)); }
float eyes(vec3 p){
  if (!OPEN) return 1e3;
  float d = length(p - EC0) - ES;
  if (NE > 1.5) d = min(d, length(p - EC1) - ES);
  if (NE > 2.5) d = min(d, length(p - EC2) - ES);
  return d;
}
vec3 antTip(){ return vec3(0.55 * W + 0.26 * vDec.w, H + 0.44 + 0.16 * hs(2.0), 0.06); }
float topper(vec3 p, out float tip){
  tip = 1e3;
  vec3 q = vec3(abs(p.x), p.y, p.z);
  if (TOP < 0.5) {
    vec3 b = vec3(0.3 * W, 0.86 * H, 0.0), t = antTip(), m = vec3(mix(b.x, t.x, 0.35), mix(b.y, t.y, 0.7), 0.03);
    tip = length(q - t) - 0.11;
    return min(min(sdCap(q, b, m, 0.036), sdCap(q, m, t, 0.03)), tip);
  }
  if (TOP < 1.5) { vec3 e = q; e.z *= 1.9; return sdCone(e, vec3(0.34 * W, 0.74 * H, 0.0), vec3(0.76 * W, H + 0.3, 0.0), 0.2, 0.03) * 0.55; }
  if (TOP < 2.5) { vec3 a = vec3(0.4 * W, 0.8 * H, 0.1), m = vec3(0.6 * W, H + 0.14, 0.08), t = vec3(0.56 * W, H + 0.44, 0.04);
    return min(sdCone(q, a, m, 0.11, 0.07), sdCone(q, m, t, 0.07, 0.015)); }
  if (TOP < 3.5) {
    float st = sdCap(p, vec3(0.0, 0.9 * H, 0.0), vec3(0.0, H + 0.24, 0.0), 0.028);
    vec3 l = q - vec3(0.17, H + 0.3, 0.0); float c = 0.866, s = 0.5; l.xy = mat2(c, -s, s, c) * l.xy;
    return min(st, sdEll(l, vec3(0.18, 0.07, 0.045)));
  }
  return 1e3;
}
float map(vec3 p){
  p = vec3(p.x * SX, p.y * SY, p.z * SX);
  float t, d = smin(body(p), feet(p), 0.07);
  d = smin(d, eyes(p), 0.035);
  d = smin(d, topper(p, t), 0.05);
  return d / max(SX, SY);
}
vec3 nrm(vec3 p){ const vec2 e = vec2(1.0, -1.0) * 0.0025;
  return normalize(e.xyy * map(p + e.xyy) + e.yyx * map(p + e.yyx) + e.yxy * map(p + e.yxy) + e.xxx * map(p + e.xxx)); }
float stroke(float d, float w, float aa){ return smoothstep(w + aa, w - aa, d); }
float arcD(vec2 p, vec2 c, float hw, float bow){
  float x = clamp(p.x - c.x, -hw, hw), u = x / hw, y = c.y + bow * (1.0 - u * u), sl = -2.0 * bow * u / hw;
  return length(vec2(p.x - c.x - x, (p.y - y) / sqrt(1.0 + sl * sl)));
}
float segD(vec2 p, vec2 a, vec2 b){ vec2 pa = p - a, ba = b - a; return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)); }
vec2 glyphUV(float id, vec2 c){ return (vec2(mod(id, 8.0), floor(id / 8.0)) + 0.1 + clamp(1.0 - c, 0.0, 1.0) * 0.8) / 8.0; }

void main(){
  W = vCol.w; H = vShp.x; LOB = vShp.y; WOB = vShp.z; PH = vShp.w; SQ = vMor.x; NE = vMor.y; TOP = vMor.w; SEED = vDec.z;
  float state = vSt.x, blink = vSt.y, jump = vMo.x, squash = vMo.y, yaw = vMo.z, pulse = vMo.w, aa = vPx * 1.2;
  OPEN = state < 0.5 || (state > 1.5 && state < 2.5);
  SY = 1.0 / (1.0 + squash); SX = 1.0 / (1.0 - 0.5 * squash);
  ES = NE < 1.5 ? 0.38 : NE < 2.5 ? 0.28 : 0.22; EY = NE < 1.5 ? 0.235 : 0.176;
  float ex = NE < 1.5 ? 0.0 : NE < 2.5 ? 0.38 * W : 0.5 * W;
  float zf0 = 0.8 * W * sqrt(max(0.05, 1.0 - pow(ex / W, 2.0) - pow(EY / H, 2.0))), zfc = 0.8 * W * sqrt(max(0.05, 1.0 - pow(EY / H, 2.0)));
  EC0 = NE < 1.5 ? vec3(0.0, EY, zfc - 0.46 * ES) : vec3(-ex, EY, zf0 - 0.46 * ES);
  EC1 = vec3(ex, EY, zf0 - 0.46 * ES); EC2 = vec3(0.0, EY, zfc - 0.46 * ES);

  vec3 base = vCol.rgb, lite = mix(base, vec3(1.0), 0.5), deep = base * 0.22;
  vec2 L2 = vL - vec2(0.0, jump);
  vec4 acc = vec4(0.0);

  vec2 g = (vL - vec2(0.0, -1.14 * H)) / vec2(1.02, 0.25);
  float gr = length(g), gd = abs(gr - 1.0) * mix(0.25, 1.02, abs(g.x) / max(gr, 1e-4)), ga = atan(g.y, g.x);
  if (state < 0.5) {
    float dash = step(0.5, fract(ga * 3.8197 - uTime * 0.6));
    vec3 c = MINT * (stroke(gd, 0.012, aa) * (0.25 + 0.9 * dash) + exp(-gr * gr * 2.2) * 0.07);
    acc = vec4(c, 0.0);
  } else if (state < 1.5) {
    acc = vec4(MINT * exp(-gr * gr * 3.0) * 0.025, 0.0);
  } else if (state < 2.5) {
    acc = vec4(GOLD * (stroke(gd, 0.014, aa) * (0.7 + 0.3 * sin(uTime * 3.0)) + exp(-gr * gr * 2.2) * 0.06), 0.0);
  } else if (state < 3.5) {
    acc = vec4(VIO * stroke(gd, 0.01, aa) * step(0.55, fract(ga * 7.64)) * 1.2, 0.0);
  } else {
    acc = vec4(mix(MINT, ICE, 0.5) * (stroke(gd, 0.008, aa) * 0.3 + exp(-gr * gr * 3.0) * 0.02), 0.0);
  }
  if (pulse > 0.0 && pulse < 1.0) {
    float pr = 0.9 + 1.25 * pulse, pd = abs(length(L2 * vec2(1.0, 1.1)) - pr);
    acc.rgb += GOLD * (stroke(pd, 0.02 + 0.03 * pulse, aa) * 2.0 + exp(-pd / 0.08) * 0.35) * (1.0 - pulse);
  }

  float cy = cos(yaw), sy = sin(yaw);
  mat3 Ry = mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy);
  vec3 ro = Ry * vec3(L2, 4.0), rd = Ry * vec3(0.0, 0.0, -1.0);
  vec3 bc = vec3(0.0, 0.28, 0.0); float br = 1.95;
  vec3 oc = ro - bc; float b = dot(oc, rd), hh = b * b - dot(oc, oc) + br * br;
  if (hh > 0.0) {
    hh = sqrt(hh);
    float t = max(0.0, -b - hh), tf = -b + hh, dm = 1e3, tm = t;
    bool hit = false;
    for (int i = 0; i < 56; i++) {
      float d = map(ro + rd * t);
      if (d < dm) { dm = d; tm = t; }
      if (d < 0.0015) { hit = true; break; }
      t += d * 0.92;
      if (t > tf) break;
    }
    float cov = hit ? 1.0 : smoothstep(aa, 0.0, dm);
    if (cov > 0.002) {
      vec3 p = ro + rd * (hit ? t : tm), n = nrm(p), V = -rd;
      vec3 L = Ry * normalize(vec3(-0.5, 0.66, 0.58)), Le = Ry * normalize(vec3(vLt.xy, 0.45));
      vec3 ps = vec3(p.x * SX, p.y * SY, p.z * SX);
      float tip, dB = smin(body(ps), feet(ps), 0.07), dE = eyes(ps), dT = topper(ps, tip), dF = feet(ps);
      float ao = clamp(0.35 + 0.65 * map(p + n * 0.12) / 0.12, 0.0, 1.0) * clamp(0.5 + 0.5 * map(p + n * 0.3) / 0.3, 0.0, 1.0);
      vec3 alb = mix(deep * 2.2, base, smoothstep(-1.1, 0.4, ps.y));
      float spec = 0.55, rough = 50.0, emit = 0.0;
      vec3 ecol = vec3(0.0);
      if (dF < dB + 0.01 && ps.y < -0.8 * H) alb = deep * 1.6;
      if (dT < min(dB, dE) - 0.002) {
        alb = TOP > 1.5 && TOP < 2.5 ? GOLD * 0.9 : TOP > 2.5 && TOP < 3.5 ? MINT * 0.55 : deep * 1.8;
        if (tip < 0.004) { alb = vec3(0.85, 1.0, 0.92); emit = state < 0.5 ? 2.2 + 1.2 * sin(uTime * 2.4 + SEED * 6.0) : 0.25; ecol = state < 0.5 ? MINT : vec3(0.8, 1.0, 0.9); }
      }
      bool onEye = OPEN && dE < min(dB, dT) + 0.004;
      if (onEye) {
        vec3 ce = length(ps - EC0) < ES + 0.02 ? EC0 : length(ps - EC1) < ES + 0.02 ? EC1 : EC2;
        vec3 q = normalize(ps - ce), lk = normalize(vec3(vSt.zw, 1.0));
        float dl = dot(q, lk);
        alb = mix(vec3(0.86, 0.95, 0.9), vec3(0.004, 0.02, 0.012), smoothstep(0.76, 0.8, dl));
        alb = mix(alb, base * 0.45, smoothstep(0.62, 0.7, dl) * (1.0 - smoothstep(0.76, 0.8, dl)) * 0.75);
        spec = 1.4; rough = 180.0;
        float lid = ce.y + ES * (1.0 - 2.1 * blink);
        if (ps.y > lid) { alb = mix(deep * 2.2, base, 0.8); spec = 0.5; rough = 40.0; }
      } else if (dB < dT + 0.003 && n.z > -0.2) {
        vec2 f = ps.xy;
        float my = NE < 1.5 ? -0.44 : NE < 2.5 ? -0.4 : -0.34;
        if (vDec.y > 0.5) for (int i = 0; i < 4; i++) {
          vec2 sc = vec2(-0.82 + 1.64 * hs(float(i) * 3.1), -0.94 + 0.76 * hs(float(i) * 7.3 + 1.0));
          float sr = 0.09 + 0.14 * hs(float(i) * 5.7 + 2.0);
          alb = mix(alb, lite, smoothstep(sr + aa, sr - aa, length(f - sc)) * 0.35);
        }
        alb = mix(alb, lite, smoothstep(1.0 + aa * 3.0, 1.0 - aa * 3.0, length((f - vec2(0.0, -0.88 * H)) / vec2(0.59 * W, 0.35))) * 0.3);
        vec2 gu = (f - vec2(0.0, -0.74 * H)) / 0.3 + 0.5;
        if (all(greaterThan(gu, vec2(0.0))) && all(lessThan(gu, vec2(1.0)))) alb = mix(alb, deep, texture(uAtlas, glyphUV(vMor.z, gu)).r * 0.75);
        vec2 bl = vec2(abs(f.x), f.y) - vec2(0.64 * W, my + 0.09);
        alb = mix(alb, vec3(1.0, 0.36, 0.52), smoothstep(1.0, 0.6, length(bl / vec2(0.15, 0.09))) * 0.45);
        float ink = 0.0, hw = 0.176;
        if (state > 1.5 && state < 2.5) ink = stroke(arcD(f, vec2(0.0, my - 0.09), hw, 0.088), 0.035, aa);
        else if (vDec.x < 0.5 || !OPEN) ink = stroke(arcD(f, vec2(0.0, my), hw, -0.088), 0.035, aa);
        else if (vDec.x < 1.5) ink = max(stroke(arcD(f, vec2(-0.1, my), 0.1, -0.06), 0.032, aa), stroke(arcD(f, vec2(0.1, my), 0.1, -0.06), 0.032, aa));
        else if (vDec.x < 2.5) ink = smoothstep(1.0 + aa * 8.0, 1.0 - aa * 8.0, length((f - vec2(0.0, my - 0.03)) / vec2(0.1, 0.118)));
        else { ink = stroke(arcD(f, vec2(0.0, my), hw, -0.088), 0.035, aa);
          float fg = segD(f, vec2(0.09, my - 0.07), vec2(0.13, my - 0.15)); alb = mix(alb, vec3(0.95), stroke(fg, 0.022, aa)); }
        if (!OPEN) {
          float bow = state < 1.5 ? 0.35 : state < 3.5 ? 0.0 : -0.3;
          ink = max(ink, stroke(arcD(f, vec2(NE < 1.5 ? 0.0 : -ex, EY), 0.8 * ES, bow * ES), 0.038, aa));
          if (NE > 1.5) ink = max(ink, stroke(arcD(f, vec2(ex, EY), 0.8 * ES, bow * ES), 0.038, aa));
          if (NE > 2.5) ink = max(ink, stroke(arcD(f, vec2(0.0, EY), 0.8 * ES, bow * ES), 0.038, aa));
        }
        if (state > 1.5 && state < 2.5) for (int i = 0; i < 3; i++) {
          if (float(i) >= NE) break;
          float x = NE < 1.5 ? 0.0 : i == 0 ? -ex : i == 1 ? ex : 0.0;
          ink = max(ink, stroke(segD(f, vec2(x - ES, EY + 1.25 * ES), vec2(x + 0.6 * ES, EY + 0.8 * ES)), 0.03, aa));
        }
        alb = mix(alb, vec3(0.0015, 0.007, 0.004), ink);
        if (ink > 0.5) { spec = 0.2; rough = 20.0; }
      }
      float dif = max(0.0, (dot(n, L) + 0.4) / 1.4);
      vec3 col = alb * (0.05 + 1.05 * dif * vec3(1.0, 0.97, 0.92));
      col += alb * MINT * max(0.0, dot(n, Le)) * 0.55 * vLt.z;
      col += alb * VIO * max(0.0, -n.y) * 0.12;
      float fr = pow(1.0 - max(dot(n, V), 0.0), 3.0);
      col += (onEye ? vec3(0.2) : lite) * fr * 0.35;
      col += MINT * fr * 0.25 * vLt.z * max(0.0, dot(n.xy, normalize(vLt.xy + 1e-4)));
      col *= ao;
      vec3 hv = normalize(L + V);
      col += vec3(1.0, 0.98, 0.94) * pow(max(dot(n, hv), 0.0), rough) * spec * (onEye ? 3.0 : 1.0);
      col += ecol * emit;
      acc.rgb = col * cov + acc.rgb * (1.0 - cov);
      acc.a = cov;
    }
  }
  o = vec4(acc.rgb, acc.a) * vFade;
}`;

const SVS = `precision highp float;
in vec3 position;
in vec4 aS;
uniform vec2 uRes; uniform float uTime; uniform vec4 uA, uB[8], uC[8];
out float vG; out vec3 vCol; out float vA;
void main(){
  int i = int(aS.x);
  vec4 B = uB[i], C = uC[i];
  float f = fract(aS.y + uTime * (0.22 + 0.1 * aS.w)), k = f * f * (3.0 - 2.0 * f);
  vec2 a = uA.xy, b = B.xy, d = b - a, nn = normalize(vec2(-d.y, d.x) + 1e-5);
  vec2 p = mix(a, b, k) + nn * sin(k * 3.14159) * length(d) * (0.12 + 0.1 * (aS.w - 0.5));
  float inEye = smoothstep(uA.z * 0.92, uA.z * 1.08, length(p - a)), nearB = smoothstep(B.z * 0.25, B.z * 0.7, length(p - b));
  vA = C.w * inEye * nearB * sin(f * 3.14159);
  gl_Position = vec4(p / uRes * 2.0 - 1.0, 0.0, 1.0);
  gl_PointSize = vA > 0.001 ? uA.w * (0.8 + 0.5 * aS.w) : 0.0;
  vG = mod(aS.z + floor(uTime * 3.0 + aS.y * 17.0), 61.0);
  vCol = C.rgb;
}`;
const SFS = `precision highp float;
in float vG; in vec3 vCol; in float vA;
uniform sampler2D uAtlas;
out vec4 o;
void main(){
  vec2 q = vec2(1.0 - gl_PointCoord.x, gl_PointCoord.y);
  vec2 g = texture(uAtlas, (vec2(mod(vG, 8.0), floor(vG / 8.0)) + 0.1 + q * 0.8) / 8.0).rg;
  o = vec4(vCol * (g.x * 1.4 + g.y * 0.5) * vA, 0.0);
}`;

const STATE = { working: 0, done: 1, error: 2, stale: 3, sleep: 4 }, TOP = { ant: 0, ears: 1, horns: 2, sprout: 3, none: 4 }, MOUTH = { smile: 0, cat: 1, o: 2, fang: 3 };
const NAMES = ["iPos", "iCol", "iShp", "iMor", "iDec", "iSt", "iMo", "iLt"], MAX = 24, PER = 26;
const lin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
function hsl(h, s, l) {
  const a = s * Math.min(l, 1 - l), f = (n) => { const k = (n + h / 30) % 12; return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)); };
  return [lin(f(0)), lin(f(8)), lin(f(4))];
}
const easeBack = (x) => { const c = 1.5; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };

/* The creature layer: set(list) with {id, state, ring: {r, a}, size, min, tag}; a hook for the stage (step, back, front). */
export function createCreatures({ T, r }, tex, st) {
  const blend = { transparent: true, depthTest: false, depthWrite: false, blending: T.CustomBlending, blendSrc: T.OneFactor, blendDst: T.OneMinusSrcAlphaFactor };
  const U = { uRes: { value: new T.Vector2() }, uTime: { value: 0 }, uAtlas: { value: tex } };
  const mat = new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: VS, fragmentShader: FS, uniforms: U, ...blend });
  const layer = () => {
    const g = new T.InstancedBufferGeometry(), A = {};
    g.setAttribute("position", new T.BufferAttribute(new Float32Array([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]), 3));
    g.setIndex([0, 1, 2, 0, 2, 3]);
    NAMES.forEach((k) => { A[k] = new T.InstancedBufferAttribute(new Float32Array(MAX * 4), 4); g.setAttribute(k, A[k]); });
    g.instanceCount = 0;
    const m = new T.Mesh(g, mat);
    m.frustumCulled = false;
    return { g, A, m, n: 0 };
  };
  const back = layer(), front = layer();

  const SU = { uRes: U.uRes, uTime: U.uTime, uAtlas: U.uAtlas, uA: { value: new T.Vector4() },
    uB: { value: Array.from({ length: 8 }, () => new T.Vector4()) }, uC: { value: Array.from({ length: 8 }, () => new T.Vector4()) } };
  const sg = new T.BufferGeometry(), sa = new Float32Array(8 * PER * 4);
  for (let i = 0; i < 8; i++) for (let j = 0; j < PER; j++) { const o = (i * PER + j) * 4; sa[o] = i; sa[o + 1] = j / PER; sa[o + 2] = (i * 13 + j * 7) % 61; sa[o + 3] = ((j * 2654435761) >>> 0) % 1000 / 1000; }
  sg.setAttribute("position", new T.BufferAttribute(new Float32Array(8 * PER * 3), 3));
  sg.setAttribute("aS", new T.BufferAttribute(sa, 4));
  const streams = new T.Points(sg, new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: SVS, fragmentShader: SFS, uniforms: SU, transparent: true, depthTest: false, depthWrite: false, blending: T.AdditiveBlending }));
  streams.frustumCulled = false;

  const all = new Map(), fx = document.getElementById("fx");
  let n = [0, 0.3, 0.954], spin = false, list = [], nStream = 0, lastT = 0;

  function make(s, i, t) {
    const P = params(s.id), c = { id: s.id, P, col: hsl(P.h, 0.72, 0.6), e: 0, eGoal: 1, delay: t + 0.05 + i * 0.07, state: s.state, jump: -9, pulse: -9,
      blinkAt: t + 1 + P.seed * 4, blinkT: -9, glanceAt: t + 2 + P.seed * 6, glanceTo: -9, spec: s, q: null, tag: null };
    return c;
  }
  const C = {};
  /* The creatures of the scene; ring normal nn; turning with the stage spin when turn is true. */
  C.set = (next, { normal = n, turn = false, fresh = false } = {}) => {
    const t = st.clock(), ids = new Set(next.map((s) => s.id));
    n = normal; spin = turn; list = next;
    for (const c of all.values()) if (!ids.has(c.id) || fresh) { c.eGoal = 0; c.delay = t; c.gone = true; }
    next.forEach((s, i) => {
      let c = all.get(s.id);
      if (c && c.gone && fresh) { all.delete(s.id); if (c.tag) c.tag.remove(); c = null; }
      if (!c) { c = make(s, i, t); all.set(s.id, c); }
      else {
        c.gone = false; c.eGoal = 1;
        if (c.state === "working" && s.state === "done" && !st.still()) { c.jump = t; c.pulse = t; c.cheer = true; }
        if (c.state !== "error" && s.state === "error" && !st.still()) c.pulse = t;
      }
      c.state = s.state; c.spec = s;
      if (c.tag) c.tag.innerHTML = s.tag || "";
    });
    st.wake(0);
  };
  C.count = () => all.size;

  /* Animation state; true while anything must run at full rate. */
  C.step = (t, dt) => {
    lastT = t;
    let hot = false;
    const calm = st.still();
    for (const c of [...all.values()]) {
      if (t >= c.delay) {
        const k = calm ? 1 : Math.min(1, dt / (c.eGoal ? 0.55 : 0.35));
        c.e = c.eGoal ? Math.min(1, c.e + k) : Math.max(0, c.e - k);
      }
      if (c.e !== c.eGoal) hot = true;
      if (!c.eGoal && c.e <= 0) { all.delete(c.id); if (c.tag) c.tag.remove(); continue; }
      if (t - c.jump < 0.8 || t - c.pulse < 1.3) hot = true;
      if (t > c.blinkAt) { c.blinkT = t; c.blinkAt = t + 2.2 + ((c.P.seed * 7.31 + t) % 1) * 4.5; }
      if (t > c.glanceAt) { c.glanceTo = t + 1.3; c.glanceAt = t + 4 + ((c.P.seed * 3.7 + t * 0.61) % 1) * 6; }
    }
    return hot;
  };

  function place(S) {
    const E = st.E, cam = st.life.cam, turn = spin && !st.still() ? st.spin / (Math.PI * 2) : 0, t = lastT, k = S.k, H = innerHeight;
    const out = [];
    let si = 0;
    for (const c of all.values()) {
      const s = c.spec, e = c.e, ee = easeBack(Math.min(1, e));
      if (e <= 0.001 || !s.ring) continue;
      const p0 = ringPoint(s.ring.r, s.ring.a + turn * (s.dir || 1), n), p = [p0[0] * ee, p0[1] * ee + (1 - ee) * 0.05, p0[2] * ee];
      const q = project(p, E, cam), size = Math.max(s.min || 0, (s.size || 0.5) * q.s) * Math.min(1, e * 1.4);
      const dx = E.x - q.x, dy = q.y - E.y, dl = Math.hypot(dx, dy) || 1, dir = [dx / dl, -dy / dl];
      const jf = (t - c.jump) / 0.75, jump = jf >= 0 && jf < 1 ? Math.sin(Math.PI * jf) * 0.62 : 0;
      const breath = c.state === "sleep" ? 0.05 * Math.sin(t * 0.9 + c.P.seed * 6) : 0.03 * Math.sin(t * 1.7 + c.P.seed * 6.28);
      const land = jf >= 0 && jf < 1.25 ? (jf < 0.12 ? -0.14 * Math.sin((jf / 0.12) * Math.PI) : jf > 0.95 ? -0.16 * Math.sin(Math.min(1, (jf - 0.95) / 0.3) * Math.PI) : 0.08 * Math.sin(jf * Math.PI)) : 0;
      const bob = c.state === "working" ? 0.06 * Math.abs(Math.sin(t * 2.6 + c.P.seed * 9)) : 0;
      const bf = t - c.blinkT, blink = bf >= 0 && bf < 0.16 ? 1 - Math.abs(bf - 0.08) / 0.08 : 0;
      const glance = t < c.glanceTo || jf >= 0 && jf < 1.6;
      const look = glance ? [dir[0] * 0.75, dir[1] * 0.6] : [0.16 * Math.sin(t * 0.37 + c.P.seed * 9), 0.1 * Math.sin(t * 0.29 + c.P.seed * 5)];
      const pf = (t - c.pulse) / 1.2;
      out.push({ c, q, size, jump: jump + bob, squash: breath + land, yaw: glance ? Math.max(-0.35, Math.min(0.35, dir[0] * 0.35)) : 0, blink, look, dir, pulse: pf >= 0 && pf < 1 ? pf : -1, e });
      if ((c.state === "working" || c.state === "error") && si < 8 && e > 0.6) {
        SU.uB.value[si].set(q.x * k, (H - q.y) * k, size * k, 0);
        const cc = c.state === "error" ? [1, 0.637, 0.133] : [0.074, 1, 0.35];
        SU.uC.value[si].set(cc[0] * 1.3, cc[1] * 1.3, cc[2] * 1.3, Math.min(1, (e - 0.6) / 0.4) * (c.state === "error" ? 0.7 : 1));
        si++;
      }
    }
    nStream = si;
    SU.uA.value.set(E.x * k, (H - E.y) * k, E.r * k, Math.max(8, Math.min(18, E.r * 0.09)) * k);
    out.sort((a, b) => b.q.z - a.q.z);
    return out;
  }
  function fill(L, arr, S) {
    const k = S.k, H = innerHeight;
    L.n = Math.min(MAX, arr.length);
    for (let i = 0; i < L.n; i++) {
      const o = arr[i], c = o.c, P = c.P, A = L.A, j = i * 4;
      const fade = Math.min(1, o.e * 1.6) * (o.q.z > D ? Math.max(0.55, 1 - (o.q.z - D) * 0.12) : 1);
      A.iPos.array.set([o.q.x * k, (H - o.q.y) * k, o.size * k, fade], j);
      A.iCol.array.set([c.col[0], c.col[1], c.col[2], P.W], j);
      A.iShp.array.set([P.Hh, P.lobes, P.wob, P.ph], j);
      A.iMor.array.set([P.sq, P.eyes, P.gi, TOP[P.topper]], j);
      A.iDec.array.set([MOUTH[P.mouth], P.spots ? 1 : 0, P.seed, P.ant.length ? P.ant[0] : 0.5], j);
      A.iSt.array.set([STATE[c.state] ?? 0, o.blink, o.look[0], o.look[1]], j);
      A.iMo.array.set([o.jump, o.squash, o.yaw, o.pulse], j);
      A.iLt.array.set([o.dir[0], o.dir[1], c.state === "sleep" ? 0.35 : 1, 0], j);
    }
    NAMES.forEach((nm) => { L.A[nm].needsUpdate = true; });
    L.g.instanceCount = L.n;
  }
  function tags(arr) {
    for (const o of arr) {
      const c = o.c, s = c.spec;
      if (!s.tag || !fx) continue;
      if (!c.tag) { c.tag = document.createElement("div"); c.tag.innerHTML = s.tag; fx.appendChild(c.tag); }
      const cls = "otag " + c.state + (s.big ? " lg" : ""), tf = `translate3d(${o.q.x.toFixed(1)}px,${(o.q.y + o.size * 0.66).toFixed(1)}px,0) translateX(-50%)`, op = Math.min(1, o.e * 1.3).toFixed(2);
      if (c.tag.className !== cls) c.tag.className = cls;
      if (c.tagT !== tf) { c.tag.style.transform = c.tagT = tf; }
      if (c.tagO !== op) { c.tag.style.opacity = c.tagO = op; }
    }
  }

  let placed = [];
  C.back = (S) => {
    if (!all.size) { nStream = 0; return; }
    U.uRes.value.set(S.hdr.width, S.hdr.height); U.uTime.value = lastT;
    placed = place(S);
    fill(back, placed.filter((o) => o.q.z > D), S);
    fill(front, placed.filter((o) => o.q.z <= D), S);
    if (back.n) r.render(back.m, st.ctx.cam);
    tags(placed);
  };
  C.front = () => {
    if (!all.size) return;
    if (front.n) r.render(front.m, st.ctx.cam);
    if (nStream) { SU.uB.value.slice(nStream).forEach((v) => v.set(0, 0, 0, 0)); SU.uC.value.slice(nStream).forEach((v) => v.set(0, 0, 0, 0)); r.render(streams, st.ctx.cam); }
  };
  /* Screen position of creature id, for a glance of the eye. */
  C.at = (id) => { const o = placed.find((x) => x.c.id === id); return o ? o.q : null; };
  C.cheers = () => { const out = []; for (const c of all.values()) if (c.cheer) { c.cheer = false; out.push(c.id); } return out; };
  return C;
}
