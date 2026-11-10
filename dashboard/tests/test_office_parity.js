// Office parity (T1601-14): nothing Org, Court and Roster showed is lost. One fixture fills every field of PLAN §2.1 (payload §4.1); one row per kept
// item (25), its assertion read from the old screens' source (court.js, roster.js, org.js before T1601-05), run at 1366 and 400. Every card is reached
// by clicks from the list (the keyboard path to the card a click on an avatar opens) and every subject is checked to stand in the 3D scene.
// Writes PARITY.md (item, where found, pass or FAIL) from the results. Run: node tests/test_office_parity.js   (fixture API only; PARITY=<file> moves the table)
"use strict";
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path");
const { pathToFileURL } = require("url");
const { execFileSync } = require("child_process");
const { chromium, serveStatic } = require("./lib/browser");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan", "--mute-audio"];
const OUT = process.env.PARITY || path.join(os.homedir(), "agent-work", "research", "2026-11-10", "T1601", "PARITY.md");
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

let mode = "", say = false, hits = [];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: false, problems: [], needs: [{ kind: "need", text: "disk low", t: "2026-11-10T10:00:00Z" }] } };
const srv = serveStatic((u, res) => {
  hits.push([u, Date.now()]);
  const F = fixture(Date.now(), mode === "stale" ? "office source failed: agents" : "");
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") {
    if (mode === "fail") { res.writeHead(500, { "Content-Type": "application/json" }); return res.end("{}"); }
    if (mode === "slow") { res.writeHead(200, { "Content-Type": "application/json" }); setTimeout(() => res.end(JSON.stringify(F)), 4000); return; }
    return F;
  }
  if (u === "/api/org") return { seats: F.seats, sessions: F.sessions, hidden: 0 };
  if (u === "/api/agents") return { ...F.agents, agents: [], roster: [] };
  if (u.startsWith("/api/chat")) return { messages: say ? [{ id: 9, from: "alpha", kind: "dm", ch: dmOf("alpha"), text: "zone 3 is in", t: iso(Date.now()) }] : [{ id: 1, from: "owner", kind: "dm", text: "hi" }], channels: [], wakes: { cap: 12, today: {} } };
});

/* Opens #org at width w, the renderer's apply wrapped so the test sees each model the scene draws. */
async function open(b, w, wait = true) {
  const p = await (await b.newContext({ viewport: { width: w, height: w < 600 ? 850 : 768 }, deviceScaleFactor: 1 })).newPage(), errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.addInitScript(() => {
    let R = null;
    window.__drawn = [];
    Object.defineProperty(window, "__office", { configurable: true, get: () => R, set: (v) => { R = v; const a = v.apply; v.apply = (M, plan, patch) => { window.__drawn.push({ t: Date.now(), M }); return a.call(v, M, plan, patch); }; } });
  });
  hits = [];
  await p.goto(base + "/#org", { waitUntil: "load" });
  if (wait) await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1 && !window.__office.stats().pending, null, { timeout: 30000 });
  return { p, errs };
}

/* Every card reachable by clicks: list buttons, then the chips and room lines on each card; text, rows, links, state and bar of each. */
async function crawl(p) {
  const route = {}, cards = {};
  for (const id of await p.$$eval(".office .olist [data-who]", (b) => b.map((x) => x.dataset.who))) route[id] = route[id] || [id];
  const todo = Object.keys(route);
  while (todo.length) {
    const id = todo.shift();
    if (cards[id]) continue;
    const c = await p.evaluate((r) => {
      const card = document.getElementById("office-card");
      if (card && card.matches(":popover-open")) card.hidePopover();
      document.querySelector(`.office .olist [data-who="${CSS.escape(r[0])}"]`).click();
      for (const id of r.slice(1)) document.querySelector(`#office-card [data-who="${CSS.escape(id)}"]`).click();
      const c = document.getElementById("office-card"), q = (s) => [...c.querySelectorAll(s)];
      const rows = q("dl").flatMap((dl) => [...dl.children].filter((e) => e.tagName === "DT").map((dt) => [dt.textContent, dt.nextElementSibling.textContent, dt.nextElementSibling.className]));
      const st = c.querySelector(".st");
      return { id: c.dataset.for, title: c.querySelector("h2").textContent, text: c.innerText, rows, hrefs: q("a[href]").map((a) => a.getAttribute("href")), titles: q("[title]").map((e) => e.title),
        chips: q("[data-who]").map((e) => e.dataset.who), heads: q("h3").map((e) => e.textContent), st: st && st.className, stText: st && st.textContent, dim: !!c.querySelector(".dim"),
        bar: c.querySelector("progress") ? +c.querySelector("progress").value : null, fig: !!c.querySelector(".cfig svg, .cfig .fam") };
    }, route[id]);
    cards[id] = c;
    for (const k of c.chips) if (!route[k]) { route[k] = [...route[id], k]; todo.push(k); }
  }
  await p.evaluate(() => document.getElementById("office-card").hidePopover());
  return cards;
}

const where = {};
/* One table row: id, the old item, where it is found now, the assertion over the page's facts X. */
const ROWS = [];
const row = (id, item, found, fn) => ROWS.push({ id, item, found, fn });
/* Card c shows every x (case-blind: CSS may set a label in capitals). */
const has = (c, ...xs) => { assert.ok(c, "card missing"); for (const x of xs) assert.ok(c.text.toLowerCase().includes(String(x).toLowerCase()), `${c.id}: "${x}" not on the card`); };
const inScene = (X, id) => assert.ok(X.anchor[id], id + ": not in the 3D scene");
const val = (c, k) => (c.rows.find((r) => r[0] === k) || [])[1];
let F0, seats, S0, subs, members, live, L, up, q;
/* The fixture the page shows, its times read against the same clock. */
function setFix(T) {
  CLOCK = T; F0 = fixture(T); seats = F0.seats; S0 = F0.sessions; subs = F0.agents.subagents; members = F0.staff.flatMap((t) => t.members.map((m) => ({ ...m, team: t.id })));
  live = subs.filter((s) => s.state === "working"); L = members.filter((r) => r.name !== "hello"); up = L.filter((r) => r.on);
  q = up.filter((r) => r.next).sort((a, b) => Date.parse(a.next) - Date.parse(b.next));
}
setFix(Date.now());
/* A seat's old Org state; the CEO shows C4's error pose while an agent failed < 10 min ago. */
const nowOf = (s) => (s.role === "ceo" && subs.some((a) => a.state === "error" && mins(a.last) < 10) ? "stuck on an error" : seatState(s));
const seatState = (seat) => { const mine = S0.filter((s) => s.seat === seat.id); return mine.some((s) => !("pid" in s)) ? "yours" : mine.some((s) => s.state === "working") ? "working" : mine.length ? "idle" : seat.wake === "channel" ? "off" : "asleep"; };

row("O1", "Org band: N Claude sessions, N working, `stale: <error>`", "band line over the office", (X) => {
  assert.ok(X.band.startsWith(`${S0.length} Claude sessions on this laptop, ${S0.filter((s) => s.state === "working").length} working`), X.band);
  assert.ok(X.staleBand.includes("stale: office source failed: agents"), X.staleBand);
});
row("O2", "Org tree: who reports to whom, N seats", "scene: every seat has a room, a sub-seat's room in its parent's team; list: child nested under parent", (X) => {
  for (const s of seats) inScene(X, s.id);
  const R = (id) => X.M.rooms.find((r) => r.id === id);
  assert.strictEqual(R("beta").team, R("alpha").team, "beta's room not in alpha's team");
  for (const s of seats.filter((s) => s.parent !== "owner")) assert.ok(X.nest[s.id] === s.parent, `${s.id} not under ${s.parent} in the list: ${X.nest[s.id]}`);
});
row("O4", "Org seat card: Familiar in state and role gear, name, rank, state dot", "scene creature at the lead desk (pose) + seat card (figure, name, rank, state)", (X) => {
  const POSE = { working: "working", idle: "idle", asleep: "sleep", off: "sleep" };
  for (const s of seats) {
    const c = X.cards[s.id], st = seatState(s);
    inScene(X, s.id); assert.ok(c.fig, s.id + ": no figure"); has(c, s.name, s.rank);
    assert.ok(c.stText.startsWith("Now " + nowOf(s)), `${s.id}: state "${c.stText}" not ${nowOf(s)}`);
    if (POSE[st] && s.id !== "orchestrator") assert.strictEqual(X.M.who[s.id].pose, s.runner && bad(s.runner) ? "error" : POSE[st], s.id + ": scene pose");
  }
});
row("O5", "Org seat tooltip: Name · Rank, area, about, role line, wake line, Now <state>.", "seat card", (X) => {
  for (const s of seats) has(X.cards[s.id], s.name, s.rank, s.area, s.about, ROLE[s.role], WAKE[s.wake], "Now " + nowOf(s));
});
row("O6", "Org Message button `#chat?ch=dm-…`", "seat card button", (X) => {
  for (const s of seats) assert.ok(X.cards[s.id].hrefs.includes("#chat?ch=" + dmOf(s.id)), s.id + ": no message link");
});
row("O7", "Org workers under a seat: N workers, M working, 3 shown, hidden N, name or pid, state, name · Worker", "seat card Workers row + scene desks + worker card", (X) => {
  const H_ = S0.filter((s) => !s.seat && s.parent === "beta");
  assert.ok(X.cards.beta.text.includes(`${H_.length} workers, ${H_.filter((s) => s.state === "working").length} working`), "beta card: worker count");
  for (const s of H_) {
    const id = "pid" + s.pid, c = X.cards[id];
    const merged = subs.some((a) => a.id === id);
    inScene(X, id); has(c, merged ? tk(subs.find((a) => a.id === id).label) : s.name || "pid " + s.pid);
    if (merged) assert.ok(Object.values(X.cards).some((k) => k.rows.some((r) => r[0] === s.name)), id + ": session name on no card"); else has(c, s.rank);
    assert.ok(c.st.includes(s.state === "working" ? "working" : "idle"), id + ": state " + c.st);
    if (!merged) has(c, "Works for Bramble");
  }
});
row("O8", "Org: a seat talks for 2 s when it posts", "scene creature pose (card shows it while open)", (X) => {
  assert.ok(X.talkCard, "alpha's open card did not talk");
  assert.ok(X.talkScene, "the 3D scene never drew alpha talking after it posted");
});
row("O9", "Org sessions table: Session, Seat, Folder, State, Started by, Last active; protected row", "room card Sessions (CEO card when no avatar) + the session's person card", (X) => {
  const all = Object.values(X.cards);
  for (const s of S0) {
    if (!("pid" in s)) { has(X.cards[s.seat], "protected project"); assert.ok(all.some((c) => c.rows.some((r) => r[0] === "protected project" && r[1].startsWith(s.state))), "protected row"); continue; }
    const name = s.name || "pid " + s.pid, list = all.find((c) => c.rows.some((r) => r[0] === name)) || all.find((c) => c.text.includes(name));
    assert.ok(list, `session name "${name}" (${s.seat || s.parent}, folder ${s.cwd}) on no card`);
    const r = list.rows.find((r) => r[0] === name); if (r) assert.ok(r[1].startsWith(s.state), name + ": state");
    const me = X.cards[s.seat || "pid" + s.pid];
    has(me, s.cwd, s.started_by, ago(s.since) + " ago");
    const boss = seats.find((x) => x.id === (s.seat || s.parent));
    assert.ok([me.text, list.text].some((t) => t.includes(boss.name) || t.includes(boss.area) || (boss.role === "ceo" && /CEO/.test(t))), name + ": its seat");
  }
});
row("O10", "Org loading and error text", "page text while /api/office is slow or fails", (X) => {
  assert.ok(X.slow.includes("reading the org…"), X.slow);
  assert.ok(X.fail.startsWith("org unreadable · "), X.fail);
});
row("C1", "Court running now: creature, ticket, label, state, running <time>, now · <doing>", "scene creature + agent card", (X) => {
  for (const a of live) { const c = X.cards[a.id]; inScene(X, a.id); has(c, ...a.label.split(/\s+/), ago(a.started) + " ago", a.doing); assert.ok(c.st.includes("working"), a.id + " state"); }
});
row("C2", "Court rows of live sessions an agent started: pid, started by", "one creature per session; its agent card: Session pid N, Started by", (X) => {
  for (const a of live.filter((a) => /^pid/.test(a.id))) {
    const s = S0.find((x) => "pid" + x.pid === a.id);
    has(X.cards[a.id], "pid " + s.pid, s.started_by);
    const same = Object.values(X.cards).filter((c) => [s.name, tk(a.label)].some((n) => c.title === n || c.title.startsWith(n + " · "))).map((c) => c.id);
    assert.deepStrictEqual(same, [a.id], a.id + ": shown once, cards " + same.join(" "));
  }
});
row("C3", "Court recent · 24 h drawer", "removed on the owner's word (2026-11-10, T1601-17 addition 3)", null);
row("C4", "Court Conductor: 1 mote per live agent, lamp ok / needs you, error pose < 10 min", "scene CEO (motes, lamp, pose) + CEO card Failed and Needs you", (X) => {
  const L = X.M.ceo.live;
  assert.deepStrictEqual([L.motes.length, L.lamp, X.M.ceo.pose], [live.length, "needs", "error"]);
  has(X.cards.orchestrator, "T8004", ago(subs.find((s) => s.id === "a8004").last) + " ago", "Needs you");
});
row("C5", "Court orchestrator button: name, rank, state, N working", "CEO card", (X) => {
  const c = X.cards.orchestrator; has(c, "DarkSaddler", "CEO");
  assert.ok(new RegExp(`working\\D{0,4}${live.length}\\b|\\b${live.length} working`).test(c.text), `CEO card does not say ${live.length} working (old Court: every live agent); rows ${c.rows.slice(0, 2).map((r) => r[0] + " = " + r[1]).join(", ")}`);
});
row("C7", "Court persistent: creature, name, state pill, next / on demand / always on, last run ago", "scene creature in its team room + staff card", (X) => {
  for (const r of members.filter((r) => r.state && (r.state !== "off" || r.kind === "on-demand"))) {
    const c = X.cards[r.id]; inScene(X, r.id); has(c, r.name);
    assert.strictEqual(c.st.includes("working"), r.state === "running", r.id + ": running");
    has(c, r.next ? "in " + until(r.next) : r.kind === "on-demand" ? "on demand" : "always on");
    if (r.last && r.last.end) has(c, ago(r.last.end) + " ago");
  }
});
row("C8", "Court claims board: who, note, paths (short, full on hover), empty text", "room card Held files of the owner's room (CEO card when no owner)", (X) => {
  const all = Object.values(X.cards);
  for (const c of F0.agents.claims.map(X.claimRow)) {
    const k = all.find((x) => x.rows.some((r) => r[0] === c.who));
    assert.ok(k, c.who + ": on no card"); has(k, c.note, ...c.paths.map((p) => p.short));
    for (const p of c.paths) assert.ok(k.text.includes(p.full) || k.titles.includes(p.full), `${c.who}: full path ${p.full} nowhere on the card (old: on hover)`);
  }
  assert.ok(all.some((x) => x.text.includes("no files held")), "empty text");
});
row("C10", "Dock and sub-tab: gold count of failed agents, green count of working", "Office sub-tab badge (PLAN §2.1: ticket 15)", (X) => {
  assert.strictEqual(X.badge, String(subs.filter((s) => s.state === "error").length), `Office sub-tab badge is "${X.badge}"`);
});
row("C11", "Court and Roster: 5 s refresh while someone works", "quiet 20 s while someone works: /api/agents every ≤ 6.5 s; /api/office ≥ 3 reads, gap ≤ 10 s (a cycle skips a read < 4.5 s old)", (X) => {
  const A = X.gaps["/api/agents"], O = X.gaps["/api/office"];
  assert.ok(A.n >= 4 && A.max <= 6500, "/api/agents: " + JSON.stringify(A)); assert.ok(O.n >= 3 && O.max <= 10000, "/api/office: " + JSON.stringify(O));
});
row("R1", "Roster band: N of M agents on · next up <name> in <time>", "band line", (X) => {
  assert.ok(new RegExp(`${up.length} of ${L.length} (agents|staff) on · next up (${q[0].id}|${q[0].name}) in ${until(q[0].next)}`).test(X.band), X.band);
});
row("R2", "Roster next runs: name, in <time>, progress bar, bad mark", "staff card Next run + bar; team room card Next runs (failed mark)", (X) => {
  for (const r of q) {
    const c = X.cards[r.id], t = X.cards["team-" + r.team], n = t.rows.find((x) => x[0] === r.name);
    has(c, "in " + until(r.next)); assert.ok(c.bar != null, r.id + ": no bar");
    assert.ok(n && n[1].includes("in " + until(r.next)), r.id + ": not in its team's Next runs");
    assert.strictEqual(/failed/.test(n[1]) || /bad/.test(n[2]), bad(r), r.id + ": bad mark");
  }
});
/* The last-run rows a Roster card showed: when and ago, exit, seconds, report or "no report yet". */
const lastRows = (c, r, pre) => { if (r.last && r.last.end) has(c, ago(r.last.end) + " ago"); else has(c, "never"); if (r.last && r.last.exit) has(c, r.last.exit); if (r.last && r.last.seconds) has(c, r.last.seconds + " s"); has(c, r.report || "no report yet"); if (pre && r.report) has(c, pre); };
row("R4", "Roster timer agent card: pill, schedule, countdown, next, last run, exit, seconds, report; gold when bad, dim when off", "staff card (every field) + scene pose", (X) => {
  for (const r of members.filter((r) => r.kind === "timer-agent")) {
    const c = X.cards[r.id]; inScene(X, r.id); has(c, r.name, r.on ? "scheduled" : "off", r.schedule); lastRows(c, r);
    if (r.on && r.next) { has(c, "in " + until(r.next)); assert.ok(c.bar != null, r.id + ": bar"); }
    assert.strictEqual(c.rows.some((x) => /bad/.test(x[2])), bad(r), r.id + ": gold"); assert.strictEqual(c.dim, !r.on, r.id + ": dim");
    assert.strictEqual(X.M.who[r.id].pose, r.state === "running" ? "working" : bad(r) ? "error" : "sleep", r.id + ": scene pose");
  }
});
row("R5", "Roster bash-timer card: pill, schedule, unit, next, last check, result, seconds, fallback last ran, fallback report", "staff card (every field)", (X) => {
  for (const r of members.filter((r) => r.kind === "bash-timer")) {
    const c = X.cards[r.id]; has(c, r.on ? (bad(r) ? "failed" : "on") : "down", r.schedule, r.runner.unit, "in " + until(r.next)); lastRows(c, r); if (r.fallback && r.report) assert.ok(c.rows.some((x) => /fallback report/i.test(x[0]) && x[1].includes(r.report)), r.id + ": fallback report");
    if (r.fallback) has(c, ago(r.fallback.end) + " ago");
  }
});
row("R6", "Roster service card: pill, always on, unit, state · sub, up since, tmux alive / missing", "staff card (every field)", (X) => {
  for (const r of members.filter((r) => r.kind === "service")) {
    const u = r.runner, c = X.cards[r.id];
    has(c, r.on ? "on" : bad(r) ? "failed" : r.health === "warn" ? "down" : "off", "always on", u.unit, u.state + (u.sub ? " · " + u.sub : ""), u.tmux + " · " + (u.tmux_alive ? "alive" : "missing"));
    if (r.on) has(c, ago(u.since) + " ago");
  }
});
row("R7", "Roster on-demand card (po-*, ci-fix): off, on demand, last run, exit, seconds, report", "po-*: the seat's card; ci-fix: staff card", (X) => {
  for (const s of seats.filter((s) => s.runner)) lastRows(X.cards[s.id], s.runner);
  const r = members.find((r) => r.id === "ci-fix"), c = X.cards[r.id]; has(c, "off", "on demand"); lastRows(c, r);
});
row("R8", "Roster hides `hello`", "staff.json `hidden` + lib/staff.assign", (X) => {
  assert.ok(X.hidden.hidden.includes("hello"), "staff.json hidden"); assert.ok(!JSON.stringify(X.hidden.teams).includes('"hello"'), "hello placed in a team");
});

/* The facts of one width: band, cards, scene anchors and model, the talk, the badge, the poll gaps, the slow, failing and stale reads. */
async function facts(b, w) {
  const X = { claimRow: (await import(pathToFileURL(path.join(__dirname, "..", "static", "next", "js", "claims.js")).href)).claimRow };
  const lib = path.join(__dirname, "..", "..", "lib");
  X.hidden = JSON.parse(execFileSync("python3", ["-c", "import sys,json;sys.path.insert(0,sys.argv[1]);import staff;d=staff.load();print(json.dumps({'hidden':d['hidden'],'teams':staff.assign(d['teams'],d['hidden'],[{'name':'hello'}],[])}))", lib], { encoding: "utf8" }));
  mode = ""; say = false;
  const { p, errs } = await open(b, w);
  X.band = await p.$eval(".office .band .bsum", (e) => e.textContent);
  X.T = Date.now();
  X.cards = await crawl(p);
  X.anchor = await p.evaluate((ids) => Object.fromEntries(ids.map((id) => [id, window.__office.project(id).ok])), Object.keys(X.cards));
  X.M = await p.evaluate(() => { const M = window.__drawn[window.__drawn.length - 1].M; return { ceo: { live: M.ceo.live, pose: M.ceo.pose }, rooms: M.rooms.map((r) => ({ id: r.id, team: r.team })), who: Object.fromEntries(Object.entries(M.who).map(([k, v]) => [k, { pose: v.pose }])) }; });
  X.nest = await p.evaluate(() => Object.fromEntries([...document.querySelectorAll(".office .olist .seat[data-seat]")].map((s) => { const up = s.closest("li").parentElement.closest("li"); return [s.dataset.seat, up && up.querySelector(":scope > .seat").dataset.seat]; })));
  X.badge = await p.$eval('#subs a[data-nav="org"]', (a) => (a.querySelector("i:not(.live)") || {}).textContent || "");
  await p.evaluate(() => document.querySelector('.office .olist [data-who="alpha"]').click());
  const t1 = Date.now(); say = true;
  X.talkCard = await p.waitForFunction(() => document.querySelector("#office-card .st.talking"), null, { timeout: 8000 }).then(() => true, () => false);
  X.talkScene = await p.evaluate((t1) => window.__drawn.some((d) => d.t >= t1 && d.M.who.alpha.pose === "talking"), t1);
  say = false;
  hits = [];
  await p.waitForTimeout(20000);
  X.gaps = Object.fromEntries(["/api/office", "/api/agents"].map((u) => { const T = hits.filter((h) => h[0] === u).map((h) => h[1]); return [u, { n: T.length, max: Math.max(...T.slice(1).map((t, i) => t - T[i])) }]; }));
  assert.deepStrictEqual(errs, [], "page errors");
  await p.context().close();
  for (const m of ["stale", "slow", "fail"]) {
    mode = m;
    const o = await open(b, w, false);
    if (m === "stale") { await o.p.waitForSelector(".office .band .bsum", { timeout: 20000 }); X.staleBand = await o.p.$eval(".office .band .bsum", (e) => e.textContent); }
    else X[m] = await o.p.waitForFunction((m) => { const t = (document.querySelector("#grid .nxs.skel p") || {}).textContent || ""; return (m === "slow" ? t.includes("reading") : t.includes("unreadable")) && t; }, m, { timeout: 15000 }).then((h) => h.jsonValue(), () => "");
    await o.p.context().close();
  }
  mode = "";
  return X;
}

/* The PARITY.md table from the results: one row per kept item; the dropped 4 named under it. */
function table(res) {
  const cell = (s) => String(s).replace(/\|/g, "/").replace(/\n/g, " ");
  const lines = ROWS.map((r) => {
    if (!r.fn) return `| ${r.id} | ${cell(r.item)} | ${cell(r.found)} | — | — | removed | Recent 24 h: not a loss (owner's word) |`;
    const v = res[r.id], ok = Object.values(v).every((x) => x === true), note = Object.entries(v).filter(([, x]) => x !== true).map(([w, x]) => w + ": " + x)[0] || "";
    return `| ${r.id} | ${cell(r.item)} | ${cell(r.found)} | ${v[1366] === true ? "ok" : "red"} | ${v[400] === true ? "ok" : "red"} | ${ok ? "pass" : "FAIL"} | ${cell(note).slice(0, 300)} |`;
  });
  return `# T1601-14 office parity (written by dashboard/tests/test_office_parity.js, ${new Date().toISOString().slice(0, 16)}Z)\n\n` +
    `Each kept item of PLAN §2.1, asserted from the old screens' source at 1366 and 400 px on one fixture (every field). A card counts as reached when a click opens it ` +
    `(list button, then chips and room lines on cards); its subject must stand in the 3D scene. Office is avatar-only (T1601-17): mapping in done/17.md.\n\n` +
    `| # | item (old screen) | where found in the office | 1366 | 400 | result | note |\n|---|---|---|---|---|---|---|\n${lines.join("\n")}\n\n` +
    `Dropped by PLAN §2.1, named and not tested: O3 owner card "You" (owner's order), C6 Court fold button (Reset view), C9 Court eye and rings (drawing), R3 Roster countdown rings (drawing; the number is the bar).\n`;
}

let base = "";
(async () => {
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ headless: true, args: GPU }), res = {};
  try {
    for (const w of [1366, 400]) {
      const X = await facts(b, w);
      setFix(X.T);
      for (const r of ROWS.filter((r) => r.fn)) {
        res[r.id] = res[r.id] || {};
        try { r.fn(X); res[r.id][w] = true; console.log(`ok ${w} ${r.id}`); } catch (e) { res[r.id][w] = (e.message || String(e)).split("\n")[0]; console.log(`FAIL ${w} ${r.id}: ${res[r.id][w]}`); }
      }
    }
  } finally { await b.close(); srv.close(); }
  fs.writeFileSync(OUT, table(res));
  const red = Object.entries(res).filter(([, v]) => Object.values(v).some((x) => x !== true)).map(([k]) => k);
  console.log(`${red.length ? "FAIL" : "ok"} test_office_parity: ${ROWS.filter((r) => r.fn).length - red.length} of ${ROWS.filter((r) => r.fn).length} kept rows green${red.length ? "; red: " + red.join(" ") : ""}; table ${OUT}`);
  process.exit(red.length ? 1 : 0);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
