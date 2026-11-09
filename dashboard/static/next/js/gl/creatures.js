/* Agent creatures on the stage: where each Familiar stands on its ring, its entrance, leap and name tag, and the glyph streams from the eye to the working ones; the bodies are drawn by gl/familiars. */
import { project, ringPoint, D } from "./cam.js";
import { createFamiliars } from "./familiars/layer.js";
import { hash, pose } from "../familiars/genome.js";

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

const PER = 26;
const easeBack = (x) => { const c = 1.5; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };
/* Screen box [l, t, r, b] a creature of drawn size s at (x, y) covers, badge and pad included. */
const footprint = (x, y, s, up = 0.88) => [x - 0.65 * s, y - up * s, x + 0.65 * s, y + 0.76 * s];
const hits = (a, b) => a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3];
/* Top-left of a w×h tag for the creature at (x, y, s): below, above, right or left, the first side clear of every box and inside span [lo, hi]; null when none is. */
export function tagSpot(x, y, s, w, h, boxes, [lo, hi]) {
  const g = 0.06 * s, b = footprint(x, y, s);
  for (const [l, t] of [[x - w / 2, b[3] + g], [x - w / 2, b[1] - g - h], [b[2] + g, y - h / 2], [b[0] - g - w, y - h / 2]]) {
    const L = Math.max(lo, Math.min(hi - w, l)), R = [L, t, L + w, t + h];
    if (!boxes.some((o) => hits(R, o))) return [L, t];
  }
  return null;
}

/* The creature layer: set(list) with {id, state, role, live, ring: {r, a}, dir, up, size, min, tag}; a hook for the stage (step, back, front). */
export function createCreatures(ctx, tex, st) {
  const { T, r } = ctx, fam = createFamiliars(ctx);
  const U = { uRes: { value: new T.Vector2() }, uTime: { value: 0 }, uAtlas: { value: tex } };

  const SU = { uRes: U.uRes, uTime: U.uTime, uAtlas: U.uAtlas, uA: { value: new T.Vector4() },
    uB: { value: Array.from({ length: 8 }, () => new T.Vector4()) }, uC: { value: Array.from({ length: 8 }, () => new T.Vector4()) } };
  const sg = new T.BufferGeometry(), sa = new Float32Array(8 * PER * 4);
  for (let i = 0; i < 8; i++) for (let j = 0; j < PER; j++) { const o = (i * PER + j) * 4; sa[o] = i; sa[o + 1] = j / PER; sa[o + 2] = (i * 13 + j * 7) % 61; sa[o + 3] = ((j * 2654435761) >>> 0) % 1000 / 1000; }
  sg.setAttribute("position", new T.BufferAttribute(new Float32Array(8 * PER * 3), 3));
  sg.setAttribute("aS", new T.BufferAttribute(sa, 4));
  const streams = new T.Points(sg, new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: SVS, fragmentShader: SFS, uniforms: SU, transparent: true, depthTest: false, depthWrite: false, blending: T.AdditiveBlending }));
  streams.frustumCulled = false;

  const all = new Map(), fx = document.getElementById("fx");
  let n = [0, 0.3, 0.954], spin = false, list = [], nStream = 0, lastT = 0, lastDt = 0;

  function make(s, i, t) {
    const seed = (hash(s.id + "s") % 1000) / 1000;
    return { id: s.id, seed, e: 0, eGoal: 1, delay: t + 0.05 + i * 0.07, state: s.state, jump: -9, glanceAt: t + 2 + seed * 6, glanceTo: -9, spec: s, tag: null, on: false };
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
        if (c.state === "working" && s.state === "done" && !st.still()) { c.jump = t; c.cheer = true; }
      }
      c.state = s.state; c.spec = s;
      if (c.tag) { c.tag.innerHTML = s.tag || ""; c.tagW = null; }
    });
    st.wake(0);
  };
  C.count = () => all.size;

  /* Animation state; true while anything must run at full rate. */
  C.step = (t, dt) => {
    lastT = t; lastDt = dt;
    let hot = fam.busy;
    const calm = st.still();
    for (const c of [...all.values()]) {
      if (t >= c.delay) {
        const k = calm ? 1 : Math.min(1, dt / (c.eGoal ? 0.55 : 0.35));
        c.e = c.eGoal ? Math.min(1, c.e + k) : Math.max(0, c.e - k);
      }
      if (c.e !== c.eGoal) hot = true;
      if (!c.eGoal && c.e <= 0) { all.delete(c.id); fam.drop(c.id); if (c.tag) c.tag.remove(); continue; }
      if (t - c.jump < 0.8 || (c.on && !calm && pose(c.state) !== "sleep")) hot = true;
      if (t > c.glanceAt) { c.glanceTo = t + 1.3; c.glanceAt = t + 4 + ((c.seed * 3.7 + t * 0.61) % 1) * 6; }
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
      const p0 = ringPoint(s.ring.r, s.ring.a + turn * (s.dir ?? 1), n), p = [p0[0] * ee, p0[1] * ee + (1 - ee) * 0.05, p0[2] * ee];
      const q = project(p, E, cam), size = Math.max(s.min || 0, (s.size || 0.5) * q.s) * Math.min(1, e * 1.4);
      const dx = E.x - q.x, dy = q.y - E.y, dl = Math.hypot(dx, dy) || 1, dir = [dx / dl, -dy / dl];
      const jf = (t - c.jump) / 0.75, jump = jf >= 0 && jf < 1 ? Math.sin(Math.PI * jf) * 0.62 : 0;
      const land = jf >= 0 && jf < 1.25 ? (jf < 0.12 ? -0.14 * Math.sin((jf / 0.12) * Math.PI) : jf > 0.95 ? -0.16 * Math.sin(Math.min(1, (jf - 0.95) / 0.3) * Math.PI) : 0.08 * Math.sin(jf * Math.PI)) : 0;
      const glance = t < c.glanceTo || jf >= 0 && jf < 1.6;
      c.on = q.x > -size && q.x < innerWidth + size && q.y > -size && q.y < H + size;
      out.push({ c, q, size, jump, squash: land, yaw: glance ? Math.max(-0.35, Math.min(0.35, dir[0] * 0.35)) : 0, e });
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
  /* Hands one depth-sorted pass of creatures to the Familiars layer, in HDR pixels. */
  function draw(arr, S) {
    const k = S.k, H = innerHeight;
    fam.draw(arr.map((o) => ({ id: o.c.id, role: o.c.spec.role || (o.c.spec.big ? "worker" : "crew"), state: o.c.state, live: o.c.spec.live, x: o.q.x * k, y: (H - o.q.y) * k, size: o.size * k, yaw: o.yaw, lift: o.jump * o.size * 0.5 * k, squash: o.squash,
      fade: Math.min(1, o.e * 1.6) * (o.q.z > D ? Math.max(0.55, 1 - (o.q.z - D) * 0.12) : 1) })), S, lastT, st.still() ? 1 : lastDt);
  }
  /* Tags sit on the first side clear of every creature and earlier tag (run tags first), hidden when no side is clear. */
  function tags(arr) {
    if (!fx) return;
    const W = innerWidth, span = st.E.span || [0, W], boxes = arr.filter((o) => o.e > 0.3).map((o) => footprint(o.q.x, o.q.y, o.size, o.c.spec.up));
    for (const o of [...arr].sort((a, b) => !!b.c.spec.big - !!a.c.spec.big)) {
      const c = o.c, s = c.spec;
      if (!s.tag) continue;
      if (!c.tag) { c.tag = document.createElement("div"); c.tag.innerHTML = s.tag; fx.appendChild(c.tag); }
      const cls = "otag " + c.state + (s.big ? " lg" : "");
      if (c.tag.className !== cls) { c.tag.className = cls; c.tagW = null; }
      if (c.tagW == null || c.tagVW !== W) { c.tagW = c.tag.offsetWidth; c.tagH = c.tag.offsetHeight; c.tagVW = W; }
      const at = c.tagW ? tagSpot(o.q.x, o.q.y, o.size, c.tagW, c.tagH, boxes, span) : null;
      if (at) boxes.push([at[0], at[1], at[0] + c.tagW, at[1] + c.tagH]);
      const tf = at ? `translate3d(${at[0].toFixed(1)}px,${at[1].toFixed(1)}px,0)` : c.tagT, op = at ? Math.min(1, o.e * 1.3).toFixed(2) : "0";
      if (c.tagT !== tf) { c.tag.style.transform = c.tagT = tf; }
      if (c.tagO !== op) { c.tag.style.opacity = c.tagO = op; }
    }
  }

  let placed = [], ahead = [];
  C.back = (S) => {
    if (!all.size) { nStream = 0; return; }
    U.uRes.value.set(S.hdr.width, S.hdr.height); U.uTime.value = lastT;
    placed = place(S);
    const E = st.E, behind = placed.filter((o) => o.q.z > D && Math.hypot(o.q.x - E.x, o.q.y - E.y) < 1.2 * E.r + 0.7 * o.size);
    ahead = placed.filter((o) => !behind.includes(o));
    if (behind.length) draw(behind, S);
    tags(placed);
  };
  C.front = (S) => {
    if (!all.size) return;
    if (ahead.length) draw(ahead, S);
    if (nStream) { SU.uB.value.slice(nStream).forEach((v) => v.set(0, 0, 0, 0)); SU.uC.value.slice(nStream).forEach((v) => v.set(0, 0, 0, 0)); r.render(streams, st.ctx.cam); }
  };
  /* Screen position of creature id, for a glance of the eye. */
  C.at = (id) => { const o = placed.find((x) => x.c.id === id); return o ? o.q : null; };
  C.cheers = () => { const out = []; for (const c of all.values()) if (c.cheer) { c.cheer = false; out.push(c.id); } return out; };
  return C;
}
