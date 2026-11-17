/* Where things stand in the Switchboard, the CEO's floor: the office on a stone platform at the back (patch wall, table, the owner's chair, the well), the workers' pit one step lower in front. */
export const ROOM = { w: 9.2, d: 7.4, h: 2.9 };
/* The platform's height and its straight front edge; the dais bulges past it round the table. */
export const STEP = 0.16, EDGE = 3.3, DAIS = 1.9;
export const TABLE = { x: 4.6, z: 2.75, r: 0.62, h: 0.42 };
export const WALL = { x: 4.6, w: 5.2, y0: 0.46, y1: 2.66, rows: 6 };
export const NOOK = { x: 1.3, z: 2.1 }, WELL = { x: 7.95, z: 2.1, r: 0.55 };
/* The pit's two arcs of desks round the table: radius, desks, angle between two desks. */
export const ROWS = [{ r: 2.8, n: 7, a: 0.29 }, { r: 3.75, n: 9, a: 0.215 }];
export const SLOTS = ROWS[0].n + ROWS[1].n;

/* Desk k of the pit, the first row and its middle first: its place and the turn that faces the table. */
export function desk(k) {
  const row = k < ROWS[0].n ? 0 : 1, { r, n, a } = ROWS[row], i = k - row * ROWS[0].n, th = (i % 2 ? 1 : -1) * Math.ceil(i / 2) * a;
  return { x: TABLE.x + r * Math.sin(th), z: TABLE.z + r * Math.cos(th), r: th + Math.PI, row, n };
}

/* Plan for the CEO floor's view M: the room, the office and pit cells, the camera's home view. */
export function plan(M) {
  const pool = M.rooms.find((r) => r.kind === "pool"), cells = { [M.ceo.id]: { x: 0, y: STEP, z: 0, w: ROOM.w, d: EDGE, slots: 1 } };
  if (pool) cells[pool.id] = { x: 0, y: 0, z: 0, w: ROOM.w, d: ROOM.d - EDGE, slots: SLOTS };
  return { shell: "ceo", hall: { ...ROOM, shell: "ceo" }, cells, home: { az: 0.42, el: 0.62, azTall: 0.5, top: 1.2, shrink: 0.8 } };
}
