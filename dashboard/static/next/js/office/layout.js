/* Where things stand in the loft: seat rooms as bays in rows of COLS, the staff teams' rows in front, the CEO on the mezzanine, the desk pool by the stairs under it; a floor with no deck (M.deck false) has no mezzanine column: the bays start at the left wall and the pool takes a bay. */
import { SLOTS } from "./model.js";

export const IW = 3.25, ID = 3.3, COLS = 4, MW = 4.0, MD = 3.2, GAP = 1.4, H = 2.5;
export const X0 = MW + GAP, PX = IW + GAP, PZ = ID + GAP;

/* The left edge of the first bay column: GAP past the mezzanine, or half a GAP from the wall with no deck. */
export const x0Of = (M) => (M.deck === false ? GAP / 2 : X0);

/* The centre of bay i: bays stand GAP apart in rows of COLS, the first column at x0. */
export const bay = (i, x0 = X0) => ({ x: x0 + (i % COLS) * PX + IW / 2, z: 0.2 + Math.floor(i / COLS) * PZ + ID / 2 });

/* Seat-room bays of model M (one floor's view): its seat rooms, the desk pool among them with no deck. */
export const baysOf = (M) => M.rooms.filter((r) => M.deck === false || r.kind !== "pool").length;

/* Rows of seat bays and all bay rows of model M: seat rooms first, staff teams on rows of their own, two rows at least. */
export function rowsOf(M) {
  const rows = Math.max(1, Math.ceil(baysOf(M) / COLS));
  return { rows, all: Math.max(2, rows + Math.ceil(M.staff.length / COLS)) };
}

/* Plan for model M: the hall's size, one cell per room (centre, usable size, worker desks), the camera's home view. */
export function plan(M) {
  const deck = M.deck !== false, seatRooms = M.rooms.filter((r) => !deck || r.kind !== "pool"), pool = deck && M.rooms.find((r) => r.kind === "pool");
  const { rows, all } = rowsOf(M), x0 = x0Of(M);
  const depth = 0.2 + all * PZ - GAP + 0.7;
  const at = (i) => ({ ...bay(i, x0), w: IW, d: ID, slots: SLOTS });
  const cells = {};
  seatRooms.forEach((r, i) => (cells[r.id] = at(i)));
  M.staff.forEach((r, k) => (cells[r.id] = at(rows * COLS + k)));
  if (M.ceo) cells[M.ceo.id] = { x: MW / 2, z: MD / 2, w: MW, d: MD, slots: 0 };
  if (pool) cells[pool.id] = { x: MW / 2, z: MD + GAP + ID / 2, w: MW - 0.4, d: ID, slots: SLOTS };
  return { hall: { w: x0 + COLS * PX - GAP + 0.175, d: depth, h: H, x0 }, cells, home: { az: 0.3, el: 0.6, azTall: 1.2, top: 1.5, shrink: 0.83 } };
}
