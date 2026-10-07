/* Variant C, "Swarm": the eye as a cloud of katakana — iris rings turning, a sclera of glyph dust, lids as glyph sheets, depth of field by size. */
import { HEAD, PAL } from "./glsl.js";
import { atlas } from "./atlas.js";
import { still } from "./engine.js";

const VS = `precision highp float;
in vec3 position;
in vec4 meta;
uniform vec3 uEye; uniform vec2 uCam; uniform vec3 uGaze; uniform vec4 uLid; uniform vec4 uFlash;
uniform float uPupil, uTime, uAct, uForm; uniform vec2 uPx;
out vec3 vCol; out vec2 vCell; out float vSharp;
${PAL}
const float D = 7.0, RL = 1.085, IR = 0.52, DI = 0.8, PI2 = 6.2831853;
float h11(float p){ p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
vec2 lidsAt(vec3 n){
  float a = atan(n.x, n.z), e = asin(clamp(n.y, -1.0, 1.0));
  float s = max(1.0 - a * a, 0.0);
  float eu = uLid.x * pow(s, 0.62) - 0.03 * (1.0 - s), el = -uLid.y * pow(s, 0.95);
  float m = mix(el, eu, 0.22);
  eu = mix(eu, m, uLid.z); el = mix(el, m, uLid.z);
  return vec2(eu - e, e - el);
}
mat3 basis(vec3 g){ vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), g)); return mat3(r, cross(g, r), g); }
void main(){
  float kind = meta.x, seed = meta.y, size = meta.w, a = 1.0;
  mat3 B = basis(uGaze);
  vec3 p, col;
  float ring = 0.0;
  if (kind > 5.5) {
    p = vec3(-0.25 + position.x * 0.075, 0.25 + position.y * 0.05, 1.1);
    a *= step(0.14, abs(position.y + 0.12)) * step(0.12, abs(position.x - 0.1));
    col = vec3(0.75, 1.0, 0.88) * (1.1 + 0.4 * uAct);
  } else if (kind < 0.5 || kind > 4.5) {
    float rn = position.x, dir = mod(floor(rn * 9.0), 2.0) * 2.0 - 1.0;
    float th = position.y * PI2 + uTime * position.z * dir * (0.25 + 0.75 * uAct);
    float r = mix(uPupil * IR + 0.02, IR - 0.01, rn);
    r *= 1.0 + 0.05 * uFlash.a * sin(rn * 14.0 - uFlash.a * 6.0);
    p = B * vec3(cos(th) * r, sin(th) * r, DI + 0.07 * (1.0 - rn));
    ring = kind > 4.5 ? 1.0 : 0.0;
    col = mix(MINT * 0.85, VIO * 0.6, smoothstep(0.35, 0.8, rn)) * mix(1.0, 0.6, rn);
    col *= 0.3 + 1.4 * pow(h11(seed * 7.0 + floor(uTime * 0.8 + seed)), 3.0);
    col = mix(col, mix(MINT, uFlash.rgb, uFlash.a) * (1.4 + 5.0 * uFlash.a), ring);
    col *= 0.6 + 0.4 * uAct;
  } else if (kind < 1.5) {
    p = B * position;
    col = vec3(0.32, 0.5, 0.44) * 0.3 * (0.4 + 0.6 * smoothstep(0.1, 0.8, position.z));
  } else if (kind < 3.5) {
    float az = position.x, d = position.y;
    float s = max(1.0 - az * az, 0.0);
    float eu = uLid.x * pow(s, 0.62) - 0.03 * (1.0 - s), el = -uLid.y * pow(s, 0.95);
    float m = mix(el, eu, 0.22);
    eu = mix(eu, m, uLid.z); el = mix(el, m, uLid.z);
    float e = kind < 2.5 ? eu + d : el - d;
    p = (RL + 0.02 * d) * vec3(cos(e) * sin(az), sin(e), cos(e) * cos(az));
    float edge = exp(-d / 0.012);
    col = mix(VIO * 0.16, mix(MINT, uFlash.rgb, uFlash.a) * (0.8 + 0.7 * uAct + 3.0 * uFlash.a), edge) * exp(-d / 0.2) * smoothstep(1.0, 0.6, abs(az));
  } else {
    p = position;
    col = mix(VIO, MINT, step(0.7, h11(seed))) * 0.05;
  }
  if (kind < 1.5 || kind > 4.5) {
    vec2 ld = lidsAt(normalize(vec3(p.xy, sqrt(max(RL * RL - dot(p.xy, p.xy), 0.0)))));
    a *= smoothstep(-0.005, 0.03, min(ld.x, ld.y)) * step(0.0, p.z);
  }
  float f = smoothstep(0.0, 1.0, clamp(uForm * 1.6 - h11(seed * 3.0) * 0.6, 0.0, 1.0));
  float sa = h11(seed) * PI2 + (1.0 - f) * 2.0, sr = 1.4 + 2.2 * h11(seed + 4.0);
  vec3 scatter = vec3(cos(sa) * sr * 1.3, (h11(seed + 1.0) - 0.5) * 2.2, sin(sa) * sr * 0.5 - 0.6);
  p = mix(scatter, p, f);
  float cy = cos(uCam.x), sy = sin(uCam.x), cp = cos(uCam.y), sp = sin(uCam.y);
  mat3 Rc = mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy) * mat3(1.0, 0.0, 0.0, 0.0, cp, -sp, 0.0, sp, cp);
  p = p * Rc;
  float w = D - p.z;
  vec2 uv = p.xy * D / (w * 1.0104);
  gl_Position = vec4((uEye.xy + uv * uEye.z) * uPx * 2.0 - 1.0, 0.0, 1.0);
  float blur = (kind > 5.5 ? 0.1 : abs(p.z - 0.85) * 2.2) + (1.0 - f) * 0.6;
  float px = size * uEye.z * 0.03 * D / w;
  gl_PointSize = min(px * (1.0 + blur), 96.0);
  vCol = mix(mix(MINT, VIO, step(0.55, h11(seed * 11.0))) * 0.35, col * a, f) / (1.0 + blur * blur * 2.5);
  float gid = floor(fract(meta.z + floor(uTime * (0.3 + 2.0 * h11(seed * 5.0)) + seed * 13.0) * 0.618 * step(0.6, h11(seed * 9.0))) * 61.0);
  vCell = vec2(mod(gid, 8.0), floor(gid / 8.0));
  vSharp = clamp(1.0 - blur * 0.8, 0.0, 1.0);
}`;

const FSP = `precision highp float;
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

const BG = `${HEAD}
void main(){
  vec2 uv; vec3 ro, rd;
  camera(uv, ro, rd, 1.0);
  float r = length(uv * vec2(1.0, 1.6));
  vec3 col = bokeh(uv) + (MINT * 0.5 + VIO * 0.5) * 0.012 * (0.5 + uAct) * exp(-1.6 * max(r - 0.4, 0.0));
  oCol = vec4(clean(col), 1.0);
}`;

/* Builds the swarm: iris rings, collarette, sclera dust, both lid sheets, far dust, the catchlight. */
function swarm(n) {
  const pos = [], meta = [], R = (a, b) => a + (b - a) * Math.random();
  const add = (x, y, z, kind, size) => { pos.push(x, y, z); meta.push(kind, Math.random() * 1000, Math.random(), size); };
  const rings = Math.round(15 * n);
  for (let i = 0; i < rings; i++) {
    const rn = (i + 0.5) / rings, count = Math.round((34 + 120 * rn) * n), spd = R(0.02, 0.06);
    for (let k = 0; k < count; k++) add(rn + R(-0.01, 0.01), (k + R(0, 0.3)) / count, spd, 0, R(0.8, 1.1));
  }
  for (let k = 0; k < Math.round(90 * n); k++) add(0.3 + R(-0.012, 0.012), k / Math.round(90 * n), 0.03, 5, 1.05);
  for (let k = 0; k < Math.round(2600 * n); k++) {
    const z = R(0.2, 0.88), a = R(0, Math.PI * 2), s = Math.sqrt(1 - z * z);
    add(Math.cos(a) * s, Math.sin(a) * s, z, 1, R(0.35, 0.7));
  }
  for (const kind of [2, 3]) for (let row = 0; row < 7; row++) {
    const d = row === 0 ? 0.0 : 0.012 * Math.pow(row, 1.5), count = Math.round((row === 0 ? 120 : 90) * n);
    for (let k = 0; k < count; k++) add(-1 + 2 * (k + R(0.2, 0.8)) / count, d + R(0, 0.006), 0, kind, row === 0 ? 0.8 : R(0.55, 0.85));
  }
  for (let k = 0; k < Math.round(500 * n); k++) add(R(-5, 5), R(-3.2, 3.2), R(-4, 2.5), 4, R(0.8, 1.6));
  for (let k = 0; k < Math.round(110 * n); k++) add(R(-1, 1), R(-1, 1), 0, 6, R(0.35, 0.5));
  return { pos: new Float32Array(pos), meta: new Float32Array(meta), count: pos.length / 3 };
}

/* Variant C for the lab engine. */
export function variantC() {
  let pts, bg, U, B, built = 0;
  return {
    name: "Swarm",
    init({ T, quad, S }) {
      const tex = atlas();
      U = { uEye: { value: new T.Vector3() }, uCam: { value: new T.Vector2() }, uGaze: { value: new T.Vector3(0, 0, 1) }, uLid: { value: new T.Vector4(0.4, 0.3, 0, 0) },
        uFlash: { value: new T.Vector4() }, uPupil: { value: 0.3 }, uTime: { value: 0 }, uAct: { value: 0.3 }, uForm: { value: 0 }, uPx: { value: new T.Vector2() }, uAtlas: { value: tex } };
      B = { uRes: { value: new T.Vector2() }, uEye: U.uEye, uCam: U.uCam, uGaze: U.uGaze, uLid: U.uLid, uFlash: U.uFlash, uPupil: U.uPupil, uTime: U.uTime, uAct: U.uAct,
        uQ: { value: 2 }, uAtlas: { value: tex } };
      bg = quad(BG, B);
      const s = swarm(S.q === 2 ? 1 : S.q === 1 ? 0.75 : 0.5);
      const geo = new T.BufferGeometry();
      geo.setAttribute("position", new T.BufferAttribute(s.pos, 3));
      geo.setAttribute("meta", new T.BufferAttribute(s.meta, 4));
      pts = new T.Points(geo, new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: VS, fragmentShader: FSP, uniforms: U, depthTest: false, depthWrite: false, transparent: true, blending: T.AdditiveBlending }));
      pts.frustumCulled = false;
      built = s.count;
    },
    step(S, t, dt, life) {
      const v = life.view();
      U.uGaze.value.set(...v.gaze); U.uLid.value.set(...v.lid); U.uFlash.value.set(...v.flash); U.uCam.value.set(...v.cam);
      U.uPupil.value = v.pupil; U.uAct.value = v.act; U.uTime.value = t;
      S.formT = (S.formT || 0) + dt;
      const form = still.matches ? 1 : Math.min(1, S.formT / 2.2);
      U.uForm.value = form;
      return form < 1 ? 2 : 0;
    },
    draw(r, cam, S) {
      U.uEye.value.set(S.eye.x, S.eye.y, S.eye.r); U.uPx.value.set(1 / S.hdr.width, 1 / S.hdr.height); B.uRes.value.set(S.hdr.width, S.hdr.height);
      r.render(bg, cam); r.render(pts, cam);
    },
    get count() { return built; },
  };
}
