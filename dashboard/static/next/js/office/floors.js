/* Floors of the office as data: /api/office `floors` lines name the teams on each floor (an org.json head seat with its tree, or a staff.json team); everything else stands on the main floor. */
export const MAIN = "main";

/* The floors of payload P, the main floor first: [{id, name}]. */
export const floors = (P) => [{ id: MAIN, name: "Main" }, ...((P && P.floors) || []).map((f) => ({ id: f.id, name: f.name }))];

/* placer(P) → {seat(id), team(id), starter(by), head(id)}: the floor of a seat (its own line or its nearest parent's), of a staff team, of a worker by who started it (a staff member's id, alone or before "-…"), and whether a seat heads its floor (the line's `head`). */
export function placer(P) {
  const at = new Map(((P && P.floors) || []).flatMap((f) => f.teams.map((t) => [t, f.id]))), heads = new Set(((P && P.floors) || []).map((f) => f.head));
  const byId = Object.fromEntries(((P && P.seats) || []).map((s) => [s.id, s]));
  const crew = new Map(((P && P.staff) || []).flatMap((t) => (t.members || []).map((m) => [m.id, at.get(t.id) || MAIN])));
  const seat = (id) => { for (let s = byId[id]; s; s = byId[s.parent]) if (at.has(s.id)) return at.get(s.id); return MAIN; };
  const starter = (by) => { if (!by) return MAIN; for (const [m, f] of crew) if (by === m || by.startsWith(m + "-")) return f; return MAIN; };
  return { seat, team: (id) => at.get(id) || MAIN, starter, head: (id) => heads.has(id) };
}

/* The model as one floor shows it: that floor's rooms and teams; the raised office holds the CEO on the main floor, the floor's head (as kind "head", out of the bays) elsewhere, else nobody. */
export function view(M, f) {
  const here = M.rooms.filter((r) => r.floor === f), head = f !== MAIN && here.find((r) => r.head);
  return { ...M, floor: f, ceo: f === MAIN ? M.ceo : head ? { ...head, kind: "head" } : null, rooms: here.filter((r) => r !== head), staff: M.staff.filter((r) => r.floor === f) };
}

/* People working on each floor: {floor id: n}. */
export function working(M, list) {
  const n = Object.fromEntries(list.map((f) => [f.id, 0]));
  for (const r of [M.ceo, ...M.rooms, ...M.staff]) if (r && r.floor in n) n[r.floor] += r.people.filter((p) => p.pose === "working").length;
  return n;
}
