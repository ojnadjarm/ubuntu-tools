/* Floors of the office as data: /api/office `floors` lines, bottom floor first, name the teams on each floor (an org.json head seat with its tree, or a staff.json team); the CEO's floor is the line naming the CEO seat, else an implicit main floor. */
export const MAIN = "main";

const lines = (P) => (P && P.floors) || [];
const ceoOf = (P) => ((P && P.seats) || []).find((s) => s.role === "ceo");

/* The id of the CEO's floor: the line that names the CEO seat, else the main floor. */
export function home(P) {
  const c = ceoOf(P), f = c && lines(P).find((l) => l.teams.includes(c.id));
  return f ? f.id : MAIN;
}

/* The floors of payload P, bottom floor first: [{id, name}]; the main floor comes first only when no line holds the CEO. */
export const floors = (P) => {
  const L = lines(P).map((f) => ({ id: f.id, name: f.name }));
  return home(P) === MAIN ? [{ id: MAIN, name: "Main" }, ...L] : L;
};

/* Floor id as shown: id when payload P has it, else the CEO's floor. */
export const pick = (P, id) => (floors(P).some((f) => f.id === id) ? id : home(P));

/* The ids of the floors whose line says `"deck": false`: no raised office there. */
export const flat = (P) => lines(P).filter((f) => f.deck === false).map((f) => f.id);

/* placer(P) → {seat(id), team(id), starter(by), head(id), home}: the floor of a seat (its own line or its nearest parent's below the CEO, else the line with `rest` "po"), of a staff team (its line, else the `rest` "team" line), of a worker by who started it (a staff member's id, alone or before "-…"), whether a seat heads its floor, the CEO's floor; whatever no line places stands on the CEO's floor. */
export function placer(P) {
  const at = new Map(lines(P).flatMap((f) => f.teams.map((t) => [t, f.id]))), heads = new Set(lines(P).map((f) => f.head));
  const byId = Object.fromEntries(((P && P.seats) || []).map((s) => [s.id, s])), base = home(P);
  const rest = (k) => (lines(P).find((f) => (f.rest || []).includes(k)) || { id: base }).id;
  const team = (id) => at.get(id) || rest("team");
  const crew = new Map(((P && P.staff) || []).flatMap((t) => (t.members || []).map((m) => [m.id, team(t.id)])));
  const seat = (id) => {
    for (let s = byId[id]; s && (s.id === id || s.role !== "ceo"); s = byId[s.parent]) if (at.has(s.id)) return at.get(s.id);
    return byId[id] && byId[id].role === "ceo" ? base : rest("po");
  };
  const starter = (by) => { if (by) for (const [m, f] of crew) if (by === m || by.startsWith(m + "-")) return f; return base; };
  return { seat, team, starter, head: (id) => heads.has(id), home: base };
}

/* The model as floor f of payload P shows it: that floor's rooms and teams, `deck` false when its line says so; the raised office holds the CEO on its floor, the floor's head (as kind "head", out of the bays) elsewhere, else nobody; a floor with no deck has none. The CEO's own line, holding him and the desk pool only, is the Switchboard (`shell` "ceo"), not the loft. */
export function view(M, f, P) {
  const deck = !flat(P).includes(f), here = M.rooms.filter((r) => r.floor === f), head = deck && here.find((r) => r.head), top = deck && M.ceo && M.ceo.floor === f;
  const staff = M.staff.filter((r) => r.floor === f), own = top && !!M.ceo.desk && !staff.length && here.every((r) => r.kind === "pool");
  return { ...M, floor: f, deck, ceo: top ? M.ceo : head ? { ...head, kind: "head" } : null, rooms: here.filter((r) => top || r !== head), staff, ...(own ? { shell: "ceo" } : {}) };
}

/* People working on each floor: {floor id: n}. */
export function working(M, list) {
  const n = Object.fromEntries(list.map((f) => [f.id, 0]));
  for (const r of [M.ceo, ...M.rooms, ...M.staff]) if (r && r.floor in n) n[r.floor] += r.people.filter((p) => p.pose === "working").length;
  return n;
}
