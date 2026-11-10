// Office parity (T1601-14) fixture: one payload with every PLAN §2.1 field, the old screens' helpers and the row helpers, read against one clock.
"use strict";
const assert = require("assert");
const H = 3600e3, M_ = 60e3, iso = (t) => new Date(t).toISOString(), sec = (t) => Math.round(t / 1000);

/* Old helpers, as court.js and roster.js wrote them. */
const tk = (l) => (/^[A-Za-z]{1,3}\d+\w*(\s+[A-Za-z]{1,3}\d+\b)?/.exec(l) || [l.split(" ")[0]])[0];
let CLOCK = Date.now();
const mins = (t) => { const ms = typeof t === "number" ? t * 1000 : Date.parse(t); return Math.max(0, (CLOCK - ms) / 60000); };
const ago = (t) => { const m = mins(t); return m < 60 ? Math.round(m) + " min" : m < 2880 ? (m / 60).toFixed(1) + " h" : Math.round(m / 1440) + " d"; };
const until = (t) => { const h = (Date.parse(t) - CLOCK) / 3600000; return h < 1 ? Math.max(0, Math.round(h * 60)) + " min" : h < 48 ? h.toFixed(0) + " h" : (h / 24).toFixed(0) + " d"; };
const ROLE = { ceo: "Runs the fleet and answers questions about the harness.", po: "Product owner.", manager: "Project manager. Never posts." };
const WAKE = { channel: "Always on; woken through its chat channel.", "po-inbox": "Asleep until someone writes to its inbox.", pull: "Reads its messages when it next runs." };
const dmOf = (id) => "dm-" + ["owner", id].sort().join("--");
const bad = (r) => (r.health ? r.health === "bad" : !!(r.last && r.last.exit && r.last.exit !== "0"));

/* The fixture at time t: every §2.1 field filled; times sit away from rounding edges. */
function fixture(t, error = "") {
  const run = (name, end, exit, s, report, extra) => ({ name, enabled: "no", schedule: "on demand", next: "", last: { end: iso(end), exit, seconds: s }, kind: "on-demand", on: false, health: "off", runner: { kind: "on-demand", unit: `agent@${name}.service` }, report, state: "off", ...extra });
  const m = (id, name, rank, kind, o) => ({ id, name, rank, kind, state: "idle", on: true, health: "ok", report: "", ...o });
  const w = (pid, state, name, by, ago_m) => ({ seat: null, state, since: sec(t - ago_m * M_), pid, parent: "beta", ...(name ? { name } : {}), cwd: "~/projects/beta-" + pid, started_by: by, rank: "Worker" });
  return {
    seats: [
      { id: "orchestrator", name: "DarkSaddler", rank: "CEO", role: "ceo", parent: "owner", area: "Fleet HQ", about: "Runs the whole fleet.", wake: "channel" },
      { id: "alpha", name: "Mossfang", rank: "Product Owner", role: "po", parent: "orchestrator", area: "Alpha Isle", about: "An island course in the browser.", wake: "po-inbox", runner: run("po-alpha", t - 5.32 * H, "0", "312", "Shipped zone 3 props.") },
      { id: "beta", name: "Bramble", rank: "Manager", role: "manager", parent: "alpha", area: "Beta Board", about: "A narrated board-game helper.", wake: "po-inbox", runner: run("po-beta", t - 2.42 * H, "3", "640", "Two PRs open.", { health: "bad" }) },
      { id: "gamma", name: "Thistle", rank: "Product Owner", role: "po", parent: "orchestrator", area: "Client Gamma", about: "A client project.", wake: "pull" },
    ],
    sessions: [
      { seat: "orchestrator", state: "working", since: sec(t - 40.2 * M_), pid: 2001, parent: "owner", name: "CEO console", cwd: "~", started_by: "owner" },
      { seat: "beta", state: "idle", since: sec(t - 12.3 * M_), pid: 2002, parent: "alpha", name: "agent-po-beta", cwd: "~/agents/po-beta", started_by: "po-beta" },
      w(2003, "working", "agent-T8001", "T8001", 33.3), w(2004, "idle", "agent-T8021", "T8021", 21.4), w(2005, "working", "", "T8022", 17.2), w(2006, "idle", "agent-T8023", "T8023", 27.4), w(2007, "idle", "agent-T8024", "T8024", 8.4),
      { seat: null, state: "working", since: sec(t - 14.3 * M_), pid: 2010, parent: "orchestrator", name: "agent-T8010", cwd: "~/agents", started_by: "T8010", rank: "Worker" },
      { seat: "gamma", state: "working", since: sec(t - 6.4 * M_) },
    ],
    staff: [
      { id: "operations", name: "Operations", members: [
        m("digest", "Cinder", "Watch Reporter", "timer-agent", { schedule: "daily 07:00", next: iso(t + 5.4 * H), last: { end: iso(t - 6.32 * H), exit: "0", seconds: "130" }, runner: { kind: "timer-agent", unit: "agent@digest.timer" }, report: "All quiet." }),
        m("keeper", "Wren", "Moodle Keeper", "timer-agent", { health: "bad", schedule: "Mon 04:00", next: iso(t + 30.4 * H), last: { end: iso(t - 7.42 * H), exit: "2", seconds: "1200" }, runner: { kind: "timer-agent", unit: "agent@keeper.timer" } }),
        m("smith", "Soot", "Toolsmith", "timer-agent", { state: "off", on: false, health: "off", schedule: "Sun 05:00", next: "", last: { end: iso(t - 50.2 * H), exit: "0", seconds: "2400" }, runner: { kind: "timer-agent", unit: "agent@smith.timer" }, report: "Built 1 tool." }),
        m("maint", "Briar", "Caretaker", "timer-agent", { state: "running", schedule: "every 6 h", next: iso(t + 4.4 * H), last: { end: iso(t - 1.62 * H), exit: "0", seconds: "300" }, runner: { kind: "timer-agent", unit: "agent@maint.timer" }, report: "Pruned 3 GB of caches." }),
        m("watch", "Ember", "Sentinel", "bash-timer", { health: "bad", schedule: "hourly", next: iso(t + 1.4 * H), last: { end: iso(t - 33.2 * M_), exit: "1", seconds: "3" }, runner: { kind: "bash-timer", unit: "watch-check.timer", service: "watch-check.service", state: "active", result: "exit-code" }, fallback: { end: iso(t - 8.32 * H), exit: "0", seconds: "40" }, report: "disk check failed" }),
        m("relay", "Sorrel", "Liaison", "service", { schedule: "always on", next: "", last: {}, runner: { kind: "service", unit: "relay.service", state: "active", sub: "running", tmux: "relay-tmux", tmux_alive: true, since: iso(t - 30.32 * H) }, report: "relay up" }),
      ] },
      { id: "quality", name: "Quality", members: [
        m("ci-fix", "Flint", "CI Fixer", "on-demand", { state: "off", on: false, health: "off", schedule: "on demand", next: "", last: { end: iso(t - 13.62 * H), exit: "0", seconds: "44" }, runner: { kind: "on-demand", unit: "agent@ci-fix.service" }, report: "Fixed a test drift." }),
        m("backup", "Yarrow", "Archivist", "bash-timer", { schedule: "daily 03:30", next: iso(t + 11.4 * H), last: { end: iso(t - 12.62 * H), exit: "0", seconds: "660" }, runner: { kind: "bash-timer", unit: "backup.timer", service: "backup.service", state: "active", result: "success" }, unit: "backup.timer" }),
      ] },
      { id: "unassigned", name: "Unassigned", members: [
        m("night-relay", "night-relay", "Staff", "service", { state: "off", on: false, health: "warn", schedule: "always on", next: "", last: {}, runner: { kind: "service", unit: "night-relay.service", state: "inactive", sub: "dead", tmux: "nr-tmux", tmux_alive: false }, report: "" }),
      ] },
    ],
    agents: {
      orchestrator: { name: "DarkSaddler", role: "ceo", rank: "CEO", session: "abcd1234", state: "running" },
      subagents: [
        { id: "pid2003", label: "T8001", type: "session", started: iso(t - 33.3 * M_), last: sec(t - 0.4 * M_), state: "working", doing: "live session · pid 2003", report: "" },
        { id: "pid2010", label: "T8010", type: "session", started: iso(t - 14.3 * M_), last: sec(t - 0.4 * M_), state: "working", doing: "live session · pid 2010", report: "" },
        { id: "a8002", label: "T8002-03 hall painter", type: "worker-max", started: iso(t - 44.2 * M_), last: sec(t - 0.3 * M_), state: "working", doing: "Paints the hall", report: "" },
        { id: "a8004", label: "T8004 broken run", type: "worker", started: iso(t - 30.2 * M_), last: sec(t - 4.3 * M_), state: "error", doing: "step 3", report: "tests red" },
        { id: "a8005", label: "T8005 done run", type: "worker", started: iso(t - 3.2 * H), last: sec(t - 2.2 * H), state: "done", doing: "", report: "5 of 5 green" },
      ],
      claims: [
        "T8001 · dashboard/static/next/js/office/model.js ~/projects/beta-board/src/components/narration/panels/deep/folder/panel.js · core work · 2026-11-10 16:21",
        "nobody-x · ~/drop/X1/ · do not move · 2026-11-09",
      ],
    },
    error,
  };
}

const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: false, problems: [], needs: [{ kind: "need", text: "disk low", t: "2026-11-10T10:00:00Z" }] } };

/* Card c shows every x (case-blind: CSS may set a label in capitals). */
const has = (c, ...xs) => { assert.ok(c, "card missing"); for (const x of xs) assert.ok(c.text.toLowerCase().includes(String(x).toLowerCase()), `${c.id}: "${x}" not on the card`); };
const inScene = (X, id) => assert.ok(X.anchor[id], id + ": not in the 3D scene");
const val = (c, k) => (c.rows.find((r) => r[0] === k) || [])[1];
/* The last-run rows a Roster card showed: when and ago, exit, seconds, report or "no report yet". */
const lastRows = (c, r, pre) => { if (r.last && r.last.end) has(c, ago(r.last.end) + " ago"); else has(c, "never"); if (r.last && r.last.exit) has(c, r.last.exit); if (r.last && r.last.seconds) has(c, r.last.seconds + " s"); has(c, r.report || "no report yet"); if (pre && r.report) has(c, pre); };

/* The fixture the page shows, its times read against the same clock: its parts and the old screens' state rules over them. */
function setFix(T) {
  CLOCK = T;
  const F0 = fixture(T), seats = F0.seats, S0 = F0.sessions, subs = F0.agents.subagents, members = F0.staff.flatMap((t) => t.members.map((m) => ({ ...m, team: t.id })));
  const live = subs.filter((s) => s.state === "working"), L = members.filter((r) => r.name !== "hello"), up = L.filter((r) => r.on);
  const q = up.filter((r) => r.next).sort((a, b) => Date.parse(a.next) - Date.parse(b.next));
  /* A seat's old Org state; the CEO shows C4's error pose while an agent failed < 10 min ago. */
  const nowOf = (s) => (s.role === "ceo" && subs.some((a) => a.state === "error" && mins(a.last) < 10) ? "stuck on an error" : seatState(s));
  const seatState = (seat) => { const mine = S0.filter((s) => s.seat === seat.id); return mine.some((s) => !("pid" in s)) ? "yours" : mine.some((s) => s.state === "working") ? "working" : mine.length ? "idle" : seat.wake === "channel" ? "off" : "asleep"; };
  return { F0, seats, S0, subs, members, live, L, up, q, nowOf, seatState };
}

module.exports = { fixture, STATUS, setFix, tk, mins, ago, until, ROLE, WAKE, dmOf, bad, iso, has, inScene, val, lastRows };
