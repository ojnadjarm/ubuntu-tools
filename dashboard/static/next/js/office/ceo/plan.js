/* Where things stand in the Switchboard, the CEO's floor: the office on a stone platform at the back (patch wall, table, the owner's chair, the well), the workers' pit one step lower in front. */
export const ROOM = { w: 11, d: 9.8, h: 4.6 };
/* The platform's height and its straight front edge; the dais bulges past it round the table. */
export const STEP = 0.28, EDGE = 4.3, DAIS = 2.2;
export const TABLE = { x: 5.5, z: 3.4, r: 0.62, h: 0.42 };
export const WALL = { x: 5.5, w: 9.8, y0: 0.5, y1: 3.9, rows: 6 };
export const NOOK = { x: 1.6, z: 2.6 }, WELL = { x: 9.45, z: 2.6, r: 0.55 };
/* The pit's two arcs of desks round the table: radius, desks, angle between two desks. */
export const ROWS = [{ r: 3.2, n: 7, a: 0.29 }, { r: 4.3, n: 9, a: 0.215 }];
export const SLOTS = ROWS[0].n + ROWS[1].n;

/* Desk k of the pit, the first row and its middle first: its place and the turn that faces the table. */
export function desk(k) {
  const row = k < ROWS[0].n ? 0 : 1, { r, n, a } = ROWS[row], i = k - row * ROWS[0].n, th = (i % 2 ? 1 : -1) * Math.ceil(i / 2) * a;
  return { x: TABLE.x + r * Math.sin(th), z: TABLE.z + r * Math.cos(th), r: th + Math.PI, row, n };
}

/* Plan for the CEO floor's view M: the room, the office and pit cells, the camera's home view (a tall stage looks nearly square at the patch wall, whose plates stay in the fitted box). */
export function plan(M) {
  const pool = M.rooms.find((r) => r.kind === "pool"), cells = { [M.ceo.id]: { x: 0, y: STEP, z: 0, w: ROOM.w, d: EDGE, slots: 1 } };
  if (pool) cells[pool.id] = { x: 0, y: 0, z: 0, w: ROOM.w, d: ROOM.d - EDGE, slots: SLOTS };
  return { shell: "ceo", hall: { ...ROOM, shell: "ceo" }, cells, home: { az: 0.42, el: 0.55, azTall: 0.32, top: WALL.y1 + STEP, shrink: 0.8 } };
}
