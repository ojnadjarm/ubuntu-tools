/* The renderer the office screen talks to: chunks, creatures, light surfaces and halos on one stage; the still renderer is the same object. */
import { stage } from "./stage.js";
import { chunks } from "./chunks.js";
import { creatures } from "./creatures.js";
import { effects } from "./fx.js";
import { halos } from "./halos.js";

const HALL = "hall", SLICE_MS = 8, REACH = 2.6, TAP_PX = 22, made = new WeakMap(), inks = new Map();

/* Lit pixel runs of a text set in the page's monospace: {w, h, runs: [[x0, x1, y]]}. */
function ink(text) {
  if (inks.has(text)) return inks.get(text);
  const c = document.createElement("canvas"), g = c.getContext("2d", { willReadFrequently: true }), font = "bold 12px ui-monospace, 'DejaVu Sans Mono', Menlo, Consolas, monospace";
  g.font = font; c.width = Math.ceil(g.measureText(text).width) + 2; c.height = 14;
  g.font = font; g.textBaseline = "middle"; g.fillStyle = "#fff"; g.fillText(text, 1, 7.5);
  const d = g.getImageData(0, 0, c.width, c.height).data, runs = [];
  for (let y = 0; y < c.height; y++) for (let x = 0, a = -1; x <= c.width; x++) { const on = x < c.width && d[(y * c.width + x) * 4 + 3] > 96; if (on && a < 0) a = x; if (!on && a >= 0) { runs.push([a, x, y]); a = -1; } }
  const out = { w: c.width, h: c.height, runs };
  inks.set(text, out);
  return out;
}
/* Distance in pixels from p to the segment a-b. */
function reach(p, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y, k = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy || 1)));
  return Math.hypot(p.x - a.x - dx * k, p.y - a.y - dy * k);
}

/* True when pixel p lies inside the convex polygon Q (projected corners in order). */
function inside(p, Q) {
  let sign = 0;
  for (let i = 0; i < Q.length; i++) {
    const a = Q[i], b = Q[(i + 1) % Q.length], c = Math.sign((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x));
    if (c && sign && c !== sign) return false;
    sign = sign || c;
  }
  return true;
}

/* The lamps that reach the box of chunk c on the ground plan: bake cuts a lamp at REACH radii. */
const near = (c, lamps) => lamps.filter((l) => l.i > 0 && Math.hypot(Math.max(c.lo[0] - l.x, 0, l.x - c.hi[0]), Math.max(c.lo[2] - l.z, 0, l.z - c.hi[2])) <= REACH * l.r);

/* createRenderer(canvas, {theme, kit, still?, build?, chunk?, ink?}) → Renderer; one per canvas, a second call returns the first. build = {steps, stamp?} defaults to build/index.js; chunk is a one-step build. */
export function createRenderer(canvas, opts) {
  if (made.has(canvas)) return made.get(canvas);
  const S = stage(canvas, { still: opts.still }), mesh = chunks(S), fam = creatures(S.scene), fx = effects(S.scene), halo = halos(S), lit = halos(S), built = new Map(), anchors = new Map();
  let B = opts.build || (opts.chunk && { steps: (...a) => [() => opts.chunk(...a)] }), actors = [], boards = [], jobs = [], raf = 0, cur = null, fit = false, queued = null, hot = null, tally = { rebuilt: 0, relit: 0, ms: 0 };
  S.ticker((t, dt) => { fx.step(t); return fam.step(t, dt); });

  /* Runs queued jobs for SLICE_MS, then leaves the rest to the next frame. */
  function pump() {
    const t0 = performance.now();
    while (jobs.length && performance.now() - t0 < SLICE_MS) jobs.shift()();
    tally.ms += performance.now() - t0;
    raf = jobs.length ? requestAnimationFrame(pump) : 0;
  }
  /* Queues the build of chunk id in its steps; the last one keeps the Chunk, unlit and not yet on screen. */
  function build(id, stamp) {
    const { M, plan } = cur, st = B.steps(id, M, plan, opts.theme, opts.kit, opts.ink || ink);
    return st.map((f, i) => (i < st.length - 1 ? f : () => { built.set(id, { c: f(), stamp, night: M.night, fresh: true, quads: true, lit: null }); tally.rebuilt++; }));
  }
  /* Queues a bake for every chunk that is new or whose lamps changed (the hall takes its own lamps only: its bake is the longest task), then the hand-over. */
  function light() {
    const { M } = cur, lamps = [...built.values()].flatMap((b) => b.c.lamps || []);
    for (const [id, b] of built) {
      const L = id === HALL ? b.c.lamps : near(b.c, lamps), lit = b.c.bake ? JSON.stringify([M.night, L]) : "";
      if (!b.fresh && lit === b.lit) continue;
      jobs.push(() => {
        if (b.c.bake) b.c.bake(opts.theme.env[M.night ? "night" : "day"], L);
        if (b.fresh) mesh.set(id, b.c); else mesh.recolor(id, b.c.color);
        if (b.quads) fx.set(id, b.c.quads || []);
        b.fresh = b.quads = false; b.lit = lit; tally.relit++;
      });
    }
    jobs.push(done);
  }
  /* Hands actors, lamps and anchors to the scene parts and asks for one frame. */
  function done() {
    const { M, plan } = cur, lamps = [], lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
    actors = []; anchors.clear(); boards = [];
    for (const { c } of built.values()) {
      actors.push(...(c.actors || [])); lamps.push(...(c.lamps || []));
      for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], c.lo[i]); hi[i] = Math.max(hi[i], c.hi[i]); }
    }
    for (const a of actors) anchors.set(a.id, [a.x, a.y + (0.8 * a.scale) / 0.36, a.z]);
    for (const { c } of built.values()) for (const l of c.labels || []) { anchors.set(l.id ?? l.who, l.pos); if (l.quad) boards.push(l); (l.cap || []).forEach((q, i) => anchors.set(l.id + "/cap" + i, q)); }
    fam.set(actors); halo(lamps); fx.look(opts.theme, M.night);
    if (fit) S.view({ lo, hi, ...plan.home }); else { S.invalidate(); canvas.dispatchEvent(new Event("view")); }
    fit = false;
  }
  /* Queues what the patch asks: a chunk with a new stamp is rebuilt, one that only changed day or night is re-lit, the rest keep their buffers; an empty patch does nothing. */
  function apply(M, plan, patch = {}) {
    if (!B) { queued = [M, plan, patch]; return; }
    const ids = [HALL, ...Object.keys(plan.cells)], all = !cur || jobs.length > 0 || patch.layout || patch.night || cur.M.night !== M.night;
    tally = { rebuilt: 0, relit: 0, ms: 0 };
    if (!all && !(patch.rooms || []).length) return;
    fit = fit || !cur || !!patch.layout; cur = { M, plan }; jobs = [];
    for (const id of [...built.keys()]) if (!ids.includes(id)) { built.delete(id); mesh.drop(id); fx.drop(id); }
    for (const id of all ? ids : patch.rooms.filter((r) => ids.includes(r))) {
      const b = built.get(id), stamp = B.stamp ? B.stamp(id, M, plan) : null;
      if (!b || stamp === null || b.stamp !== stamp) jobs.push(...build(id, stamp));
      else if (b.night !== M.night) jobs.push(() => { if (b.c.relight(M, plan)) Object.assign(b, { night: M.night, quads: true, lit: null }); else jobs.unshift(...build(id, stamp)); });
    }
    jobs.push(light);
    if (raf) cancelAnimationFrame(raf);
    pump();
  }
  if (!B) import("../build/index.js").then((m) => { B = m; if (queued) apply(...queued); queued = null; });

  const R = {
    still: S.still,
    apply,
    /* Canvas pixels of the label point of a person or room; ok is false off screen or for an unknown id. */
    project(id) { const p = anchors.get(id); return p ? S.project(p) : { x: 0, y: 0, ok: false }; },
    /* The id under canvas pixel (x, y): a creature's body, else the name board it lies on, else the nearest creature or board within TAP_PX (a 44 px target). */
    pick(x, y) {
      let best = null, bd = 1e9, body = false;
      for (const a of actors) {
        const feet = S.project([a.x, a.y, a.z]), tip = S.project(anchors.get(a.id)), d = reach({ x, y }, feet, tip), own = Math.hypot(tip.x - feet.x, tip.y - feet.y) * 0.45;
        if (feet.ok && d < Math.max(TAP_PX, own) && d < bd) { bd = d; best = a.id; body = d < own; }
      }
      hot = null;
      if (body) return best;
      for (const l of boards) {
        const Q = l.quad.map(S.project);
        if (!Q.every((q) => q.ok)) continue;
        const d = inside({ x, y }, Q) ? 0 : Math.min(...Q.map((q, i) => reach({ x, y }, q, Q[(i + 1) % 4])));
        if (d < TAP_PX && d * 0.5 < bd) { bd = d * 0.5; hot = l; }
      }
      return hot ? hot.who || hot.id : best;
    },
    /* Lights the creature `id`, or the name board the last pick found for it, with a soft accent halo (null clears it) and draws one frame. */
    hover(id) {
      const b = id && ((hot && (hot.who || hot.id) === id && hot) || boards.find((l) => l.id === id)), a = id && !b && actors.find((x) => x.id === id), col = opts.theme.accent;
      lit(a ? [{ x: a.x, y: a.y + 0.3 * a.scale / 0.36, z: a.z, col, r: 0.7, halo: 0.9 }] : b ? [{ x: b.pos[0], y: b.pos[1], z: b.pos[2], col, r: b.r, halo: 0.6 }] : []);
      S.invalidate();
    },
    /* Pixels of creature id that the scene leaves on screen at the current view (seen) and that it covers with nothing else drawn (alone); for tests. */
    seen(id) {
      const own = fam.parts(id), kids = S.scene.children, was = kids.map((k) => k.visible), grab = S.grab();
      if (!own.length || !grab) return { seen: 0, alone: 0 };
      const diff = (a, b) => { let n = 0; for (let i = 0; i < a.length; i += 4) if (a[i] !== b[i] || a[i + 1] !== b[i + 1] || a[i + 2] !== b[i + 2]) n++; return n; };
      own.forEach((m) => (m.visible = false)); const without = S.grab();
      kids.forEach((k) => (k.visible = false)); const empty = S.grab();
      own.forEach((m) => (m.visible = true)); const alone = S.grab();
      kids.forEach((k, i) => (k.visible = was[i])); S.invalidate();
      return { seen: diff(grab, without), alone: diff(alone, empty) };
    },
    reset: S.reset,
    zoom: S.zoom,
    /* rebuilt, relit and ms count the last apply; pending is its jobs still queued. */
    stats: () => ({ chunks: mesh.size, rebuilt: tally.rebuilt, relit: tally.relit, pending: jobs.length, verts: mesh.verts(), ms: tally.ms, frames: S.stats.frames }),
  };
  made.set(canvas, R);
  return R;
}
