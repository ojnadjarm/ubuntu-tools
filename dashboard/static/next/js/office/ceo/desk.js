/* The Switchboard's live data, pure: the tickets running in the building, the patch wall's columns, the sheets on the table, the owner's lamp and the well's capsule events. */
import { floors, home, MAIN } from "../floors.js";

const STATE = { working: "working", error: "failing" };
const ms = (t) => (typeof t === "number" || /^\d+$/.test(t) ? t * 1000 : Date.parse(t)) || 0;

/* One ticket per worker or sub-agent in the rooms, oldest first: {id, name, floor, state: working|waiting|failing, since}; bad is a failed sub-agent row no room holds, on floor bad.floor. */
export function tickets(rooms, bad) {
  const out = rooms.flatMap((r) => r.people.filter((p) => p.kind === "agent" || p.kind === "worker")
    .map((p) => ({ id: p.id, name: p.name, floor: r.floor, state: STATE[p.pose] || "waiting", since: p.since })));
  if (bad && !out.some((t) => t.id === bad.id)) out.push({ id: bad.id, name: bad.label.split(" ")[0], floor: bad.floor, state: "failing", since: bad.started });
  return out.sort((a, b) => ms(a.since) - ms(b.since) || (a.id < b.id ? -1 : 1));
}

/* The desk of payload P: its floors top floor first ({id, name, n}), the CEO's floor and the tickets; null while the CEO has no floor line of its own (the one-hall office has no patch wall). */
export function desk(P, rooms, bad) {
  const F = floors(P);
  if (home(P) === MAIN) return null;
  return { home: home(P), floors: F.map((f, i) => ({ ...f, n: i + 1 })).reverse(), tickets: tickets(rooms, bad && { ...bad, floor: home(P) }) };
}

/* The patch wall: one column per floor, top floor first, each with the tickets plugged into it. */
export const columns = (D) => D.floors.map((f) => ({ ...f, jacks: D.tickets.filter((t) => t.floor === f.id) }));

/* The briefs on the table, the newest last (on top), at most max. */
export const sheets = (D, max = 12) => D.tickets.slice(-max);

/* True while something waits on the owner: his reading lamp is on. */
export const lampOn = (live) => !!live && live.lamp === "needs";

/* The capsule moves from desk a to desk b: "out" for a ticket that starts running, "back" for one that stops (done or failed). */
export function events(a, b) {
  if (!a || !b) return [];
  const run = (D) => new Map(D.tickets.filter((t) => t.state !== "failing").map((t) => [t.id, t])), was = run(a), now = run(b), seen = new Set(a.tickets.map((t) => t.id));
  return [...[...now.values()].filter((t) => !seen.has(t.id)).map((t) => ({ id: t.id, dir: "out", floor: t.floor })),
    ...[...was.values()].filter((t) => !now.has(t.id)).map((t) => ({ id: t.id, dir: "back", floor: t.floor }))];
}

/* True when the agents read A lists a working agent the office read P lacks, or one whose state moved since: the office is behind. */
export function behind(P, A) {
  if (!P || !A) return false;
  const was = new Map(((P.agents || {}).subagents || []).map((s) => [s.id, s.state]));
  for (const s of P.sessions || []) if (s.pid) was.set("pid" + s.pid, null);
  return (A.subagents || []).some((s) => (was.has(s.id) ? was.get(s.id) !== null && was.get(s.id) !== s.state : s.state === "working"));
}

/* The patch entry for the capsule moves between two models: {events} when a ticket started or stopped, else nothing. */
export function moves(a, b) {
  const ev = a && a.ceo && b.ceo ? events(a.ceo.desk, b.ceo.desk) : [];
  return ev.length ? { events: ev } : {};
}
