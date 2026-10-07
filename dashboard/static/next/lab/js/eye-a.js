/* Variant A, "Oracle": an analytic ray-traced eyeball in the dark — lids, wet cornea refracting a procedural iris, katakana rain falling into the pupil. */
import { HEAD } from "./glsl.js";
import { shaderVariant } from "./variant.js";

export const FS = `${HEAD}
const float RL = 1.085, CC = 0.355, RC = 0.715, DL = 0.866, DI = 0.80, IR = 0.52;

vec2 lidsAt(vec3 n){
  float a = atan(n.x, n.z), e = asin(clamp(n.y, -1.0, 1.0));
  float s = max(1.0 - a * a, 0.0);
  float eu = uLid.x * pow(s, 0.62) - 0.03 * (1.0 - s), el = -uLid.y * pow(s, 0.95);
  float m = mix(el, eu, 0.22);
  eu = mix(eu, m, uLid.z); el = mix(el, m, uLid.z);
  return vec2(eu - e, e - el);
}

vec3 sclera(vec3 p, vec3 rd, mat3 B, float occ){
  vec3 n = normalize(p), q = n * B;
  float lim = q.z;
  float v1 = vn3(q * 7.0 + 3.1), v2 = vn3(q * 17.0 + 7.3);
  float r1 = pow(1.0 - abs(v1 * 2.0 - 1.0), 12.0), r2 = pow(1.0 - abs(v2 * 2.0 - 1.0), 16.0);
  float vm = smoothstep(0.9, 0.5, lim) * (0.35 + 0.65 * vn3(q * 2.5 + 11.0));
  float veins = clamp((r1 * 0.9 + r2 * 0.55) * vm, 0.0, 1.0);
  vec3 alb = mix(vec3(0.062, 0.07, 0.068), vec3(0.03, 0.003, 0.018), veins);
  alb *= mix(0.45, 1.0, smoothstep(DL + 0.005, DL - 0.09, lim));
  vec3 L = normalize(KEY);
  float wrap = max((dot(n, L) + 0.25) / 1.25, 0.0);
  vec3 c = alb * (wrap * vec3(0.8, 0.95, 0.88) * 0.9 + 0.012);
  float ig = exp(-max(DL - lim, 0.0) * 10.0);
  c += mix(VIO, MINT, 0.55) * ig * 0.035 * (0.6 + uAct) + VIO * veins * 0.012;
  float flow = fract(lim * 10.0 - uTime * 0.35 + v1 * 3.0);
  c += MINT * veins * smoothstep(0.965, 1.0, flow) * 0.5 * uAct;
  float F = 0.02 + 0.98 * pow(1.0 - max(dot(-rd, n), 0.0), 5.0);
  return c * occ + env(reflect(rd, n), 0.75) * F * mix(0.35, 1.0, occ);
}

vec3 iris(vec2 ip, float rN, mat3 B, float occ){
  float th = atan(ip.y, ip.x + 1e-7) / PI2 + 0.5;
  vec2 dth = vec2(dFdx(th), dFdy(th)); dth -= floor(dth + 0.5);
  float pr = uPupil * (1.0 + 0.02 * (pn(vec2(th * 18.0, 0.5), 18.0) - 0.5));
  float z = (rN - pr) / (1.0 - pr), zz = clamp(z, 0.0, 1.0);
  float aa = fwidth(z) + 1e-4;
  float w = 0.008 * (pn(vec2(th * 24.0, zz * 3.5), 24.0) - 0.5) + 0.0015 * (pn(vec2(th * 90.0, zz * 6.0), 90.0) - 0.5);
  float f1 = pn(vec2((th + w) * 150.0, zz * 2.2), 150.0);
  float f2 = pn(vec2((th + w * 1.7) * 320.0, zz * 7.0 + 3.0), 320.0);
  float f3 = pn(vec2(th * 40.0, zz * 1.5 + 7.0), 40.0);
  float lod = smoothstep(0.25, 0.7, length(dth) * 320.0);
  float r1 = pow(1.0 - abs(2.0 * f1 - 1.0), 3.0), r2 = mix(pow(1.0 - abs(2.0 * f2 - 1.0), 4.0), 0.2, lod);
  float fib = clamp((r1 * 0.8 + r2 * 0.5) * (0.5 + 0.7 * f3), 0.0, 1.0);
  float cr = 0.3 + 0.07 * pn(vec2(th * 13.0, 1.7), 13.0) + 0.03 * pn(vec2(th * 37.0, 4.1), 37.0);
  float coll = smoothstep(0.028, 0.0, abs(zz - cr - 0.012 * (pn(vec2(th * 64.0, 2.0), 64.0) - 0.5))) * (0.4 + 0.6 * f2);
  float inner = smoothstep(cr + 0.03, cr - 0.03, zz);
  float crypt = 0.0;
  if (uQ > 0.5) {
    vec2 cq = vec2(th * 26.0, zz * 5.0), ci = floor(cq), cf = fract(cq);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
      vec2 o = vec2(i, j), id = vec2(mod(ci.x + o.x, 26.0), ci.y + o.y);
      vec2 pt = o + vec2(h12(id), h12(id + 17.0)) * 0.8 + 0.1;
      float sz = 0.18 + 0.25 * h12(id + 5.0);
      float near = smoothstep(0.55, 0.25, abs(ci.y + o.y + 0.5 - cr * 5.0 - 0.6));
      crypt = max(crypt, smoothstep(sz, sz * 0.3, length((cf - pt) * vec2(1.6, 1.0))) * near * step(0.45, h12(id + 3.0)));
    }
  }
  float fur = 0.0;
  for (int k = 0; k < 3; k++) {
    float rz = 0.6 + float(k) * 0.13 + 0.015 * (pn(vec2(th * 7.0, float(k) * 3.0), 7.0) - 0.5);
    fur += smoothstep(0.014, 0.0, abs(zz - rz)) * pn(vec2(th * 5.0, float(k) + 0.5), 5.0);
  }
  vec3 outer = mix(vec3(0.004, 0.002, 0.009), vec3(0.1, 0.055, 0.2), fib);
  vec3 innerC = mix(vec3(0.002, 0.007, 0.005), vec3(0.035, 0.11, 0.075), fib);
  vec3 alb = mix(outer, innerC, inner);
  alb *= (1.0 - 0.8 * crypt) * (1.0 - 0.45 * clamp(fur, 0.0, 1.0));
  alb *= mix(1.0, 0.1, smoothstep(0.78, 1.0, zz));
  vec3 Lk = normalize(KEY);
  vec2 lp = vec2(dot(Lk, B[0]), dot(Lk, B[1]));
  float caus = pow(max(dot(ip / max(rN, 1e-3), -normalize(lp + 1e-4)), 0.0), 3.0) * smoothstep(0.25, 0.85, zz);
  vec3 c = alb * (0.5 + 1.2 * caus) * occ;
  float act = 0.35 + 0.65 * uAct;
  vec3 em = (VIO * 0.035 * fib * (1.0 - inner) + MINT * 0.06 * inner * fib) * act * (1.0 - 0.8 * crypt);
  vec3 ring = mix(MINT, uFlash.rgb, uFlash.a);
  em += ring * coll * (0.06 + 0.14 * uAct + 2.5 * uFlash.a);
  float S = 64.0, sc = th * S, sid = floor(sc), sx = fract(sc), LEN = 12.0;
  float u = (1.0 - zz) * LEN;
  float cyc = uTime * (0.5 + 0.7 * h12(vec2(sid, 1.3))) + h12(vec2(sid, 9.1)) * 40.0;
  float ep = floor(cyc / (LEN + 5.0)), head = mod(cyc, LEN + 5.0);
  float on = step(h12(vec2(sid, ep + 0.5)), 0.12 + 0.3 * uAct);
  float slot = floor(u), d = head - slot;
  float tail = on * step(0.0, d) * step(d, 4.0) * pow(1.0 - d / 4.5, 2.0);
  float gid = floor(h12(vec2(sid * 7.0 + slot, floor(uTime * (1.0 + 3.0 * h12(vec2(slot, sid)))))) * 61.0);
  vec2 du = vec2(dFdx(u), dFdy(u));
  vec2 g = glyph(gid, vec2(sx, fract(u)), vec2(dth.x * S, du.x), vec2(dth.y * S, du.y));
  float hb = on * smoothstep(1.3, 0.0, d);
  em += mix(MINT, vec3(0.8, 1.0, 0.9), hb) * (g.x * (0.35 + 1.8 * hb) + g.y * 0.15) * tail * (0.3 + 0.9 * fib) * step(0.0, z) * (1.0 - smoothstep(0.9, 1.0, zz));
  c += em;
  float ruff = smoothstep(0.06, 0.0, z) * step(0.0, z);
  c *= 1.0 - 0.7 * ruff;
  vec3 pupil = vec3(0.0, 0.003, 0.002) + MINT * 0.012 * act * smoothstep(0.0, -0.5, z);
  return mix(pupil, c, smoothstep(-aa, aa, z));
}

vec3 eye(vec3 ro, vec3 rd, out float tHit){
  mat3 B = basis(uGaze);
  vec3 g = uGaze;
  vec2 tc = sph(ro, rd, g * CC, RC), te = sph(ro, rd, vec3(0.0), 1.0);
  vec3 pc = ro + rd * tc.x;
  bool corn = tc.x > 0.0 && dot(pc, g) > DL;
  if (!corn && te.x < 0.0) { tHit = 1e9; return vec3(0.0); }
  vec3 p = corn ? pc : ro + rd * te.x;
  tHit = corn ? tc.x : te.x;
  vec2 ld = lidsAt(normalize(p));
  float occ = smoothstep(-0.03, 0.3, ld.x) * smoothstep(-0.01, 0.06, ld.y);
  vec3 c;
  if (corn) {
    vec3 n = normalize(p - g * CC);
    float F = 0.025 + 0.975 * pow(1.0 - max(dot(-rd, n), 0.0), 5.0);
    vec3 refl = env(reflect(rd, n), 1.0);
    vec3 t = refract(rd, n, 1.0 / 1.336);
    float s = (DI - dot(p, g)) / dot(t, g);
    vec3 x = p + t * s;
    vec2 ip = vec2(dot(x, B[0]), dot(x, B[1])) / IR;
    float rN = length(ip);
    for (int i = 0; i < 2; i++) {
      float h = 0.05 * pow(clamp(1.0 - rN, 0.0, 1.0), 1.6);
      s = (DI + h - dot(p, g)) / dot(t, g);
      x = p + t * s; ip = vec2(dot(x, B[0]), dot(x, B[1])) / IR; rN = length(ip);
    }
    vec3 ir = iris(ip, rN, B, occ);
    float edge = smoothstep(DL + 0.002, DL + 0.05, dot(p, g));
    ir = mix(sclera(p, rd, B, occ) * 0.5, ir, edge);
    c = ir * (1.0 - F) + refl * F * mix(0.5, 1.0, occ);
  } else {
    c = sclera(p, rd, B, occ);
  }
  float lash = smoothstep(0.07, 0.0, ld.x) * (0.55 + 0.45 * pn(vec2(atan(p.x, p.z) * 60.0, 0.5), 377.0));
  c *= (1.0 - 0.8 * lash) * mix(0.6, 1.0, smoothstep(0.0, 0.05, ld.y));
  vec3 n0 = normalize(p), up = normalize(vec3(-n0.x * n0.y, 1.0 - n0.y * n0.y, -n0.z * n0.y) + 1e-5);
  float lower = step(ld.y, ld.x);
  vec3 Nr = normalize(n0 * 0.55 + up * mix(-0.85, 0.85, lower));
  float Fr = 0.03 + 0.97 * pow(1.0 - max(dot(Nr, -rd), 0.0), 5.0);
  vec3 rimC = mix(vec3(0.0015, 0.0008, 0.0015), vec3(0.004, 0.002, 0.005) + env(reflect(rd, Nr), 0.9) * Fr * 0.5, lower);
  float m = smoothstep(0.012, 0.0, abs(ld.y - 0.004)) * 0.35;
  c += env(reflect(rd, n0), 0.8) * m * 0.2;
  c = mix(rimC, c, smoothstep(-0.003, 0.003, min(ld.x, ld.y)));
  return c;
}

vec3 skin(vec3 p, vec3 n, vec3 rd, vec2 ld){
  float d = -min(ld.x, ld.y);
  float dir = ld.x < ld.y ? -1.0 : 1.0;
  vec3 up = normalize(vec3(-n.x * n.y, 1.0 - n.y * n.y, -n.z * n.y) + 1e-5);
  float roll = exp(-d / 0.04);
  vec3 N = normalize(n * (1.0 - 0.8 * roll) + up * dir * roll * 1.1);
  float crease = dir < 0.0 ? smoothstep(0.05, 0.0, abs(d - 0.22 - 0.03 * sin(atan(n.x, n.z) * 2.0))) : smoothstep(0.06, 0.0, abs(d - 0.16)) * 0.5;
  N = normalize(N - up * dir * crease * 0.6);
  float pores = vn3(p * 70.0) * 0.6 + vn3(p * 160.0) * 0.4;
  vec3 alb = vec3(0.02, 0.014, 0.024) * (0.7 + 0.6 * pores);
  vec3 L = normalize(KEY);
  vec3 c = alb * max((dot(N, L) + 0.25) / 1.25, 0.0) * 1.3;
  float F = 0.028 + 0.972 * pow(1.0 - max(dot(N, -rd), 0.0), 5.0);
  c += env(reflect(rd, N), 0.0) * F * 0.1 * (0.3 + roll);
  c += env(reflect(rd, N), 0.85) * smoothstep(0.028, 0.0, d) * F * 0.45;
  c += (MINT * 0.5 + VIO * 0.4) * 0.03 * exp(-d / 0.025) * (0.5 + uAct);
  c += pow(1.0 - max(dot(N, -rd), 0.0), 4.0) * VIO * 0.01;
  return c * exp(-d / 0.14);
}

vec3 halo(vec3 ro, vec3 rd, out float tH){
  vec3 hn = normalize(vec3(0.0, 0.95, 0.3));
  float den = dot(rd, hn);
  tH = -dot(ro, hn) / den;
  if (tH <= 0.0) return vec3(0.0);
  vec3 x = ro + rd * tH, ax = vec3(1.0, 0.0, 0.0), ay = cross(hn, ax);
  vec2 q = vec2(dot(x, ax), dot(x, ay));
  float rr = length(q), a = atan(q.y, q.x) / PI2 + 0.5, px = fwidth(rr) + 1e-4;
  float line = smoothstep(px * 1.2, 0.0, abs(rr - 1.5));
  float tick = step(fract(a * 144.0), 0.1) * smoothstep(px, 0.0, abs(rr - 1.522) - 0.012);
  float major = step(fract(a * 12.0 + 0.004), 0.008) * smoothstep(px, 0.0, abs(rr - 1.53) - 0.03);
  float th = a + uTime * 0.004, S = 150.0, sc = th * S, sid = floor(sc);
  float grp = floor(sid / 7.0);
  float on = step(0.5, h12(vec2(grp, 5.0))) * step(0.15, h12(vec2(sid, 3.0)));
  float v = (rr - 1.56) / 0.055;
  float gid = floor(h12(vec2(sid, floor(uTime * 0.25 + h12(vec2(grp, 2.0)) * 9.0))) * 61.0);
  vec2 g = glyph(gid, vec2(fract(sc), clamp(v, 0.0, 1.0)), vec2(0.0), vec2(0.0));
  float band = step(0.0, v) * step(v, 1.0) * on;
  float depth = mix(0.35, 1.0, smoothstep(-1.2, 1.0, x.z));
  return MINT * (band * (g.x * 0.9 + g.y * 0.2) + line * 0.35 + tick * 0.25 + major * 0.5) * (0.4 + 0.4 * uAct) * depth * smoothstep(0.0, 0.25, abs(den));
}

void main(){
  vec2 uv; vec3 ro, rd;
  camera(uv, ro, rd, 1.0);
  vec2 hs = sph(ro, rd, vec3(0.0), RL);
  vec3 pS = ro + rd * (hs.x > 0.0 ? hs.x : -dot(ro, rd));
  vec3 n = normalize(pS);
  vec2 ld = lidsAt(n);
  float open = min(ld.x, ld.y), aa = fwidth(open) + 1e-4;
  float cov = smoothstep(-aa, aa, open);
  float sil = smoothstep(RL, 0.9, length(cross(rd, ro)));
  vec3 col = vec3(0.0);
  float tS = 1e9, occl = 0.0;
  if (hs.x > 0.0) {
    tS = hs.x;
    vec3 sk = cov < 1.0 ? skin(pS, n, rd, ld) * sil : vec3(0.0);
    float tE = 1e9;
    vec3 ey = cov > 0.0 ? eye(ro, rd, tE) : vec3(0.0);
    col = mix(sk, ey, cov);
    occl = cov + (1.0 - cov) * sil * smoothstep(0.45, 0.12, -open);
  }
  float tH;
  vec3 hl = halo(ro, rd, tH);
  col += hl * (tH < tS ? 1.0 : 1.0 - occl) + bokeh(uv) * (1.0 - occl);
  float r = length(uv);
  col += (MINT * 0.55 + VIO * 0.45) * 0.01 * (0.5 + uAct) * exp(-1.8 * max(r - 0.45, 0.0));
  oCol = vec4(clean(col), 1.0);
}`;

/* Variant A for the lab engine. */
export const variantA = () => shaderVariant("Oracle", FS);
