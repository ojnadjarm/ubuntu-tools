/* Card content for whoever is tapped in the office: one entry per kind in CARDS, plain data (the overlay escapes and draws it); `lines` are prose lines under the sub. */
import { dmOf } from "../seats.js";
import { rest } from "./model.js";
import { ago, at, until, progress, took } from "./time.js";

const ROLE = { ceo: "Runs the fleet and answers questions about the harness.", po: "Product owner.", manager: "Project manager. Never posts." };
const WAKE = { channel: "Always on; woken through its chat channel.", "po-inbox": "Asleep until someone writes to its inbox.", pull: "Reads its messages when it next runs." };
const SAY = { available: "free to talk", working: "working", talking: "talking", error: "stuck on an error", idle: "idle", asleep: "asleep", off: "off", yours: "yours", done: "done", stale: "stopped" };
const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s");
const keep = (rows) => rows.filter((r) => r[1] != null && r[1] !== "");
/* A card's text kept to one line: longer text is cut with an ellipsis. */
const cut = (s, n = 80) => (s && s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s);
/* A card's list kept short: the first 5, and how many more there are. */
export const MAX = 5;
const cap = (list) => ({ shown: list.slice(0, MAX), more: Math.max(0, list.length - MAX) });

/* "Now <state>", with how long when awake (a protected seat shows its state only). */
const now = (p, t) => "Now " + (SAY[p.state] || p.state) + (p.pose === "sleep" || p.state === "yours" || !p.since ? "" : " · " + ago(p.since, t));
const message = (p) => [{ label: "Message " + p.name, href: "#chat?ch=" + dmOf(p.id) }];
const base = (p, t, sub) => ({ title: p.name, rank: p.rank || "", sub: sub || "", state: { pose: p.pose, text: now(p, t) }, rows: [], actions: [] });

/* A seat's about, role and wake lines, as the old Org tooltip read them. */
const lines = (r) => [r.about, ROLE[r.role], WAKE[r.wake]].filter(Boolean);
/* A session's folder, who started it and when it was last active; a protected one shows its last activity only. */
const where = (s, t) => (!s ? [] : !("pid" in s) ? [["Folder", "protected project"], ["Last active", ago(s.since, t) + " ago"]]
  : keep([["Folder", s.cwd], ["Started by", s.started_by], ["Last active", s.since ? ago(s.since, t) + " ago" : ""]]));

/* The CEO: about, role and wake lines, how many agents work (every live one) and sit at the desk pool, the agent that just failed, its session by name, a message button. */
function ceo(p, t) {
  const r = p.raw, c = r.crew || { n: 0, on: 0 }, f = r.failing, s = r.session;
  return { ...base(p, t, r.area), lines: lines(r), rows: [["Agents", c.on + " working"], ["At the desk pool", String(c.n)],
    ...(f ? [["Failed", f.ticket + " · " + ago(f.last, t) + " ago", "bad"]] : []), ...(s && "pid" in s ? [["Session", s.name || "pid " + s.pid]] : []), ...where(s, t)], actions: message(p) };
}

/* A free seat's live workers, one row each: ticket, since when, how long; none while the seat itself works. */
const crew = (p, t) => p.state !== "available" ? [] : [part("Workers running", "no workers running", p.raw.crew.list.map((w) => [w.name, "since " + at(w.since, t) + " · " + ago(w.since, t)]))];

/* A product owner or manager seat: area, about, role and wake lines, workers, its session, its runner's 4 rows, a message button; free to talk while only its workers run. */
function seat(p, t) {
  const r = p.raw, c = r.crew || { n: 0, on: 0 };
  const run = r.runner ? last4(r.runner, t, r.runner.health === "bad") : [];
  const b = base(p, t, r.area), state = p.state === "available" ? { ...b.state, text: "Free to talk · " + plural(c.n, "worker") + " running" } : b.state;
  return { ...b, state, lines: lines(r), rows: [["Workers", c.n ? plural(c.n, "worker") + ", " + c.on + " working" : "no workers"], ...where(r.session, t), ...run], parts: crew(p, t), actions: message(p) };
}

/* A session a seat started: who it works for, its folder, who started it, when it was last active. */
function worker(p, t) {
  return { ...base(p, t, "Works for " + p.raw.boss), rows: where(p.raw, t) };
}

/* An agent the CEO runs: its ticket, label, type, what it is doing now and since when (or how it ended), the session it runs in. */
function agent(p, t) {
  const a = p.raw, s = a.session, run = a.state === "working";
  const rows = run ? [["Running since", when(a.started, t)], ["Now", cut(a.doing) || "starting"]]
    : [["Ended", when(a.last, t)], ["Report", cut(a.report || (a.state === "stale" ? "no report · last step · " + (a.doing || "—") : ""))]];
  return { ...base(p, t, rest(a.label)), rows: keep([["Type", a.type], ...rows, ...(s ? [["Session", "pid " + s.pid], ...where(s, t)] : [])]) };
}

const when = (v, t) => at(v, t) + " · " + ago(v, t) + " ago";
const ran = (l, t) => (l && l.end ? when(l.end, t) : "never");
const gold = (row, bad) => (bad ? [...row, "bad"] : row);
const exit = (l) => (l && l.exit != null && l.exit !== "" ? String(l.exit) : "—");
const next = (m, t, none) => (m.on && m.next ? "in " + until(m.next, t) + " · " + at(m.next, t) : none);

/* A runner's last run, exit, length and report line: the 4 rows a staff card and a PO or manager seat's card share. */
const last4 = (m, t, bad, L = ["Last run", "Last exit", "Report"]) => [[L[0], ran(m.last, t)], gold([L[1], exit(m.last)], bad), ["Took", took((m.last || {}).seconds)], [L[2], cut(m.report) || "no report yet"]];

/* Per runner kind (the Roster's cards): its pill, its rows and what it does while it rests. A bash timer with no fallback is a plain timer. */
const RUNNERS = {
  "timer-agent": (m, t, bad) => ({ pill: m.on ? "scheduled" : "off", rest: m.on ? "Asleep until its next run" : "Off",
    rows: [["Schedule", m.schedule || "no schedule"], ["Next run", next(m, t, "off")], ...last4(m, t, bad)] }),
  "bash-timer": (m, t, bad) => {
    const fb = m.fallback, own = last4(m, t, bad, ["Last check", "Result", fb ? "Fallback report" : "Report"]);
    return { pill: m.on ? (bad ? "failed" : "on") : "down", rest: m.on ? "Asleep until its next run" : "Timer down",
      rows: [["Schedule", m.schedule || "—"], ["Unit", (m.runner || {}).unit || "—"], ["Next run", next(m, t, "down")], ...own.slice(0, 3), ...(fb ? [["Fallback last ran", ran(fb, t)]] : []), own[3]] };
  },
  service: (m, t, bad) => {
    const u = m.runner || {}, pill = m.on ? "on" : bad ? "failed" : m.health === "warn" ? "down" : "off";
    return { pill, rest: m.on ? "Always on" : "Off", rows: [["Schedule", "always on"], ["Unit", u.unit || "—"], ["Up since", m.on && u.since ? when(u.since, t) : "—"],
      gold(["Unit state", (u.state || "—") + (u.sub ? " · " + u.sub : "")], u.state !== "active"),
      ...(u.tmux ? [gold(["Tmux", u.tmux + " · " + (u.tmux_alive ? "alive" : "missing")], !u.tmux_alive)] : []), ["Report", cut(m.report) || "no report yet"]] };
  },
  "on-demand": (m, t, bad) => ({ pill: "off", rest: "Asleep until someone starts it", rows: [["Schedule", "on demand"], ...last4(m, t, bad)] }),
};

/* A rostered staff agent: name, rank, its id and team, its runner's pill and rows, the bar to its next run; dim when off; no message button. */
function staff(p, t) {
  const m = p.raw, bad = m.health === "bad", k = (RUNNERS[m.kind] || RUNNERS["timer-agent"])(m, t, bad);
  const text = p.pose === "working" ? "Running now" : bad ? "Stuck on an error" : k.rest;
  const c = { ...base(p, t, m.id + " · " + m.team), state: { pose: p.pose, text }, rows: [gold(["Status", k.pill], bad), ...k.rows] };
  if (m.on && m.next) c.bar = progress((m.last || {}).end, m.next, t);
  if (!m.on && p.pose !== "working" && !bad) c.dim = true;
  return c;
}

const NOTE = { "team-unassigned": "Rostered agents that no team in staff.json names." };
/* One titled list of a card: at most 5 rows or chips, the rest counted in `more`. */
function part(h, empty, rows, chips) {
  const r = cap(rows || []), c = cap(chips || []);
  return { h, empty, rows: r.shown, chips: c.shown, more: r.more + c.more };
}
/* Running sub-agents as chips: ticket, running since, what each does now. */
const subs = (I, t) => part("Sub-agents running", "none running for this project", null, I.subs.map((a) => ({ id: a.id, name: a.ticket, note: "since " + at(a.started, t) + " · " + (cut(a.doing, 60) || "starting"), pose: "working" })));
/* Sessions as one line each: name, state, last active (the folder is on the session's own card). */
const sessions = (I, t) => part("Sessions", "no sessions", I.sessions.map((x) => [x.session, x.state + " · " + ago(x.since, t) + " ago"]));
/* Held files as one row: how many files and whose ("9 · T1616"); no paths; none held, no row. */
function held(claims) {
  if (!claims.length) return [];
  const n = claims.reduce((s, c) => s + c.paths.length, 0), who = cap(claims.map((c) => c.who));
  return [["Files held", n + " · " + who.shown.join(", ") + (who.more ? " +" + who.more + " more" : "")]];
}
const runs = (I, t) => part("Next runs", "no scheduled runs", I.next.map((n) => [n.name, "in " + until(n.next, t) + " · " + at(n.next, t) + (n.bad ? " · last run failed" : ""), n.bad ? "bad" : ""].filter(Boolean)));

/* A room's info, its sign's card: who is in it with their state (5, then +N more; a running sub-agent only once, in its own list), the files it holds in one row, its next runs, sessions and running sub-agents; empty parts say so in one line. */
function room(r, t, sub, extra) {
  const I = r.info, run = new Set(I.subs.map((a) => a.id)), ids = r.people.map((p) => p.id).filter((id) => !run.has(id)), roll = cap(ids.length || !run.size ? ids : []);
  return { title: I.name, rank: r.kind === "seat" ? "Project" : r.kind === "pool" ? r.rank : "Team", sub, ...extra, state: { pose: r.pose, text: r.busy + " working now" }, rows: held(I.claims), actions: [],
    roll: ids.length || !run.size ? roll.shown : null, rollMore: roll.more, parts: [runs(I, t), sessions(I, t), subs(I, t)] };
}
/* A staff team's room; the Unassigned room says why they are there. */
const team = (r, t) => room(r, t, r.people.length + " staff", NOTE[r.id] ? { lines: [NOTE[r.id]] } : {});
/* The desk pool: the agents the CEO runs himself. */
const pool = (r, t) => room(r, t, "Agents the CEO runs himself");
/* A seat's room: its project, the seat and the workers at its desks, the working ones listed. */
const project = (r, t) => { const c = room(r, t, r.area || r.people[0].name + "'s room"); return { ...c, parts: [...crew(r.people[0], t), ...c.parts] }; };

/* A person's card gains the line naming its room (opens the room's card) and the room's running sub-agents; a seat also its room's sessions and the files it holds. */
function homed(p, t, c) {
  const r = p.sign && p.info, lead = p.kind === "seat";
  return r ? { ...c, rows: lead ? [...c.rows, ...held(r.claims)] : c.rows, home: { id: p.sign, text: "Team · " + r.name },
    parts: [...(c.parts || []), ...(lead ? [sessions(r, t)] : []), subs(r, t)] } : c;
}

/* What only the CEO sees: needs-you, the sessions and the files (one row) no avatar holds. */
function loose(p, t, c) {
  const L = p.raw.loose || { sessions: [], claims: [] };
  return { ...c, rows: [...c.rows, ...held(L.claims)], parts: [part("Needs you", "nothing needs you", L.needs ? [["Needs you", "yes · the status lamp is on"]] : []),
    sessions(L, t)] };
}

export const CARDS = { ceo, seat, worker, agent, staff, team, pool };

/* The card of a person or room, by its kind; a person's card links its room, the CEO's adds what no avatar shows. */
export function card(p, t = Date.now()) {
  if (p.people) return p.kind === "seat" ? project(p, t) : CARDS[p.kind](p, t);
  const c = CARDS[p.kind](p, t);
  return p.kind === "ceo" ? loose(p, t, c) : homed(p, t, c);
}
