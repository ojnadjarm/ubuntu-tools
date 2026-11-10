/* Where things stand in the loft: seat rooms as bays in rows of COLS, the staff teams' rows in front, the CEO on the mezzanine, the desk pool by the stairs under it. */
import { SLOTS } from "./model.js";

export const IW = 3.25, ID = 3.3, COLS = 4, MW = 4.0, MD = 3.2, GAP = 1.4, H = 2.5;
export const X0 = MW + GAP, PX = IW + GAP, PZ = ID + GAP;

/* The centre of bay i: bays stand GAP apart in rows of COLS, the first one GAP from the mezzanine. */
export const bay = (i) => ({ x: X0 + (i % COLS) * PX + IW / 2, z: 0.2 + Math.floor(i / COLS) * PZ + ID / 2 });

/* Plan for model M: the hall's size, one cell per room (centre, usable size, worker desks), the camera's home view. */
export function plan(M) {
  const seatRooms = M.rooms.filter((r) => r.kind !== "pool"), pool = M.rooms.find((r) => r.kind === "pool");
  const rows = Math.max(2, Math.ceil(seatRooms.length / COLS)), all = rows + Math.ceil(M.staff.length / COLS);
  const depth = 0.2 + all * PZ - GAP + 0.7;
  const at = (i) => ({ ...bay(i), w: IW, d: ID, slots: SLOTS });
  const cells = {};
  seatRooms.forEach((r, i) => (cells[r.id] = at(i)));
  M.staff.forEach((r, k) => (cells[r.id] = at(rows * COLS + k)));
  if (M.ceo) cells[M.ceo.id] = { x: MW / 2, z: MD / 2, w: MW, d: MD, slots: 0 };
  if (pool) cells[pool.id] = { x: MW / 2, z: MD + GAP + ID / 2, w: MW - 0.4, d: ID, slots: SLOTS };
  return { hall: { w: X0 + COLS * PX - GAP + 0.175, d: depth, h: H }, cells, home: { az: 0.3, el: 0.6, azTall: 1.2, top: 1.5, shrink: 0.83 } };
}
