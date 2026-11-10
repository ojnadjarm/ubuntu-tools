/* Plan → chunks: the hall or one room built on its own batch, lit by its own lamps; the renderer re-lights a chunk with bake(env, lamps). */
import { batch } from "./batch.js";
import { hall, DECK } from "./hall.js";
import { seatRoom, teamRoom, ceoSpot, pool } from "./room.js";

export const HALL = "hall";
const ROOMS = { seat: seatRoom, team: teamRoom, ceo: ceoSpot, pool };

/* The chunk `id` (HALL or a room id) of model M laid out by plan; ink(text) rasterises sign text. */
export function chunk(id, M, plan, theme, kit, ink) {
  const ctx = { B: batch(kit, theme.pal), M, plan, th: theme, night: M.night, ink, actors: [], lamps: [], glows: [null], glowIx: {}, labels: [], quads: [] };
  if (id === HALL) hall(ctx, plan);
  else {
    const R = [M.ceo, ...M.rooms, ...M.staff].find((r) => r && r.id === id), c = plan.cells[id], up = R.kind === "ceo";
    ctx.B.push({ x: c.x, y: up ? DECK : 0, z: c.z + (up ? 0.25 : 0) });
    ROOMS[R.kind](ctx, R);
    ctx.B.pop();
  }
  const g = ctx.B.finish(), env = theme.env[M.night ? "night" : "day"], lit = (v) => theme.minLight + (1 - theme.minLight) * v;
  g.bake(env, ctx.lamps, ctx.glows);
  for (const a of ctx.actors) a.light = g.lightAt(env, ctx.lamps, a.x, a.y + 0.3, a.z).map(lit);
  return {
    id, position: g.position, color: g.color, index: g.index, lamps: ctx.lamps, quads: ctx.quads, actors: ctx.actors, labels: ctx.labels, lo: g.lo, hi: g.hi,
    bake: (e, lamps) => g.bake(e, lamps, ctx.glows),
    lightAt: (e, lamps, x, y, z) => g.lightAt(e, lamps, x, y, z).map(lit),
  };
}
