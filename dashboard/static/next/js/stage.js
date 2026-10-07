/* The stage: the director over the engine — the eye at its anchor, the living field, the glyph mass, the creatures, the eye's life and the frame rhythm. */
import { createEngine, still, phone } from "./gl/engine.js";
import { createLife } from "./gl/life.js";
import { EYE, FACE, project, ringPoint } from "./gl/eye.js";
import { createField } from "./gl/field.js";
import { createMass } from "./gl/mass.js";
import { createCreatures } from "./gl/creatures.js";
import { atlas } from "./gl/glyphs.js";

export { still };
const MORPH_MS = 1100, FORM_MS = 2200, ORBIT_FPS = 6, ORBIT_S = 180, LIFE_FPS = 12, WARM_FPS = 30, GRACE_S = 30, EASE_S = 5;
const LIFE_RATE = [0, LIFE_FPS, WARM_FPS, 60], MASS_RATE = [0, WARM_FPS, 60];
const COL = { mint: [0.074, 1, 0.35], gold: [1, 0.637, 0.133], vio: [0.434, 0.074, 1], ice: [0.347, 0.807, 1] };
const smooth = (x) => x * x * (3 - 2 * x);

/* Where the world span of a scene sits on screen: centre, camera distance and tilt, from its box. */
function fitOf(sc) {
  const W = innerWidth, H = innerHeight, b = sc.box && sc.box.isConnected ? sc.box.getBoundingClientRect() : { left: 0, top: 0, width: W, height: H };
  const fixed = !sc.box || sc.box.id === "gl", sy = scrollY;
  const vis = Math.max(0.05, Math.min(b.width, b.height * (sc.ar || 1.9)) / W);
  const d = sc.span / vis / (2 * Math.tan((32 * Math.PI) / 360) * (W / H)) * (1 + 0.25 * Math.min(1, sy / H));
  return { cx: b.left + b.width / 2, cy: b.top + b.height / 2 + (fixed ? -0.25 * sy : 0.4 * sy), d, tilt: sc.tilt || 0 };
}

export function createStage(canvas) {
  const life = createLife({ seed: 7, still: () => still.matches });
  let eng, field, mass, eye, U, tex, crowd;
  const E = { x: innerWidth / 2, y: innerHeight * 0.4, r: 0, vx: 0, vy: 0, vr: 0, set: false, calm: false, vis: true };
  const rings = { n: 0, cur: new Float32Array(32), goal: new Float32Array(32), flash: new Float32Array(8) };
  const par = { x: 0, y: 0, tx: 0, ty: 0 }, rip = { i: 0, list: [0, 1, 2, 3].map(() => [0, 0, -9, 0]) };
  let sc = null, fitFrom = null, fitNow = null, morphT0 = 0, drift = 0, lastNow = 0, scrollT = 0, spin = 0, ft = 0, bootT0 = 0, viaT0 = 0, aliveT = 0, tempo = 1;
  const st = { life, E, sc: null, spin: 0, hooks: new Set() };

  const director = {
    nextAt: Infinity,
    init(ctx) {
      const { T } = ctx;
      tex = atlas(T);
      field = createField(ctx, tex);
      mass = createMass(ctx, tex, phone() ? 3200 : 6400);
      U = { uRes: { value: new T.Vector2() }, uEye: { value: new T.Vector3() }, uCam: { value: new T.Vector2() }, uGaze: { value: new T.Vector3(0, 0, 1) },
        uLid: { value: new T.Vector4(0.4, 0.3, 1, 0) }, uFlash: { value: new T.Vector4() }, uPupil: { value: 0.3 }, uTime: { value: 0 }, uAct: { value: 0.3 },
        uQ: { value: 2 }, uSpin: { value: 0 }, uRingK: { value: 0 }, uSleep: { value: 0 }, uHalo: { value: 1 }, uAtlas: { value: tex },
        uRingN: { value: new T.Vector3(...FACE) }, uRing: { value: Array.from({ length: 8 }, () => new T.Vector4()) }, uForm: { value: 1 }, uPx: { value: new T.Vector2() } };
      eye = EYE.create(ctx, U);
      st.ctx = ctx;
      crowd = createCreatures(ctx, tex, st);
      st.hooks.add(crowd);
    },
    /* The wanted frame rate: 60 for input, travel, screen morphs and the alive grace, 30 while data settles, the orbit and idle life slower, else 0 until life.nextAt. */
    step(t, dt, full) {
      const now = performance.now(), fdt = lastNow ? Math.min(0.1, (now - lastNow) / 1000) : dt;
      lastNow = now;
      let fps = full ? 60 : 0;
      const want = (f) => { if (f > fps) fps = f; };
      const age = (now - aliveT) / 1000, g = still.matches ? 0 : age < GRACE_S ? 1 : 1 - smooth(Math.min(1, (age - GRACE_S) / EASE_S));
      tempo = g <= tempo ? g : tempo + (g - tempo) * Math.min(1, fdt * 4);
      if (tempo > 0.001) want(60); else tempo = 0;
      ft += fdt * tempo;
      if (sc && placeEye(fdt)) want(60);
      E.vis = E.r > 0 && E.y + 1.4 * E.r > 0 && E.y - 1.4 * E.r < innerHeight;
      const lv = life.step(t, dt, ft);
      if (lv > 1 || E.vis) want(LIFE_RATE[lv]);
      want(MASS_RATE[mass.step(now)]);
      if (morphT0) want(WARM_FPS);
      if ((U.uForm.value = formAt(now)) < 1) want(60);
      if (ringStep(fdt)) want(WARM_FPS);
      if (rip.list.some((r) => r[3] > 0 && ft - r[2] < 1.6)) want(WARM_FPS);
      if (Math.abs(par.tx - par.x) + Math.abs(par.ty - par.y) > 0.002) want(60);
      par.x += (par.tx - par.x) * Math.min(1, fdt * 6); par.y += (par.ty - par.y) * Math.min(1, fdt * 6);
      if (now - scrollT < 160) want(60);
      drift += dt * tempo * (0.5 + 1.5 * life.load);
      const orbit = sc && sc.orbit && !still.matches;
      if (orbit) spin += fdt * ((Math.PI * 2) / ORBIT_S);
      st.spin = spin;
      for (const h of st.hooks) if (h.step && h.step(t, fdt)) want(WARM_FPS);
      for (const id of crowd.cheers()) { const q = crowd.at(id); if (q) st.event("done", q.x, q.y); }
      if (orbit && E.vis) want(ORBIT_FPS);
      director.nextAt = E.vis ? life.nextAt : Infinity;
      return fps;
    },
    draw(S) {
      const { r } = st.ctx, k = S.k, H = innerHeight, hdr = S.hdr;
      S.ctr = [E.x, E.y];
      const f = field.U;
      f.uRes.value.set(hdr.width, hdr.height); f.uTime.value = ft; f.uAct.value = life.act; f.uDrift.value = drift;
      f.uPar.value.set(par.x, par.y); f.uScroll.value = scrollY / H; f.uEye.value.set(E.x * k, (H - E.y) * k, E.r * k); f.uAura.value = E.vis ? 1 - 0.7 * life.sleep : 0;
      const m = morphT0 ? Math.min(1, (performance.now() - morphT0) / MORPH_MS) : 1;
      f.uZoom.value = 1 + 0.07 * Math.sin(Math.PI * m);
      rip.list.forEach((q, i) => f.uRip.value[i].set(...q));
      r.render(field.mesh, st.ctx.cam);
      placeMass(S);
      mass.U.uSide.value = 0;
      r.render(mass.scene, mass.cam);
      for (const h of st.hooks) if (h.back) h.back(S);
      if (E.vis && E.r > 1) drawEye(S);
      for (const h of st.hooks) if (h.front) h.front(S);
      if (mass.transit()) { mass.U.uSide.value = 1; r.render(mass.scene, mass.cam); }
      if (sc && sc.frame) sc.frame(st);
    },
    probe(S) {
      const k = S.k;
      U.uRes.value.set(S.hdr.width, S.hdr.height);
      U.uEye.value.set(S.hdr.width / 2, S.hdr.height / 2, (Math.min(innerWidth, innerHeight) / 3) * k);
      eye.probe(S);
    },
  };

  /* Springs the eye to its anchor; true while it travels. */
  function placeEye(dt) {
    const el = sc.eyeEl;
    if (!el || !el.isConnected) return false;
    const b = el.getBoundingClientRect(), g = sc.eyeFit(b);
    if (!E.set || still.matches) { Object.assign(E, g, { vx: 0, vy: 0, vr: 0, set: true, calm: true }); return false; }
    if (E.calm && Math.abs(g.r - E.r) < 0.5) { E.x = g.x; E.y = g.y; return false; }
    E.calm = false;
    const w = 8.5;
    for (const [p, v] of [["x", "vx"], ["y", "vy"], ["r", "vr"]]) { E[v] += (w * w * (g[p] - E[p]) - 2 * w * E[v]) * dt; E[p] += E[v] * dt; }
    if (Math.hypot(g.x - E.x, g.y - E.y, g.r - E.r) < 0.4 && Math.hypot(E.vx, E.vy, E.vr) < 8) { Object.assign(E, g, { vx: 0, vy: 0, vr: 0, calm: true }); return false; }
    return true;
  }

  function ringStep(dt) {
    let busy = false;
    for (let i = 0; i < 8; i++) {
      const d = rings.goal[i] - rings.cur[i];
      if (Math.abs(d) > 0.0015) { rings.cur[i] += d * (still.matches ? 1 : Math.min(1, dt * 4)); busy = true; } else rings.cur[i] = rings.goal[i];
      rings.flash[i] *= Math.exp(-dt / 0.45);
      if (rings.flash[i] > 0.04) busy = true; else rings.flash[i] = 0;
    }
    return busy;
  }

  function placeMass(S) {
    if (!sc) return;
    const now = fitOf(sc), m = morphT0 ? Math.min(1, (performance.now() - morphT0) / MORPH_MS) : 1, e = 1 - Math.pow(1 - m, 3);
    fitNow = fitFrom && m < 1 ? { cx: fitFrom.cx + (now.cx - fitFrom.cx) * e, cy: fitFrom.cy + (now.cy - fitFrom.cy) * e, d: fitFrom.d + (now.d - fitFrom.d) * e, tilt: fitFrom.tilt + (now.tilt - fitFrom.tilt) * e } : now;
    if (m >= 1) morphT0 = 0;
    const cam = mass.cam, W = innerWidth, H = innerHeight, q = fitNow;
    cam.aspect = W / H;
    cam.position.set(0, Math.sin(q.tilt) * q.d, Math.cos(q.tilt) * q.d); cam.lookAt(0, 0, 0);
    cam.setViewOffset(W, H, W / 2 - q.cx, H / 2 - q.cy, W, H);
    cam.updateProjectionMatrix(); cam.updateMatrixWorld();
    mass.pts.rotation.set(par.y * 0.05, par.x * 0.05, 0);
    mass.pts.updateMatrixWorld();
    const M = mass.U;
    M.uPx.value = (S.hdr.height * 0.5) / Math.tan((32 * Math.PI) / 360) * 0.026;
    M.uFocus.value = q.d; M.uTime.value = ft;
    if (mass.transit()) {
      const T = st.ctx.T, v = new T.Vector3((E.x / W) * 2 - 1, 1 - (E.y / H) * 2, 0.5).unproject(cam), o = cam.position.clone(), fwd = new T.Vector3();
      cam.getWorldDirection(fwd);
      const dir = v.sub(o).normalize(), p = o.addScaledVector(dir, q.d / Math.max(0.2, dir.dot(fwd)));
      M.uPupil.value.copy(mass.pts.worldToLocal(p));
      M.uAxis.value.copy(fwd).applyQuaternion(mass.pts.quaternion.clone().invert());
    }
  }

  function drawEye(S) {
    const { r } = st.ctx, k = S.k, H = innerHeight, hdr = S.hdr, v = life.view();
    U.uRes.value.set(hdr.width, hdr.height); U.uEye.value.set(E.x * k, (H - E.y) * k, E.r * k);
    U.uGaze.value.set(...v.gaze); U.uLid.value.set(...v.lid); U.uFlash.value.set(...v.flash);
    U.uCam.value.set(v.cam[0], v.cam[1]); U.uPupil.value = v.pupil; U.uAct.value = v.act; U.uTime.value = ft; U.uQ.value = S.q;
    U.uSleep.value = v.sleep; U.uSpin.value = spin; U.uRingK.value = rings.n;
    for (let i = 0; i < 8; i++) U.uRing.value[i].set(rings.cur[i + 8], rings.cur[i], rings.cur[i + 16], rings.flash[i]);
    const ext = eyeExtent();
    const x0 = Math.max(0, Math.floor((E.x - ext[0]) * k)), x1 = Math.min(hdr.width, Math.ceil((E.x + ext[1]) * k));
    const y0 = Math.max(0, Math.floor((H - E.y - ext[3]) * k)), y1 = Math.min(hdr.height, Math.ceil((H - E.y + ext[2]) * k));
    if (x1 <= x0 || y1 <= y0) return;
    eye.draw(S, [x0, y0, x1 - x0, y1 - y0]);
  }
  /* How assembled the eye is: 0 → 1 over FORM_MS at boot; on a screen change it breathes out and back in over MORPH_MS. */
  function formAt(now) {
    if (still.matches) return 1;
    let f = bootT0 ? Math.min(1, (now - bootT0) / FORM_MS) : 1;
    if (f >= 1) bootT0 = 0;
    const m = viaT0 ? (now - viaT0) / MORPH_MS : 1;
    if (m >= 1) viaT0 = 0; else f = Math.min(f, 1 - 0.7 * Math.sin(Math.PI * m));
    return f;
  }
  /* Pixels the eye pass covers left, right, up and down of the centre: eyeball, halo and the outermost ring. */
  function eyeExtent() {
    const R = E.r, cam = life.cam;
    const e = [1.2 * R, 1.2 * R, 1.2 * R, 1.2 * R];
    if (U.uHalo.value > 0.01) { e[0] = e[1] = 1.72 * R; e[2] = Math.max(e[2], 0.75 * R); e[3] = Math.max(e[3], 0.75 * R); }
    let out = 0;
    for (let i = 0; i < rings.n; i++) out = Math.max(out, rings.cur[i + 8]);
    if (out > 0) {
      const n = [U.uRingN.value.x, U.uRingN.value.y, U.uRingN.value.z];
      for (let j = 0; j < 24; j++) {
        const p = project(ringPoint(out + 0.14, j / 24, n), E, cam);
        e[0] = Math.max(e[0], E.x - p.x); e[1] = Math.max(e[1], p.x - E.x); e[2] = Math.max(e[2], E.y - p.y); e[3] = Math.max(e[3], p.y - E.y);
      }
      e.forEach((v, i) => { e[i] = v + 0.12 * R; });
    }
    return e;
  }

  eng = createEngine(canvas, director);
  st.eng = eng;
  st.S = eng.S;
  st.wake = (ms) => eng.wake(ms);
  st.clock = () => eng.clock();
  st.still = () => still.matches;
  /* Input or a data change: the ambient motion runs at full rate for GRACE_S, then eases to rest over EASE_S. */
  const touch = () => { aliveT = performance.now(); };
  document.addEventListener("visibilitychange", () => { if (!document.hidden) touch(); });

  /* A scene: {pts, box, span, tilt, ar, eyeEl, eyeFit(rect), rings:[{r, v, kind}], ringN, halo, sleep, orbit, creatures, frame(st), pulse (kind, or false)}.
     via = the screen changed (the mass flows through the pupil), data = same screen with new data, keep = same shape, fresh DOM. */
  st.show = (next, { via = false, data = false, keep = false } = {}) => {
    const first = !sc, same = keep || data;
    if (sc && !keep) fitFrom = fitNow || fitOf(sc);
    sc = next; st.sc = next;
    U.uHalo.value = next.halo == null ? 1 : next.halo;
    U.uRingN.value.set(...(next.ringN || FACE));
    const R = next.rings || [];
    if (!same) for (let i = 0; i < 8; i++) { rings.cur[i] = 0; rings.flash[i] = 0; }
    rings.n = Math.min(8, R.length);
    R.slice(0, 8).forEach((g, i) => {
      const v = Math.max(0, Math.min(1, g.v || 0));
      if (same && Math.abs(rings.goal[i] - v) > 0.02 && !still.matches) rings.flash[i] = 1;
      rings.goal[i] = v; rings.cur[i + 8] = rings.goal[i + 8] = g.r; rings.cur[i + 16] = rings.goal[i + 16] = g.kind || 0;
    });
    life.setData({ sleep: +next.sleep || 0 });
    crowd.set(next.creatures || [], { normal: next.ringN || FACE, turn: !!next.orbit, fresh: !same });
    if (keep) { eng.wake(0); return; }
    if (!data) touch();
    const animate = !first && !still.matches;
    const moved = mass.show(next.pts, { via: via && animate, instant: !animate, dur: via ? MORPH_MS : 900 });
    morphT0 = moved && fitFrom ? performance.now() : 0;
    if (first && !still.matches) bootT0 = performance.now();
    if (via && animate) viaT0 = performance.now();
    if (first) { life.setData({ sleep: true }); life.sleep = 1; setTimeout(() => { life.setData({ sleep: +sc.sleep || 0 }); eng.wake(1200); }, 350); }
    eng.wake(animate && !data ? MORPH_MS + 100 : 0);
  };
  /* Data changed on the same screen: one rim wave from the eye, an iris flash in the kind's colour. */
  st.pulse = (kind = "info") => {
    if (still.matches) { eng.wake(0); return; }
    touch();
    const c = COL[kind === "needs" || kind === "done" ? "gold" : kind === "stray" ? "vio" : "mint"];
    mass.ping(c);
    life.event(kind, null, null, eng.clock());
    ripple(E.x, E.y, 0.8);
    eng.wake(0);
  };
  st.look = (x, y, dur) => { if (E.r > 0) { life.look((x - E.x) / E.r, (E.y - y) / E.r, eng.clock(), dur); eng.wake(500); } };
  st.event = (kind, x, y) => { touch(); if (E.r > 0) { life.event(kind, x == null ? null : (x - E.x) / E.r, y == null ? null : (E.y - y) / E.r, eng.clock()); eng.wake(1500); } };
  st.data = (d) => { life.setData(d); };
  function ripple(x, y, w = 1) {
    const q = rip.list[rip.i++ % 4], H = innerHeight;
    q[0] = (x - innerWidth / 2) / H; q[1] = (H / 2 - y) / H; q[2] = ft; q[3] = w;
  }
  /* Press feedback: a ripple through the field at the press point and a glance of the eye. */
  st.press = (x, y) => {
    if (still.matches) return;
    touch();
    ripple(x, y, 1);
    if (E.r > 0) {
      const u = (x - E.x) / E.r, v = (E.y - y) / E.r;
      if (Math.hypot(u, v * 1.6) < 0.95) life.event("poke", u, v, eng.clock()); else life.look(u, v, eng.clock(), 0.9);
    }
    eng.wake(400);
  };
  st.pointer = (x, y, fine) => {
    if (still.matches) return;
    touch();
    if (fine) { par.tx = (x / innerWidth - 0.5) * 2; par.ty = (0.5 - y / innerHeight) * 2; }
    if (E.r > 0) life.setPointer((x - E.x) / E.r, (E.y - y) / E.r, eng.clock());
    eng.wake(fine ? 300 : 500);
  };
  st.leave = () => { par.tx = par.ty = 0; life.setPointer(null, null, eng.clock()); eng.wake(300); };
  st.scroll = () => { scrollT = performance.now(); touch(); eng.wake(0); };
  /* Screen position of an eye-space point with the current eye and camera. */
  st.project = (p) => project(p, E, life.cam);
  /* Screen position of a point of the glyph mass, through the mass camera as last drawn. */
  st.massProject = (x, y, z) => { const v = new st.ctx.T.Vector3(x, y, z).applyMatrix4(mass.pts.matrixWorld).project(mass.cam); return { x: ((v.x + 1) * innerWidth) / 2, y: ((1 - v.y) * innerHeight) / 2 }; };
  st.ringPoint = ringPoint;
  st.frames = () => eng.S.frames;
  return st;
}
