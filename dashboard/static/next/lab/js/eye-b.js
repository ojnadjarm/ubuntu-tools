/* Variant B, "Obsidian": a black glass orb behind shutter plates, a nine-blade diaphragm for a pupil, a glyph nebula at depth, armillary rings. */
import { HEAD } from "./glsl.js";
import { shaderVariant } from "./variant.js";

export const FS = `${HEAD}
const float RS = 1.075, DZ = 0.66, NB = 9.0;

vec2 shutters(vec3 n){
  float a = atan(n.x, n.z), e = asin(clamp(n.y, -1.0, 1.0));
  float s = 1.0 - 0.16 * a * a;
  float eu = (0.14 + uLid.x) * s, el = -(0.12 + uLid.y) * s;
  float m = mix(el, eu, 0.5);
  eu = mix(eu, m + 0.001, uLid.z); el = mix(el, m - 0.001, uLid.z);
  return vec2(eu - e, e - el);
}

vec3 lampC(){ return mix(MINT, uFlash.rgb, uFlash.a); }

vec3 shell(vec3 p, vec3 rd, vec2 sh){
  vec3 n = normalize(p);
  bool top = sh.x < sh.y;
  float d = -min(sh.x, sh.y), a = atan(n.x, n.z), sg = top ? -1.0 : 1.0;
  vec3 up = normalize(vec3(-n.x * n.y, 1.0 - n.y * n.y, -n.z * n.y) + 1e-5);
  float bev = smoothstep(0.035, 0.0, d);
  float groove = smoothstep(0.005, 0.0, abs(d - 0.1)) + smoothstep(0.005, 0.0, abs(d - 0.36));
  vec3 N = normalize(n + up * sg * bev * 1.3 - up * sg * groove * 0.45);
  float brushed = 0.8 + 0.4 * h12(vec2(floor(d * 260.0), top ? 1.0 : 2.0));
  vec3 L = normalize(KEY);
  vec3 c = vec3(0.014, 0.012, 0.018) * max(dot(N, L) * 0.8 + 0.2, 0.0) * brushed;
  float F = 0.04 + 0.96 * pow(1.0 - max(dot(N, -rd), 0.0), 5.0);
  c += env(reflect(rd, N), 0.5) * F * 0.55 * brushed;
  c += VIO * pow(1.0 - max(dot(n, -rd), 0.0), 3.0) * 0.03;
  float lamp = smoothstep(0.009, 0.0, abs(d - 0.017));
  float run = smoothstep(0.85, 1.0, sin(a * 3.0 - uTime * 1.6 * sg)) * uAct;
  float tick = step(fract(a * 24.0 / PI2 * 6.0), 0.12) * smoothstep(0.004, 0.0, abs(d - 0.06));
  c += lampC() * (lamp * (0.35 + 0.5 * uAct + 0.9 * run + 3.0 * uFlash.a) + tick * 0.12);
  return c * mix(1.0, 0.3, smoothstep(0.25, 1.2, d));
}

vec3 nebula(vec3 p, vec3 t, mat3 B){
  vec3 g = B[2], c = vec3(0.0);
  float tg = dot(t, g);
  for (int k = 0; k < 4; k++) {
    float fk = float(k), z = DZ - 0.16 - 0.24 * fk;
    float s = (z - dot(p, g)) / tg;
    if (s <= 0.0) continue;
    vec3 y = p + t * s;
    vec2 q = vec2(dot(y, B[0]), dot(y, B[1]));
    float rr = length(q), w = 0.042 + 0.014 * fk;
    if (rr > sqrt(max(1.0 - z * z, 0.0))) continue;
    float ri = floor(rr / w), fr = fract(rr / w);
    float n = max(6.0, floor(PI2 * (ri + 0.5) * 1.05));
    float spin = uTime * (0.03 + 0.05 * h12(vec2(ri, fk))) * (mod(ri + fk, 2.0) * 2.0 - 1.0) * (0.4 + uAct);
    float av = atan(q.y, q.x + 1e-7) / PI2 + 0.5 + spin, a = fract(av);
    vec2 da = vec2(dFdx(av), dFdy(av)); da -= floor(da + 0.5);
    float ci = floor(a * n), fa = fract(a * n);
    float on = step(h12(vec2(ci, ri + fk * 17.0)), 0.22 + 0.3 * uAct);
    float gid = floor(h12(vec2(ci + ri * 7.0, fk + floor(uTime * 0.6 + h12(vec2(ci, ri)) * 5.0))) * 61.0);
    float bl = 1.0 + fk * 1.6;
    vec2 dr = vec2(dFdx(rr), dFdy(rr)) / w;
    vec2 gg = glyph(gid, vec2(fa, fr), vec2(da.x * n, dr.x) * bl, vec2(da.y * n, dr.y) * bl);
    vec3 col = mix(MINT, VIO, clamp(fk / 2.5, 0.0, 1.0));
    c += col * (gg.x + gg.y * 0.4) * on * exp(-fk * 0.55) * 0.55;
  }
  float core = length(cross(t, -p));
  c += mix(MINT, vec3(0.85, 1.0, 0.92), 0.6) * (exp(-core * core / 0.0012) * 2.5 + exp(-core / 0.09) * 0.12) * (0.5 + 0.5 * uAct + 2.0 * uFlash.a);
  return c;
}

vec3 orb(vec3 rd, vec3 p, float occ){
  vec3 n = normalize(p), g = uGaze;
  mat3 B = basis(g);
  float F = 0.04 + 0.96 * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
  vec3 refl = env(reflect(rd, n), 1.0);
  vec3 t = refract(rd, n, 1.0 / 1.5);
  float RD = sqrt(1.0 - DZ * DZ), sd = (DZ - dot(p, g)) / dot(t, g);
  vec3 x = p + t * sd;
  vec2 ip = vec2(dot(x, B[0]), dot(x, B[1])) / RD;
  float rr = length(ip), ph = atan(ip.y, ip.x + 1e-7);
  float seg = PI2 / NB, rot = uPupil * 2.4;
  float k = mod(ph - rot, seg) - seg * 0.5;
  float ap = uPupil * 0.95, edgeR = mix(ap / cos(k), ap, 0.3);
  float aa = fwidth(rr) + 1e-4;
  float body = 0.0;
  vec3 inside = vec3(0.003, 0.0015, 0.006) + nebula(p, t, B) * 0.12;
  if (sd > 0.0 && rr < 1.0) {
    float blade = smoothstep(edgeR - aa, edgeR + aa, rr);
    float sp = ph - rot - (rr - ap) * 2.4;
    float bid = floor(sp / seg), fs = fract(sp / seg);
    vec3 Nb = normalize(g + (B[0] * cos(bid * 2.4) + B[1] * sin(bid * 2.4)) * 0.08);
    float Fb = 0.05 + 0.95 * pow(1.0 - abs(dot(t, Nb)), 5.0);
    vec3 dia = vec3(0.008, 0.007, 0.011) * (0.6 + 0.8 * h12(vec2(bid, 3.0)));
    dia += env(reflect(t, Nb), 0.45) * (0.1 + Fb) * 0.25 * vec3(0.8, 0.85, 1.0) * (0.75 + 0.5 * h12(vec2(floor(rr * 110.0), 1.0)));
    dia *= 1.0 - 0.85 * smoothstep(0.035, 0.0, fs) - 0.4 * smoothstep(0.93, 1.0, fs);
    dia += vec3(0.02, 0.022, 0.03) * smoothstep(0.035, 0.012, fs) * step(0.012, fs);
    float lip = smoothstep(0.035, 0.0, rr - edgeR) * step(edgeR, rr);
    dia += lampC() * lip * (0.25 + 0.55 * uAct + 3.0 * uFlash.a);
    float S = 150.0, a = (ph / PI2 + 0.5) - uTime * 0.002, sid = floor(a * S);
    float v = (rr - 0.86) / 0.06;
    float on = step(0.45, h12(vec2(floor(sid / 6.0), 4.0))) * step(0.12, h12(vec2(sid, 8.0)));
    vec2 gi = glyph(floor(h12(vec2(sid, 1.0)) * 61.0), vec2(fract(a * S), clamp(v, 0.0, 1.0)), vec2(0.0), vec2(0.0));
    float barrel = smoothstep(0.8, 0.805, rr);
    vec3 ring = vec3(0.006, 0.005, 0.008) + env(reflect(t, g), 0.6) * 0.06;
    ring += MINT * (gi.x * on * step(0.0, v) * step(v, 1.0) * 0.16 + smoothstep(0.004, 0.0, abs(rr - 0.955)) * 0.12 + step(fract(a * 180.0), 0.14) * smoothstep(0.012, 0.0, abs(rr - 0.975)) * 0.1);
    ring += (0.3 + 0.7 * uAct) * lampC() * smoothstep(0.006, 0.0, abs(rr - 0.807)) * 0.4;
    dia = mix(dia, ring, barrel);
    inside = mix(nebula(p, t, B), dia, blade);
    body = 1.0;
  }
  vec3 c = inside * (1.0 - F) * occ + refl * F;
  c += VIO * pow(1.0 - max(dot(n, -rd), 0.0), 2.5) * 0.05 * (1.0 - body * 0.5);
  return c;
}

vec3 ring(vec3 ro, vec3 rd, vec3 hn, float R, float spd, float seed, out float tR){
  float den = dot(rd, hn);
  tR = -dot(ro, hn) / den;
  if (tR <= 0.0) return vec3(0.0);
  vec3 x = ro + rd * tR, ax = normalize(cross(vec3(0.0, 0.0, 1.0), hn)), ay = cross(hn, ax);
  vec2 q = vec2(dot(x, ax), dot(x, ay));
  float rr = length(q), a = atan(q.y, q.x) / PI2 + 0.5, px = fwidth(rr) + 1e-4;
  float lines = smoothstep(px * 1.2, 0.0, abs(rr - R)) + smoothstep(px * 1.2, 0.0, abs(rr - R - 0.1)) * 0.6;
  float th = a + uTime * spd * (0.4 + uAct), S = floor(R * 95.0), sc = th * S, sid = floor(sc);
  float grp = floor(sid / 5.0);
  float on = step(0.62, h12(vec2(grp, seed))) * step(0.15, h12(vec2(sid, seed + 3.0)));
  float v = (rr - R - 0.03) / 0.045;
  vec2 g = glyph(floor(h12(vec2(sid, floor(uTime * 0.2 + h12(vec2(grp, seed)) * 7.0))) * 61.0), vec2(fract(sc), clamp(v, 0.0, 1.0)), vec2(0.0), vec2(0.0));
  float band = step(0.0, v) * step(v, 1.0) * on;
  float tick = step(fract(th * S * 0.5), 0.1) * smoothstep(px, 0.0, abs(rr - R + 0.02) - 0.012);
  float depth = mix(0.3, 1.0, smoothstep(-1.4, 1.2, x.z));
  vec3 c = mix(MINT, lampC(), uFlash.a) * (band * (g.x * 0.85 + g.y * 0.2) + lines * 0.3 + tick * 0.2);
  return c * (0.45 + 0.35 * uAct + 1.5 * uFlash.a) * depth * smoothstep(0.0, 0.2, abs(den));
}

void main(){
  vec2 uv; vec3 ro, rd;
  camera(uv, ro, rd, 1.3);
  vec2 hs = sph(ro, rd, vec3(0.0), RS);
  vec3 col = vec3(0.0);
  float tS = 1e9, occl = 0.0;
  if (hs.x > 0.0) {
    tS = hs.x; occl = 1.0;
    vec3 pS = ro + rd * hs.x;
    vec2 sh = shutters(normalize(pS));
    float open = min(sh.x, sh.y), aa = fwidth(open) + 1e-4, cov = smoothstep(-aa, aa, open);
    vec3 cs = cov < 1.0 ? shell(pS, rd, sh) : vec3(0.0), co = vec3(0.0015, 0.001, 0.002);
    if (cov > 0.0) {
      vec2 ho = sph(ro, rd, vec3(0.0), 1.0);
      if (ho.x > 0.0) {
        vec3 pO = ro + rd * ho.x;
        vec2 so = shutters(normalize(pO));
        float o2 = min(so.x, so.y), occ = smoothstep(-0.01, 0.12, o2);
        co = orb(rd, pO, occ);
        vec3 lip = vec3(0.002, 0.0015, 0.003) + lampC() * exp(min(o2, 0.0) / 0.008) * (0.2 + 0.4 * uAct + 2.0 * uFlash.a);
        co = mix(lip, co, smoothstep(-0.004, 0.004, o2));
      }
    }
    col = mix(cs, co, cov);
  }
  float t1, t2;
  vec3 r1 = ring(ro, rd, normalize(vec3(0.0, 0.96, 0.28)), 1.42, 0.004, 5.0, t1);
  vec3 r2 = ring(ro, rd, normalize(vec3(-0.42, 0.86, -0.3)), 1.62, -0.003, 11.0, t2) * 0.55;
  col += r1 * (t1 < tS ? 1.0 : 1.0 - occl) + r2 * (t2 < tS ? 1.0 : 1.0 - occl) + bokeh(uv) * (1.0 - occl);
  float r = length(uv);
  col += (MINT * 0.4 + VIO * 0.6) * 0.012 * (0.5 + uAct) * exp(-1.6 * max(r - 0.9, 0.0));
  oCol = vec4(clean(col), 1.0);
}`;

/* Variant B for the lab engine. */
export const variantB = () => shaderVariant("Obsidian", FS);
