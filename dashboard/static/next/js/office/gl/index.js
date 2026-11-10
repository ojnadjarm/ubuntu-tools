/* The renderer the office screen talks to: chunks, creatures, light surfaces and halos on one stage; the still renderer is the same object. */
import { stage } from "./stage.js";
import { chunks } from "./chunks.js";
import { creatures } from "./creatures.js";
import { effects } from "./fx.js";
import { halos } from "./halos.js";

const HALL = "hall", made = new WeakMap(), inks = new Map();

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

/* createRenderer(canvas, {theme, kit, still?, chunk?, ink?}) → Renderer; one per canvas, a second call returns the first. chunk defaults to build/index.js. */
export function createRenderer(canvas, opts) {
  if (made.has(canvas)) return made.get(canvas);
  const S = stage(canvas, { still: opts.still }), mesh = chunks(S), fam = creatures(S.scene), fx = effects(S.scene), halo = halos(S), built = new Map(), anchors = new Map();
  let make = opts.chunk, actors = [], layout = true, night = null, queued = null, last = { rebuilt: 0, ms: 0 };
  S.ticker((t, dt) => { fx.step(t); return fam.step(t, dt); });

  /* Rebuilds the chunks the patch names, then hands actors, lamps and anchors to the scene parts. */
  function apply(M, plan, patch = {}) {
    if (!make) { queued = [M, plan, patch]; return; }
    const t0 = performance.now(), ids = [HALL, ...Object.keys(plan.cells)], all = layout || patch.layout || patch.night || night !== !!M.night;
    const todo = ids.filter((id) => all || !built.has(id) || (patch.rooms || []).includes(id));
    for (const id of [...built.keys()]) if (!ids.includes(id)) { built.delete(id); mesh.drop(id); fx.drop(id); todo.dirty = true; }
    for (const id of todo) { const c = make(id, M, plan, opts.theme, opts.kit, opts.ink || ink); built.set(id, c); mesh.set(id, c); fx.set(id, c.quads || []); }
    last = { rebuilt: todo.length, ms: performance.now() - t0 };
    if (!todo.length && !todo.dirty) return;
    const lamps = [], lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
    actors = []; anchors.clear();
    for (const c of built.values()) {
      actors.push(...(c.actors || [])); lamps.push(...(c.lamps || []));
      for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], c.lo[i]); hi[i] = Math.max(hi[i], c.hi[i]); }
    }
    for (const a of actors) anchors.set(a.id, [a.x, a.y + (0.8 * a.scale) / 0.36, a.z]);
    for (const c of built.values()) for (const l of c.labels || []) anchors.set(l.id ?? l.who, l.pos);
    fam.set(actors); halo(lamps); fx.look(opts.theme, M.night);
    if (all) S.view({ lo, hi, ...plan.home }); else S.invalidate();
    layout = false; night = !!M.night; last.ms = performance.now() - t0;
  }
  if (!make) import("../build/index.js").then((m) => { make = m.chunk; if (queued) apply(...queued); queued = null; });

  const R = {
    still: S.still,
    apply,
    /* Canvas pixels of the label point of a person or room; ok is false off screen or for an unknown id. */
    project(id) { const p = anchors.get(id); return p ? S.project(p) : { x: 0, y: 0, ok: false }; },
    /* The id of the creature under canvas pixel (x, y), nearest first. */
    pick(x, y) {
      let best = null, bd = 1e9;
      for (const a of actors) {
        const feet = S.project([a.x, a.y, a.z]), tip = S.project(anchors.get(a.id)), d = reach({ x, y }, feet, tip);
        if (feet.ok && d < Math.max(16, Math.hypot(tip.x - feet.x, tip.y - feet.y) * 0.45) && d < bd) { bd = d; best = a.id; }
      }
      return best;
    },
    reset: S.reset,
    zoom: S.zoom,
    stats: () => ({ chunks: mesh.size, rebuilt: last.rebuilt, verts: mesh.verts(), ms: last.ms, frames: S.stats.frames }),
  };
  made.set(canvas, R);
  return R;
}
