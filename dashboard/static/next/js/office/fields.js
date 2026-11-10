/* Card content for whoever is tapped in the office: one entry per kind in CARDS, plain data (the overlay escapes and draws it); `lines` are prose lines under the sub. */
import { dmOf } from "../seats.js";
import { rest } from "./model.js";
import { ago, until, progress, took } from "./time.js";

const ROLE = { ceo: "Runs the fleet and answers questions about the harness.", po: "Product owner.", manager: "Project manager. Never posts." };
const WAKE = { channel: "Always on; woken through its chat channel.", "po-inbox": "Asleep until someone writes to its inbox.", pull: "Reads its messages when it next runs." };
const SAY = { working: "working", talking: "talking", error: "stuck on an error", idle: "idle", asleep: "asleep", off: "off", yours: "yours", done: "done", stale: "stopped" };
const plural = (n, w) => n + " " + w + (n === 1 ? "" : "s");
const keep = (rows) => rows.filter((r) => r[1] != null && r[1] !== "");

/* "Now <state>", with how long when awake (a protected seat shows its state only). */
const now = (p, t) => "Now " + (SAY[p.state] || p.state) + (p.pose === "sleep" || p.state === "yours" || !p.since ? "" : " · " + ago(p.since, t));
const message = (p) => [{ label: "Message " + p.name, href: "#chat?ch=" + dmOf(p.id) }];
const base = (p, t, sub) => ({ title: p.name, rank: p.rank || "", sub: sub || "", state: { pose: p.pose, text: now(p, t) }, rows: [], actions: [] });

/* A seat's about, role and wake lines, as the old Org tooltip read them. */
const lines = (r) => [r.about, ROLE[r.role], WAKE[r.wake]].filter(Boolean);
/* A session's folder, who started it and when it was last active; a protected one shows its last activity only. */
const where = (s, t) => (!s ? [] : !("pid" in s) ? [["Folder", "protected project"], ["Last active", ago(s.since, t) + " ago"]]
  : keep([["Folder", s.cwd], ["Started by", s.started_by], ["Last active", s.since ? ago(s.since, t) + " ago" : ""]]));

/* The CEO: about, role and wake lines, how many agents work at the desk pool, the agent that just failed, its session, a message button. */
function ceo(p, t) {
  const r = p.raw, c = r.crew || { n: 0, on: 0 }, f = r.failing;
  return { ...base(p, t, r.area), lines: lines(r), rows: [["Agents working", String(c.on)], ["At the desk pool", String(c.n)],
    ...(f ? [["Failed", f.ticket + " · " + ago(f.last, t) + " ago", "bad"]] : []), ...where(r.session, t)], actions: message(p) };
}

/* A product owner or manager seat: area, about, role and wake lines, workers, its session, its runner's 4 rows, a message button. */
function seat(p, t) {
  const r = p.raw, c = r.crew || { n: 0, on: 0 };
  const run = r.runner ? last4(r.runner, t, r.runner.health === "bad") : [];
  return { ...base(p, t, r.area), lines: lines(r), rows: [["Workers", c.n ? plural(c.n, "worker") + ", " + c.on + " working" : "no workers"], ...where(r.session, t), ...run], actions: message(p) };
}

/* A session a seat started: who it works for, its folder, who started it, when it was last active. */
function worker(p, t) {
  return { ...base(p, t, "Works for " + p.raw.boss), rows: where(p.raw, t) };
}

/* An agent the CEO runs: its ticket, label, type, what it is doing now and since when (or how it ended), the session it runs in. */
function agent(p, t) {
  const a = p.raw, s = a.session, run = a.state === "working";
  const rows = run ? [["Running since", when(a.started, t)], ["Now", a.doing || "starting"]]
    : [["Ended", when(a.last, t)], ["Report", a.report || (a.state === "stale" ? "no report · last step · " + (a.doing || "—") : "")]];
  return { ...base(p, t, rest(a.label)), rows: keep([["Type", a.type], ...rows, ...(s ? [["Session", "pid " + s.pid], ...where(s, t)] : [])]) };
}

const DAY = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const p2 = (n) => String(n).padStart(2, "0");
/* A moment as the Roster wrote it: "HH:MM" today, "yesterday HH:MM", "Wed HH:MM" within 6 days, else "D Mon". */
function at(v, t) {
  const d = new Date(typeof v === "number" ? v * 1000 : v), now = new Date(t), hm = p2(d.getHours()) + ":" + p2(d.getMinutes());
  if (isNaN(d)) return String(v);
  if (d.toDateString() === now.toDateString()) return hm;
  if (d.toDateString() === new Date(t - 86400e3).toDateString()) return "yesterday " + hm;
  return Math.abs(t - d) < 6 * 86400e3 ? DAY[d.getDay()] + " " + hm : d.getDate() + " " + MON[d.getMonth()] + (d.getFullYear() === now.getFullYear() ? "" : " " + d.getFullYear());
}
const when = (v, t) => at(v, t) + " · " + ago(v, t) + " ago";
const ran = (l, t) => (l && l.end ? when(l.end, t) : "never");
const gold = (row, bad) => (bad ? [...row, "bad"] : row);
const exit = (l) => (l && l.exit != null && l.exit !== "" ? String(l.exit) : "—");
const next = (m, t, none) => (m.on && m.next ? "in " + until(m.next, t) + " · " + at(m.next, t) : none);

/* A runner's last run, exit, length and report line: the 4 rows a staff card and a PO or manager seat's card share. */
const last4 = (m, t, bad, L = ["Last run", "Last exit", "Report"]) => [[L[0], ran(m.last, t)], gold([L[1], exit(m.last)], bad), ["Took", took((m.last || {}).seconds)], [L[2], m.report || "no report yet"]];

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
      ...(u.tmux ? [gold(["Tmux", u.tmux + " · " + (u.tmux_alive ? "alive" : "missing")], !u.tmux_alive)] : []), ["Report", m.report || "no report yet"]] };
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
/* A staff team's room: how many run now and who is in it; the Unassigned room says why they are there. */
function team(r) {
  return { title: r.name, rank: "Team", sub: r.people.length + " staff", ...(NOTE[r.id] ? { lines: [NOTE[r.id]] } : {}), state: { pose: r.pose, text: r.busy + " running now" }, rows: [], actions: [], roll: r.people.map((p) => p.id) };
}

/* The desk pool: the agents the CEO runs himself. */
function pool(r) {
  return { title: r.name, rank: r.rank, sub: "Agents the CEO runs himself", state: { pose: r.pose, text: r.busy + " working" }, rows: [], actions: [], roll: r.people.map((p) => p.id) };
}

export const CARDS = { ceo, seat, worker, agent, staff, team, pool };

/* The card of a person or room, by its kind. */
export const card = (p, t = Date.now()) => CARDS[p.kind](p, t);
