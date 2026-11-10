/* Where things stand in the loft: seat rooms as bays in rows of COLS, the staff teams' rows in front, the CEO on the mezzanine, the desk pool by the stairs under it. */
import { SLOTS } from "./model.js";

export const RW = 3.6, RD = 3.5, COLS = 4, MW = 4.0, MD = 3.2, GAP = 1.1, H = 2.5, AISLE = 0.6;
const X0 = MW + GAP, IW = RW - 0.35, ID = RD - 0.2;

/* Plan for model M: the hall's size, one cell per room (centre, usable size, worker desks), the camera's home view. */
export function plan(M) {
  const seatRooms = M.rooms.filter((r) => r.kind !== "pool"), pool = M.rooms.find((r) => r.kind === "pool");
  const rows = Math.max(2, Math.ceil(seatRooms.length / COLS)), all = rows + Math.ceil(M.staff.length / COLS);
  const depth = all * RD + (all - 1) * AISLE + 0.7;
  const at = (i) => ({ x: X0 + (i % COLS) * RW + RW / 2, z: Math.floor(i / COLS) * (RD + AISLE) + RD / 2 + 0.1, w: IW, d: ID, slots: SLOTS });
  const cells = {};
  seatRooms.forEach((r, i) => (cells[r.id] = at(i)));
  M.staff.forEach((r, k) => (cells[r.id] = at(rows * COLS + k)));
  if (M.ceo) cells[M.ceo.id] = { x: MW / 2, z: MD / 2, w: MW, d: MD, slots: 0 };
  if (pool) cells[pool.id] = { x: MW / 2, z: MD + 0.3 + RD / 2, w: MW - 0.4, d: ID, slots: SLOTS };
  return { hall: { w: X0 + COLS * RW, d: depth, h: H }, cells, home: { az: 0.5, el: 0.6, azTall: 1.2, top: 1.5, shrink: 0.8 } };
}
