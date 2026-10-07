/* The Swarm: the eye as a cloud of katakana — iris rings turning with activity, sclera dust, lids as glyph sheets, the data rings and the halo as glyph orbits; it assembles from scatter (uForm) and blurs by point size. */
import { PAL, EYECAM } from "../glsl.js";

const LIDS = `
vec2 lidsAt(vec3 n){
  float a = atan(n.x, n.z), e = asin(clamp(n.y, -1.0, 1.0));
  float s = max(1.0 - a * a, 0.0);
  float eu = uLid.x * pow(s, 0.62) - 0.03 * (1.0 - s), el = -uLid.y * pow(s, 0.95);
  float m = mix(el, eu, 0.22);
  eu = mix(eu, m, uLid.z); el = mix(el, m, uLid.z);
  return vec2(eu - e, e - el);
}`;

const vs = `precision highp float;
in vec3 position;
in vec4 meta;
uniform vec3 uEye; uniform vec2 uCam; uniform vec3 uGaze; uniform vec4 uLid; uniform vec4 uFlash; uniform vec2 uPx;
uniform float uPupil, uTime, uAct, uForm, uSleep, uHalo, uSpin, uRingK; uniform vec3 uRingN; uniform vec4 uRing[8];
out vec3 vCol; out vec2 vCell; out float vSharp;
${PAL}
const float D = 7.0, RL = 1.085, IR = 0.52, DI = 0.8, PI2 = 6.2831853;
const vec3 HN = vec3(0.0, 0.9536, 0.3011);
float h11(float p){ p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
${LIDS}
mat3 basis(vec3 g){ vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), g)); return mat3(r, cross(g, r), g); }
void main(){
  float kind = meta.x, seed = meta.y, size = meta.w, a = 1.0, dof = -1.0, flick = step(0.6, h11(seed * 9.0));
  vec3 p, col;
  if (kind > 7.5) {
    float layer = position.x, th = (position.y + uTime * 0.004) * PI2, sid = floor(position.y * 150.0);
    vec3 ax = vec3(1.0, 0.0, 0.0), ay = cross(HN, ax);
    p = (ax * cos(th) + ay * sin(th)) * (layer < 0.5 ? 1.5 : layer < 1.5 ? 1.585 + position.z : 1.53);
    float on = layer > 0.5 && layer < 1.5 ? step(0.5, h11(floor(sid / 7.0) * 3.7 + 1.0)) * step(0.15, h11(sid + 0.3)) : 1.0;
    col = MINT * (layer < 0.5 ? 0.14 : layer < 1.5 ? 0.85 : 0.45) * on * (0.45 + 0.4 * uAct) * uHalo;
    size *= step(0.01, uHalo * on);
    dof = 0.15;
  } else if (kind > 6.5) {
    int i = int(position.x + 0.5);
    vec4 R = uRing[i];
    float rk = R.z, v = clamp(R.y, 0.0, 1.0), at = position.y, orbit = step(1.5, rk) * step(rk, 2.5);
    float ta = at + orbit * uSpin / PI2;
    vec3 n = uRingN, ax = normalize(vec3(n.y + 1e-5, -n.x, 0.0)), ay = cross(n, ax);
    float th = PI2 * 0.25 - ta * PI2;
    p = (ax * cos(th) + ay * sin(th)) * (R.x + position.z);
    vec3 hue = rk > 0.5 && rk < 1.5 ? GOLD : rk > 2.5 ? mix(MINT, ICE, 0.35) : MINT;
    float lit = step(at, v) * step(0.004, v), trail = lit * mix(0.25, 1.0, pow(clamp(at / max(v, 1e-3), 0.0, 1.0), 2.2));
    float head = lit * smoothstep(0.02, 0.0, v - at);
    float fl = 1.0 + 2.5 * R.w;
    col = orbit > 0.5 ? MINT * (0.1 + 0.16 * step(0.55, fract(at * 36.0))) * (0.6 + 0.6 * uAct)
        : hue * (0.03 + 1.1 * trail) * fl + mix(hue, vec3(1.0), 0.55) * head * 2.2;
    size *= (orbit > 0.5 ? 0.85 : mix(0.6, 1.2, lit) + 1.1 * head) * (1.0 + 0.15 * R.w) * step(float(i) + 0.5, uRingK);
    size *= orbit > 0.5 || lit > 0.5 ? 1.0 : step(0.6, h11(seed * 2.0));
    flick = max(flick, lit);
    dof = 0.2;
  } else if (kind < 0.5 || kind > 4.5) {
    float rn = position.x, dir = mod(floor(rn * 9.0), 2.0) * 2.0 - 1.0;
    float th = position.y * PI2 + uTime * position.z * dir * (0.25 + 0.75 * uAct);
    float r = mix(uPupil * IR + 0.02, IR - 0.01, rn);
    r *= 1.0 + 0.05 * uFlash.a * sin(rn * 14.0 - uFlash.a * 6.0);
    p = basis(uGaze) * vec3(cos(th) * r, sin(th) * r, DI + 0.07 * (1.0 - rn));
    float ring = kind > 4.5 ? 1.0 : 0.0;
    col = mix(MINT * 0.85, VIO * 0.6, smoothstep(0.35, 0.8, rn)) * mix(1.0, 0.6, rn);
    col *= 0.3 + 1.4 * pow(h11(seed * 7.0 + floor(uTime * 0.8 + seed)), 3.0);
    col = mix(col, mix(MINT, uFlash.rgb, uFlash.a) * (1.4 + 5.0 * uFlash.a), ring);
    col *= (0.6 + 0.4 * uAct) * (1.0 - 0.6 * uSleep);
  } else if (kind < 1.5) {
    p = basis(uGaze) * position;
    col = vec3(0.32, 0.5, 0.44) * 0.3 * (0.4 + 0.6 * smoothstep(0.1, 0.8, position.z)) * (1.0 - 0.5 * uSleep);
  } else {
    float az = position.x, d = position.y;
    float s = max(1.0 - az * az, 0.0);
    float eu = uLid.x * pow(s, 0.62) - 0.03 * (1.0 - s), el = -uLid.y * pow(s, 0.95);
    float m = mix(el, eu, 0.22);
    eu = mix(eu, m, uLid.z); el = mix(el, m, uLid.z);
    float e = kind < 2.5 ? eu + d : el - d;
    p = (RL + 0.02 * d) * vec3(cos(e) * sin(az), sin(e), cos(e) * cos(az));
    float edge = exp(-d / 0.012);
    col = mix(VIO * 0.16, mix(MINT, uFlash.rgb, uFlash.a) * (0.8 + 0.7 * uAct + 3.0 * uFlash.a), edge) * exp(-d / 0.2) * smoothstep(1.0, 0.6, abs(az));
  }
  if (kind < 1.5 || (kind > 4.5 && kind < 5.5)) {
    vec2 ld = lidsAt(normalize(vec3(p.xy, sqrt(max(RL * RL - dot(p.xy, p.xy), 0.0)))));
    a *= smoothstep(-0.005, 0.03, min(ld.x, ld.y)) * step(0.0, p.z);
  }
  if (kind > 6.5) a *= mix(0.4, 1.0, smoothstep(-1.5, 1.5, p.z)) * mix(1.0, 0.3, step(p.z, 0.0) * step(length(p.xy), 1.05));
  float f = smoothstep(0.0, 1.0, clamp(uForm * 1.6 - h11(seed * 3.0) * 0.6, 0.0, 1.0));
  float sa = h11(seed) * PI2 + (1.0 - f) * 2.0, sr = 1.4 + 2.2 * h11(seed + 4.0);
  vec3 scatter = vec3(cos(sa) * sr * 1.3, (h11(seed + 1.0) - 0.5) * 2.2, sin(sa) * sr * 0.5 - 0.6);
  p = mix(scatter, p, f);
  float cy = cos(uCam.x), sy = sin(uCam.x), cp = cos(uCam.y), sp = sin(uCam.y);
  p = p * (mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy) * mat3(1.0, 0.0, 0.0, 0.0, cp, -sp, 0.0, sp, cp));
  float w = D - p.z;
  vec2 uv = p.xy * D / (w * 1.0104);
  gl_Position = vec4((uEye.xy + uv * uEye.z) * uPx * 2.0 - 1.0, 0.0, 1.0);
  float blur = (dof >= 0.0 ? dof * abs(p.z) : abs(p.z - 0.85) * 2.2) + (1.0 - f) * 0.6;
  float px = size * uEye.z * 0.03 * D / w;
  gl_PointSize = min(px * (1.0 + blur), 96.0);
  vCol = mix(mix(MINT, VIO, step(0.55, h11(seed * 11.0))) * 0.35, col * a, f) / (1.0 + blur * blur * 2.5);
  float gid = floor(fract(meta.z + floor(uTime * (0.3 + 2.0 * h11(seed * 5.0)) + seed * 13.0) * 0.618 * flick) * 61.0);
  vCell = vec2(mod(gid, 8.0), floor(gid / 8.0));
  vSharp = clamp(1.0 - blur * 0.8, 0.0, 1.0);
}`;

const fs = `precision highp float;
uniform sampler2D uAtlas;
in vec3 vCol; in vec2 vCell; in float vSharp;
out vec4 oCol;
void main(){
  vec2 uv = (vCell + 0.1 + gl_PointCoord * 0.8) / 8.0;
  vec2 g = texture(uAtlas, uv, (1.0 - vSharp) * 2.5).rg;
  float v = mix(g.y * 0.6, g.x + g.y * 0.25, vSharp);
  if (v < 0.004) discard;
  oCol = vec4(vCol * v, 1.0);
}`;

/* The dark almond behind the glyphs: the lid opening on the eyeball darkens what lies behind the eye. */
const shade = `precision highp float;
uniform vec3 uEye; uniform vec2 uCam; uniform vec4 uLid; uniform float uForm;
out vec4 oCol;
const float RL = 1.085;
${EYECAM}
${LIDS}
void main(){
  vec2 uv; vec3 ro, rd;
  camera(uv, ro, rd);
  float b = dot(ro, rd), h = b * b - dot(ro, ro) + RL * RL;
  vec2 ld = lidsAt(normalize(ro + rd * (-b - sqrt(max(h, 0.0)))));
  float open = min(ld.x, ld.y), aa = fwidth(open) + 1e-4;
  oCol = vec4(0.0, 0.0, 0.0, step(0.0, h) * smoothstep(-aa, 0.06, open) * 0.82 * uForm);
}`;

/* Iris rings, collarette, sclera dust, both lid sheets, n glyphs on each of the 8 data rings and the halo; k scales the eye's counts. */
function swarm(k, n) {
  const pos = [], meta = [], R = (a, b) => a + (b - a) * Math.random();
  const add = (x, y, z, kind, size) => { pos.push(x, y, z); meta.push(kind, Math.random() * 1000, Math.random(), size); };
  const rings = Math.round(15 * k);
  for (let i = 0; i < rings; i++) {
    const rn = (i + 0.5) / rings, count = Math.round((34 + 120 * rn) * k), spd = R(0.02, 0.06);
    for (let j = 0; j < count; j++) add(rn + R(-0.01, 0.01), (j + R(0, 0.3)) / count, spd, 0, R(0.8, 1.1));
  }
  for (let j = 0, c = Math.round(90 * k); j < c; j++) add(0.3 + R(-0.012, 0.012), j / c, 0.03, 5, 1.05);
  for (let j = 0; j < Math.round(2600 * k); j++) {
    const z = R(0.2, 0.88), a = R(0, Math.PI * 2), s = Math.sqrt(1 - z * z);
    add(Math.cos(a) * s, Math.sin(a) * s, z, 1, R(0.35, 0.7));
  }
  for (const kind of [2, 3]) for (let row = 0; row < 7; row++) {
    const d = row === 0 ? 0.0 : 0.012 * Math.pow(row, 1.5), count = Math.round((row === 0 ? 120 : 90) * k);
    for (let j = 0; j < count; j++) add(-1 + 2 * (j + R(0.2, 0.8)) / count, d + R(0, 0.006), 0, kind, row === 0 ? 0.8 : R(0.55, 0.85));
  }
  for (let i = 0; i < 8; i++) for (let j = 0; j < n; j++) add(i, (j + 0.5) / n, R(-0.004, 0.004), 7, R(0.9, 1.1));
  for (let j = 0; j < 2 * n; j++) add(0, j / (2 * n), 0, 8, R(0.35, 0.5));
  for (let j = 0; j < 150; j++) for (const r of [0, 0.03]) add(1, (j + 0.5) / 150, r, 8, 0.9);
  for (let j = 0; j < 12; j++) add(2, j / 12, 0, 8, 1.6);
  return { pos: new Float32Array(pos), meta: new Float32Array(meta) };
}

/* Tier q (0 low … 2 high) → eye density and glyphs per data ring. */
const DENSITY = [[0.5, 128], [0.75, 192], [1, 256]];

export default {
  name: "Swarm", vs, fs,
  /* The swarm over the shared eye uniforms U (atlas included); draw(S, box) paints the shade (scissored to box) and the glyphs, probe(S) the same for the tier probe. */
  create({ T, r, cam, quad }, U) {
    const mat = new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: vs, fragmentShader: fs, uniforms: U, depthTest: false, depthWrite: false, transparent: true, blending: T.AdditiveBlending });
    const back = quad(shade, U, T.CustomBlending, { blendSrc: T.OneFactor, blendDst: T.OneMinusSrcAlphaFactor });
    let pts = null, q = -1;
    const build = (tier) => {
      q = tier;
      if (pts) pts.geometry.dispose();
      const s = swarm(...(DENSITY[tier] || DENSITY[2])), g = new T.BufferGeometry();
      g.setAttribute("position", new T.BufferAttribute(s.pos, 3));
      g.setAttribute("meta", new T.BufferAttribute(s.meta, 4));
      pts = new T.Points(g, mat);
      pts.frustumCulled = false;
    };
    const draw = (S, box) => {
      if (S.q !== q) build(S.q);
      const hdr = S.hdr;
      U.uPx.value.set(1 / hdr.width, 1 / hdr.height);
      if (box) { hdr.scissor.set(...box); hdr.scissorTest = true; r.setRenderTarget(hdr); }
      r.render(back, cam);
      hdr.scissorTest = false;
      r.setRenderTarget(hdr);
      r.render(pts, cam);
    };
    return { draw, probe: (S) => draw(S, null), count: () => (pts ? pts.geometry.attributes.position.count : 0) };
  },
};
