/* Office model: one /api/office payload becomes the CEO, a room per seat in team order, the desk pool, the staff teams, the boards' rows; diff names what changed. */
import { seatState, titled } from "../seats.js";
import { claimRow } from "../claims.js";
import { store } from "../store.js";
import { verdict } from "../verdict.js";

export const SLOTS = 6;
const SESSION = { working: "working", idle: "idle" };
const AGENT = { working: "working", error: "error" };
const STATE = { working: "working", talking: "talking", error: "error", idle: "idle", sleep: "asleep" };
const FAIL_MS = 10 * 60e3;

/* A label's ticket ("T1601-04"), else its first word. */
export const ticket = (l) => (/^[A-Za-z]{1,3}\d+[\w-]*(\s+[A-Za-z]{1,3}\d+\b)?/.exec(l) || [l.split(" ")[0]])[0];
/* A label without its ticket. */
export const rest = (l) => l.slice(ticket(l).length).trim();

const pidOf = (a) => a.pid ?? (/^pid(\d+)$/.exec(a.id) || [])[1] * 1;
/* An epoch in seconds or a date string as ms. */
const ms = (t) => (typeof t === "number" || /^\d+$/.test(t) ? t * 1000 : Date.parse(t));
const workingFirst = (L) => [...L.filter((p) => p.pose === "working"), ...L.filter((p) => p.pose !== "working")];

/* A room around its people: busy counts the working, awake is anyone not asleep; a lead's pose is the room's; status is its section's {id, label, since?, note?}, null while active. */
function room(kind, id, name, rank, area, team, people, lead, status = null) {
  const busy = people.filter((p) => p.pose === "working" || p.pose === "talking").length, awake = people.some((p) => p.pose !== "sleep");
  const pose = lead ? lead.pose : busy ? "working" : people.some((p) => p.pose === "error") ? "error" : awake ? "idle" : "sleep";
  return { id, kind, name, rank, area, team, pose, state: lead ? lead.state : STATE[pose], busy, awake, people, more: Math.max(0, people.length - (lead ? 1 : 0) - SLOTS), status, key: "" };
}

/* A seat's pose: working, error when its runner is bad, a protected seat's from its session's state only, idle, else asleep. */
function seatPose(seat, state, mine) {
  if (state === "working") return "working";
  if (seat.runner && seat.runner.health === "bad") return "error";
  if (state === "yours") return mine.find((s) => !("pid" in s)).state === "working" ? "working" : "idle";
  return state === "idle" ? "idle" : "sleep";
}

/* A member of a staff team: running is working, a bad health is an error, anything else sleeps. */
const staffPose = (m) => (m.state === "running" ? "working" : m.health === "bad" ? "error" : "sleep");

/* build(P, {now, needs, talk}) → Model; needs (the CEO's lamp) defaults to the status verdict in the store; talk(id) is true while a seat says something. */
export function build(P, { now = Date.now(), needs = verdict(store.D).bad, talk = () => false } = {}) {
  const S = P.sessions || [], A = P.agents || {}, seats = (P.seats || []).filter((s) => s.role !== "owner"), subs = A.subagents || [];
  const who = {}, put = (p) => (who[p.id] = p), byId = Object.fromEntries(seats.map((s) => [s.id, s]));
  const top = seats.find((s) => s.role === "ceo"), under = (id) => seats.filter((s) => s.parent === id);
  const byPid = new Map(subs.filter((a) => pidOf(a)).map((a) => [pidOf(a), a])), placed = new Set();

  const agent = (a, roomId, session) => put({ id: a.id, kind: "agent", name: ticket(a.label), rank: a.type || "Agent", role: "worker", pose: AGENT[a.state] || "sleep",
    state: a.state, since: a.started, room: roomId, raw: session ? { ...a, session } : a });
  /* A session a seat started: a worker, or the sub-agent row with the same pid as one person. */
  const worker = (s, roomId) => {
    const a = byPid.get(s.pid);
    if (a) { placed.add(a.id); return agent(a, roomId, s); }
    return put({ id: "pid" + s.pid, kind: "worker", name: s.name || "pid " + s.pid, rank: s.rank || "Worker", role: "worker", pose: SESSION[s.state] || "sleep",
      state: s.state, since: s.since, room: roomId, raw: { ...s, boss: byId[s.parent] ? byId[s.parent].name : s.parent } });
  };
  /* The lead of a seat's room (talking while it says something, available while only its live workers run) and the workers at its desks: one crew list for the card and the scene. */
  const seatRoom = (seat, team, kind) => {
    const mine = S.filter((s) => s.seat === seat.id), state = seatState(seat, S), prot = mine.find((s) => !("pid" in s));
    const crew = kind === "seat" ? workingFirst(S.filter((s) => !s.seat && s.parent === seat.id).map((s) => worker(s, seat.id))) : [];
    const busy = crew.filter((p) => p.pose === "working"), free = crew.length > 0 && !mine.length, pose = seatPose(seat, state, mine);
    const lead = put({ id: seat.id, kind, name: seat.name, rank: seat.rank || "", role: seat.role, pose: talk(seat.id) ? "talking" : free && pose === "sleep" ? "idle" : pose,
      state: free ? "available" : state, since: (prot || mine[0] || {}).since, room: seat.id,
      raw: { ...seat, session: prot ? { seat: prot.seat, state: prot.state, since: prot.since } : mine[0],
        crew: { n: crew.length, on: busy.length, list: crew.map((p) => ({ id: p.id, name: p.name, since: p.since })) } } });
    return room(kind, seat.id, seat.name, seat.rank || "", seat.area || "", team, [lead, ...crew], lead, seat.status || null);
  };

  const heads = top ? under(top.id) : [], down = (id, t) => under(id).flatMap((s) => [seatRoom(s, t, "seat"), ...down(s.id, t)]);
  const ceo = top ? seatRoom(top, -1, "ceo") : null;
  const rooms = heads.flatMap((h, t) => [seatRoom(h, t, "seat"), ...down(h.id, t)]);
  const loose = S.filter((s) => !s.seat && !(s.parent in byId && s.parent !== (top && top.id)));
  const poolPeople = workingFirst([...loose.map((s) => worker(s, "pool")), ...subs.filter((a) => a.state === "working" && !placed.has(a.id) && !who[a.id]).map((a) => agent(a, "pool"))]);
  const pool = room("pool", "pool", "Desk pool", "Agents", "", -1, poolPeople);
  rooms.push(pool);
  const live = subs.filter((a) => a.state === "working"), bad = subs.find((a) => a.state === "error" && now - ms(a.last) < FAIL_MS);
  if (ceo) {
    const c = ceo.people[0];
    c.raw.crew = { n: poolPeople.length, on: live.length };
    if (bad) { Object.assign(c, { pose: "error", state: "error" }); Object.assign(ceo, { pose: "error", state: "error", awake: true }); c.raw.failing = { ticket: ticket(bad.label), last: bad.last }; }
    ceo.live = { motes: live.map((a) => a.id), lamp: needs ? "needs" : "ok", failing: bad ? bad.id : null };
  }

  const staff = (P.staff || []).map((t, k) => {
    const id = "team-" + t.id, members = (t.members || []).map((m) => put({ id: m.id, kind: "staff", name: m.name, rank: m.rank, role: "crew", pose: staffPose(m),
      on: !!m.on, state: m.state, since: (m.last || {}).end, room: id, raw: { ...m, team: t.name } }));
    return room("team", id, t.name, "Team", t.name, heads.length + k, members, null, t.status || null);
  });
  [pool, ...staff].forEach((r) => (who[r.id] = r));

  const all = [ceo, ...rooms, ...staff].filter(Boolean), night = !all.some((r) => r.awake);
  all.forEach((r) => (r.key = JSON.stringify([r.kind, r.name, r.area, r.team, r.people.map((p) => [p.id, p.pose, !!p.on]), r.busy, r.awake, r.more, r.live || 0, ...(r.status ? [r.status] : []), night])));

  const members = staff.flatMap((r) => r.people.map((p) => p.raw)), on = members.filter((m) => m.on);
  const next = on.filter((m) => m.next).sort((a, b) => Date.parse(a.next) - Date.parse(b.next));
  const names = Object.fromEntries(seats.map((s) => [s.id, titled(s)]));
  const panels = {
    next: next.map((m) => ({ id: m.id, name: m.name, next: m.next, last: (m.last || {}).end || "", bad: m.health === "bad" })),
    running: live.map((a) => ({ id: a.id, ticket: ticket(a.label), label: rest(a.label), type: a.type, started: a.started, doing: a.doing || "" })),
    sessions: S.map((s) => (!("pid" in s)
      ? { id: s.seat, protected: true, session: "protected project", seat: names[s.seat] || "—", folder: "hidden", state: s.state === "working" ? "working" : "idle", by: "—", since: s.since }
      : { id: "pid" + s.pid, protected: false, session: s.name || "pid " + s.pid, seat: s.seat ? names[s.seat] || s.seat : s.parent ? "under " + (names[s.parent] || s.parent) : "—",
        folder: s.cwd || "", state: s.state, by: s.started_by || "—", since: s.since })),
    claims: (A.claims || []).map(claimRow),
  };
  signs([...rooms, ...staff], who, S, byPid, panels, ceo);
  return {
    ceo, rooms, staff, who, night, error: P.error || "", panels,
    line: { sessions: S.length, working: S.filter((s) => s.state === "working").length, on: on.length, of: members.length, soon: next.length ? { name: next[0].name, next: next[0].next } : null },
  };
}

const base = (k) => String(k).replace(/-\d+$/, "");
/* Gives every room but the CEO's a wall sign (`sign` id, its people's `sign`) and its info: next runs, sessions, held files, running sub-agents; rows no avatar holds go to the CEO's `loose`. */
function signs(all, who, S, byPid, panels, ceo) {
  const owner = {}, ses = {};
  for (const r of all) {
    r.sign = r.kind === "seat" ? "room-" + r.id : r.id;
    who[r.sign] = r;
    for (const p of r.people) {
      p.sign = r.sign;
      for (const k of [p.id, p.kind === "agent" ? p.name : "", p.raw.started_by]) if (k) for (const x of [k, base(k)]) owner[x] = owner[x] || r.sign;
    }
  }
  for (const s of S) {
    const a = s.pid != null && byPid.get(s.pid), p = s.seat ? who[s.seat] : who["pid" + s.pid] || (a && who[a.id]);
    if (p) ses["pid" in s ? "pid" + s.pid : s.seat] = p.sign || (p === (ceo && ceo.people[0]) ? "ceo" : "");
  }
  const held = (c) => owner[c.who] || "";
  for (const r of all) {
    const ids = new Set(r.people.map((p) => p.id));
    r.info = { name: r.kind === "seat" && r.area ? r.area : r.name, next: panels.next.filter((n) => ids.has(n.id)), sessions: panels.sessions.filter((x) => ses[x.id] === r.sign),
      claims: panels.claims.filter((c) => held(c) === r.sign), subs: panels.running.filter((a) => ids.has(a.id)) };
    for (const p of r.people) p.info = r.info;
  }
  if (ceo) ceo.people[0].raw.loose = { needs: ceo.live.lamp === "needs", sessions: panels.sessions.filter((x) => !(x.id in ses)), claims: panels.claims.filter((c) => !held(c)) };
}

const rooms = (M) => [M.ceo, ...M.rooms, ...M.staff].filter(Boolean);
const look = (p) => JSON.stringify([p.pose, p.state, p.since, p.name, p.rank, p.room]);

/* What changed from model a to model b: the layout, day or night, rooms by key, people by look, boards, the band line. */
export function diff(a, b) {
  const R = rooms(b), people = R.flatMap((r) => r.people);
  if (!a) return { layout: true, night: false, rooms: R.map((r) => r.id), people: people.map((p) => p.id), panels: Object.keys(b.panels), line: true };
  const was = new Map(rooms(a).map((r) => [r.id, r.key])), saw = new Map(rooms(a).flatMap((r) => r.people).map((p) => [p.id, look(p)]));
  return {
    layout: rooms(a).map((r) => r.id).join("\n") !== R.map((r) => r.id).join("\n"),
    night: a.night !== b.night,
    rooms: R.filter((r) => was.get(r.id) !== r.key).map((r) => r.id),
    people: people.filter((p) => saw.get(p.id) !== look(p)).map((p) => p.id),
    panels: Object.keys(b.panels).filter((k) => JSON.stringify(a.panels[k]) !== JSON.stringify(b.panels[k])),
    line: JSON.stringify(a.line) !== JSON.stringify(b.line),
  };
}
