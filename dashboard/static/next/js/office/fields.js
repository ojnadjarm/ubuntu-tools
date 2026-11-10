/* Card content for whoever is tapped in the office: one entry per kind in CARDS, plain data (the overlay escapes and draws it); `lines` are prose lines under the sub. */
import { dmOf } from "../seats.js";
import { rest } from "./model.js";
import { ago, until, progress, took } from "./time.js";

const ROLE = { ceo: "Runs the fleet and answers questions about the harness.", po: "Product owner.", manager: "Project manager. Never posts." };
const WAKE = { channel: "Always on; woken through its chat channel.", "po-inbox": "Asleep until someone writes to its inbox.", pull: "Reads its messages when it next runs." };
const SAY = { working: "working", talking: "talking", error: "stuck on an error", idle: "idle", asleep: "asleep", off: "off", yours: "yours" };
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

/* The CEO: about, role and wake lines, how many agents work at the desk pool, its session, a message button. */
function ceo(p, t) {
  const r = p.raw, c = r.crew || { n: 0, on: 0 };
  return { ...base(p, t, r.area), lines: lines(r), rows: [["Agents working", String(c.on)], ["At the desk pool", String(c.n)], ...where(r.session, t)], actions: message(p) };
}

/* A product owner or manager seat: area, about, role and wake lines, workers, its session, a message button. */
function seat(p, t) {
  const r = p.raw, c = r.crew || { n: 0, on: 0 };
  return { ...base(p, t, r.area), lines: lines(r), rows: [["Workers", c.n ? plural(c.n, "worker") + ", " + c.on + " working" : "no workers"], ...where(r.session, t)], actions: message(p) };
}

/* A session a seat started: who it works for, its folder, who started it, when it was last active. */
function worker(p, t) {
  return { ...base(p, t, "Works for " + p.raw.boss), rows: where(p.raw, t) };
}

/* An agent the CEO runs: its ticket, what it is doing now and since when, or how it ended. */
function agent(p, t) {
  const a = p.raw, run = a.state === "working";
  return { ...base(p, t, rest(a.label)), rows: keep(run ? [["Running for", ago(a.started, t)], ["Now", a.doing]] : [["Ended", ago(a.last, t) + " ago"], ["Report", a.report]]) };
}

/* A rostered staff agent: schedule, next run and how far it is, last run, exit, length, report; no message button. */
function staff(p, t) {
  const m = p.raw, last = m.last || {}, u = m.runner || {}, bad = m.health === "bad", fb = m.fallback;
  const text = p.pose === "working" ? "Running now" : bad ? "Stuck on an error" : m.on ? "Asleep until its next run" : "Off";
  const rows = keep([["Schedule", m.schedule], ["Next run", m.on && m.next ? "in " + until(m.next, t) : "—"], ["Last run", last.end ? ago(last.end, t) + " ago" : "never"]]);
  rows.push(bad ? ["Last exit", last.exit || "—", "bad"] : ["Last exit", last.exit || "—"], ["Took", took(last.seconds)]);
  if (u.unit) rows.push(["Unit", u.unit]);
  if (m.kind === "service") rows.push(["Up since", u.since ? ago(u.since, t) + " ago" : "—"]);
  if (fb) rows.push(["Fallback last ran", fb.end ? ago(fb.end, t) + " ago" : "never"]);
  rows.push(["Report", m.report || "no report yet"]);
  const c = { ...base(p, t, m.id + " · " + m.team), state: { pose: p.pose, text }, rows };
  if (m.on && m.next) c.bar = progress(last.end, m.next, t);
  return c;
}

/* A staff team's room: how many run now and who is in it. */
function team(r) {
  return { title: r.name, rank: "Team", sub: r.people.length + " staff", state: { pose: r.pose, text: r.busy + " running now" }, rows: [], actions: [], roll: r.people.map((p) => p.id) };
}

/* The desk pool: the agents the CEO runs himself. */
function pool(r) {
  return { title: r.name, rank: r.rank, sub: "Agents the CEO runs himself", state: { pose: r.pose, text: r.busy + " working" }, rows: [], actions: [], roll: r.people.map((p) => p.id) };
}

export const CARDS = { ceo, seat, worker, agent, staff, team, pool };

/* The card of a person or room, by its kind. */
export const card = (p, t = Date.now()) => CARDS[p.kind](p, t);
