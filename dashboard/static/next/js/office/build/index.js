/* Plan → chunks: the hall or one room built on its own batch in short steps, lit by the lamps the caller hands to bake; a day-night flip re-reads lamps and glows without geometry. */
import { batch } from "./batch.js";
import { hall, DECK } from "./hall.js";
import { seatRoom, teamRoom, ceoSpot, pool } from "./room.js";

export const HALL = "hall";
const ROOMS = { seat: seatRoom, team: teamRoom, ceo: ceoSpot, pool };
const room = (M, id) => [M.ceo, ...M.rooms, ...M.staff].find((r) => r && r.id === id);
const envOf = (theme, M) => theme.env[M.night ? "night" : "day"];

/* Everything but day or night that decides the geometry of chunk `id`: an equal stamp keeps the buffers. */
export function stamp(id, M, plan) {
  if (id === HALL) return JSON.stringify([plan.hall, M.rooms.filter((r) => r.kind !== "pool").length, M.staff.length]);
  return JSON.stringify([JSON.parse(room(M, id).key).slice(0, -1), plan.cells[id]]);
}

/* Runs the builders of chunk `id`; dry keeps lamps, glows, quads, actors and labels and makes no geometry. Every glow call and every unlit glow material gets its own index, so a dry run lines up with the built one. */
function run(id, M, plan, theme, kit, ink, dry) {
  const B = batch(kit, theme.pal), model = B.model;
  if (dry) B.cells = B.box = B.cyl = B.ring = B.foot = () => {};
  const ctx = { B, M, plan, th: theme, night: M.night, ink, actors: [], lamps: [], glows: [null], glowIx: new Proxy({}, { get: () => undefined }), labels: [], quads: [] };
  B.model = (name, o = {}) => { for (const k in o.glow) o.glow[k] ||= ctx.glows.push(null) - 1; return dry ? kit.models[name].s : model(name, o); };
  if (id === HALL) hall(ctx, plan);
  else {
    const R = room(M, id), c = plan.cells[id], up = R.kind === "ceo";
    B.push({ x: c.x, y: up ? DECK : 0, z: c.z + (up ? 0.25 : 0) });
    ROOMS[R.kind](ctx, R);
    B.pop();
  }
  return ctx;
}

/* The build of chunk `id` as two short tasks: the builders, then the frozen buffers; the second returns the Chunk, unlit until bake(env, lamps). */
export function steps(id, M, plan, theme, kit, ink) {
  const lit = (v) => theme.minLight + (1 - theme.minLight) * v, take = (c, ctx) => Object.assign(c, { lamps: ctx.lamps, quads: ctx.quads, actors: ctx.actors, labels: ctx.labels, glows: ctx.glows });
  let ctx;
  return [
    () => { ctx = run(id, M, plan, theme, kit, ink); },
    () => {
      const g = ctx.B.finish();
      const c = take({
        id, position: g.position, color: g.color, index: g.index, lo: g.lo, hi: g.hi,
        /* Lights the colour buffer and the chunk's creatures with the given lamps. */
        bake(e, lamps) { g.bake(e, lamps, c.glows); for (const a of c.actors) a.light = c.lightAt(e, lamps, a.x, a.y + 0.3, a.z); return g.color; },
        lightAt: (e, lamps, x, y, z) => g.lightAt(e, lamps, x, y, z).map(lit),
        /* Takes model m's lamps, glows, quads and creatures and keeps the geometry; false when m needs other geometry. */
        relight(m, p) { const d = run(id, m, p, theme, kit, ink, true); return d.glows.length === c.glows.length && !!take(c, d); },
      }, ctx);
      return c;
    },
  ];
}

/* The chunk `id` (HALL or a room id) of model M laid out by plan, lit by its own lamps; ink(text) rasterises sign text. */
export function chunk(id, M, plan, theme, kit, ink) {
  const [gen, freeze] = steps(id, M, plan, theme, kit, ink);
  gen();
  const c = freeze();
  c.bake(envOf(theme, M), c.lamps);
  return c;
}
