// Office pure core (T1601-02): time.js, model.js (build, diff), layout.js (plan), fields.js (card), seats.js, on the
// shared fixture tests/fixtures/office.json. No DOM, no WebGL.
// Run: node tests/test_office_model.js
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.join(__dirname, "..");
const JS = path.join(ROOT, "static", "next", "js");
const P = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8"));
const NOW = Date.parse("2026-11-10T15:00:00Z");
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const copy = () => JSON.parse(JSON.stringify(P));
let n = 0;
const ok = (name, fn) => { fn(); n++; console.log("ok " + n + " " + name); };

(async () => {
  const T = await load("office/time.js"), Mo = await load("office/model.js"), L = await load("office/layout.js");
  const F = await load("office/fields.js"), S = await load("seats.js");
  const M = Mo.build(P);

  ok("seats.js is the one source of seatState, titled, dmOf: org.js re-exports them and holds no copy", () => {
    const org = fs.readFileSync(path.join(JS, "screens", "org.js"), "utf8"), mine = fs.readFileSync(path.join(JS, "seats.js"), "utf8");
    assert.ok(/export \{ seatState, titled, dmOf \} from "\.\.\/seats\.js";/.test(org), "org.js re-exports them from ../seats.js");
    for (const head of ["export function seatState", "export const titled", "export const dmOf"]) {
      assert.ok(mine.includes(head), "seats.js defines " + head);
      assert.ok(!org.includes(head) && !org.includes(head.replace("export ", "")), "org.js holds no copy of " + head);
    }
    assert.strictEqual(S.titled({ name: "Bramble", rank: "Manager" }), "Bramble · Manager");
    assert.strictEqual(S.dmOf("vass"), "dm-owner--vass");
    assert.strictEqual(S.seatState({ id: "vass" }, P.sessions), "yours");
  });

  ok("ago, until, progress, took", () => {
    assert.strictEqual(T.ago(NOW / 1000 - 300, NOW), "5 min");
    assert.strictEqual(T.ago("2026-11-10T12:00:00Z", NOW), "3.0 h");
    assert.strictEqual(T.ago("2026-11-07T15:00:00Z", NOW), "3 d");
    assert.strictEqual(T.ago("", NOW), "—");
    assert.strictEqual(T.until("2026-11-10T15:20:00Z", NOW), "20 min");
    assert.strictEqual(T.until("2026-11-10T20:00:00Z", NOW), "5 h");
    assert.strictEqual(T.until("2026-11-14T15:00:00Z", NOW), "4 d");
    assert.strictEqual(T.until("", NOW), "—");
    assert.strictEqual(T.progress("2026-11-10T14:00:00Z", "2026-11-10T16:00:00Z", NOW), 50);
    assert.strictEqual(T.progress("2026-11-10T14:00:00Z", "2026-11-10T14:30:00Z", NOW), 100);
    assert.strictEqual(T.progress("", "2026-11-10T16:00:00Z", NOW), 0);
    assert.strictEqual(T.took("44"), "44 s");
    assert.strictEqual(T.took(""), "—");
  });

  ok("no owner room; the CEO on its own; rooms in team order, the pool last", () => {
    assert(!M.who.owner && !M.rooms.some((r) => r.id === "owner"));
    assert.strictEqual(M.ceo.kind, "ceo");
    assert.strictEqual(M.ceo.id, "orchestrator");
    assert.deepStrictEqual(M.rooms.map((r) => r.id), ["mooblox", "vass", "discord", "tiny-epic-narrator", "mosaico", "pool"]);
    assert.deepStrictEqual(M.rooms.map((r) => r.team), [0, 1, 2, 2, 2, -1]);
    assert.deepStrictEqual(M.staff.map((r) => r.id), ["team-operations", "team-quality", "team-improvement", "team-unassigned"]);
    assert.deepStrictEqual(M.staff.map((r) => r.team), [3, 4, 5, 6]);
    assert.strictEqual(M.who["night-relay"].room, "team-unassigned");
  });

  ok("a pid row of agents.subagents and the session with that pid make 1 person", () => {
    const all = [M.ceo, ...M.rooms, ...M.staff].flatMap((r) => r.people);
    const hits = all.filter((p) => p.id === "pid1005" || (p.raw.session && p.raw.session.pid === 1005));
    assert.strictEqual(hits.length, 1);
    assert.deepStrictEqual([hits[0].id, hits[0].kind, hits[0].room, hits[0].name], ["pid1005", "agent", "pool", "T9002"]);
    assert.strictEqual(hits[0].raw.session.cwd, "~/agents");
    assert.strictEqual(M.who.pid1005, hits[0]);
  });

  ok("working sub-agents of another type are the pool's people; ended ones are not", () => {
    const pool = M.rooms.find((r) => r.kind === "pool");
    assert.deepStrictEqual(pool.people.map((p) => p.id).sort(), ["a0000000000000002", "pid1005"]);
    assert(!M.who.a0000000000000003);
  });

  ok("workers sit in the room of the seat that started them", () => {
    const ten = M.rooms.find((r) => r.id === "tiny-epic-narrator");
    assert.deepStrictEqual(ten.people.map((p) => [p.id, p.kind]), [["tiny-epic-narrator", "seat"], ["pid1003", "worker"], ["pid1004", "worker"]]);
    assert.strictEqual(ten.busy, 2);
    assert.strictEqual(M.who.pid1004.pose, "idle");
  });

  ok("poses: running → working, health bad → error, protected → state only, anything else → sleep", () => {
    assert.strictEqual(M.who.maintenance.pose, "working");
    assert.strictEqual(M.who.sentinel.pose, "error");
    assert.strictEqual(M.who["code-review"].pose, "sleep");
    assert.strictEqual(M.who.toolsmith.pose, "sleep");
    assert.strictEqual(M.who.orchestrator.pose, "working");
    assert.strictEqual(M.who.mooblox.pose, "sleep");
    const v = M.who.vass;
    assert.strictEqual(v.state, "yours");
    assert.strictEqual(v.pose, "idle");
    assert.deepStrictEqual(Object.keys(v.raw.session).sort(), ["seat", "since", "state"]);
    assert.strictEqual(M.rooms.find((r) => r.id === "vass").awake, true);
  });

  ok("more counts the people beyond the cell's slots", () => {
    const Q = copy();
    for (let i = 0; i < 9; i++) Q.sessions.push({ seat: null, state: "idle", since: 1794322000, pid: 2000 + i, parent: "mosaico", name: "w" + i, cwd: "~", started_by: "x" });
    const r = Mo.build(Q).rooms.find((x) => x.id === "mosaico");
    assert.strictEqual(Mo.SLOTS, 6);
    assert.strictEqual(r.people.length, 10);
    assert.strictEqual(r.more, 3);
    assert.strictEqual(M.rooms.find((x) => x.id === "mosaico").more, 0);
  });

  ok("night only when nobody is awake", () => {
    assert.strictEqual(M.night, false);
    const Q = copy();
    Q.sessions = []; Q.agents.subagents = Q.agents.subagents.filter((s) => s.state !== "working");
    Q.staff.forEach((t) => t.members.forEach((m) => { m.state = "idle"; m.health = "ok"; }));
    assert.strictEqual(Mo.build(Q).night, true);
  });

  ok("line: sessions, working, staff on of all, soonest next", () => {
    assert.deepStrictEqual(M.line, { sessions: 6, working: 4, on: 11, of: 13, soon: { name: "Sorrel", next: "2026-11-10T16:02:00+01:00" } });
  });

  ok("panels: next soonest first, running, no recent, sessions with a protected row, claims", () => {
    const nx = M.panels.next.map((r) => Date.parse(r.next));
    assert.strictEqual(nx.length, 10);
    assert.deepStrictEqual(nx, [...nx].sort((a, b) => a - b));
    assert.strictEqual(M.panels.next[1].bad, true);
    assert.deepStrictEqual(M.panels.running.map((r) => r.ticket), ["T9002", "T9003-04"]);
    assert.strictEqual(M.panels.running[1].label, "office renderer");
    assert.ok(!("recent" in M.panels), "Recent 24 h is gone (owner 2026-11-10)");
    const prot = M.panels.sessions.find((r) => r.protected);
    assert.deepStrictEqual(prot, { id: "vass", protected: true, session: "protected project", seat: "Thistle · Product Owner", folder: "hidden", state: "idle", by: "—", since: 1794322086 });
    assert.strictEqual(M.panels.sessions.length, 6);
    assert.strictEqual(M.panels.sessions.find((r) => r.id === "pid1003").seat, "under Bramble · Manager");
    assert.deepStrictEqual(M.panels.claims[0].who, "T9001");
    assert.deepStrictEqual(M.panels.claims[0].note, "core · 2026-11-10 16:21");
    assert.deepStrictEqual(M.panels.claims[0].paths.map((p) => p.short), ["dashboard/static/next/js/office/model.js", "dashboard/tests/test_office_model.js"]);
    assert.strictEqual(M.error, "");
    assert.strictEqual(Mo.build({ ...copy(), error: "org unreadable" }).error, "org unreadable");
  });

  ok("ticket and rest split a label", () => {
    assert.strictEqual(Mo.ticket("T1601-04 office renderer"), "T1601-04");
    assert.strictEqual(Mo.rest("T1601-04 office renderer"), "office renderer");
  });

  ok("diff: equal → empty", () => {
    assert.deepStrictEqual(Mo.diff(M, Mo.build(copy())), { layout: false, night: false, rooms: [], people: [], panels: [], line: false });
  });

  ok("diff: 1 seat state → 1 room", () => {
    const Q = copy();
    Q.sessions.push({ seat: "mooblox", state: "working", since: 1794322700, pid: 3001, parent: "orchestrator", name: "agent-po-mooblox", cwd: "~/agents/po-mooblox", started_by: "po-mooblox" });
    const d = Mo.diff(M, Mo.build(Q));
    assert.deepStrictEqual(d.rooms, ["mooblox"]);
    assert.deepStrictEqual(d.people, ["mooblox"]);
    assert.strictEqual(d.layout, false);
    assert.strictEqual(d.night, false);
    assert(d.line && d.panels.includes("sessions"));
  });

  ok("diff: worker added → 1 room", () => {
    const Q = copy();
    Q.sessions.push({ seat: null, state: "working", since: 1794322700, pid: 3002, parent: "mosaico", name: "agent-T9005", cwd: "~", started_by: "T9005", rank: "Worker" });
    const d = Mo.diff(M, Mo.build(Q));
    assert.deepStrictEqual(d.rooms, ["mosaico"]);
    assert.deepStrictEqual(d.people, ["pid3002"]);
    assert.strictEqual(d.layout, false);
  });

  ok("diff: seat added → layout", () => {
    const Q = copy();
    Q.seats.push({ id: "newbie", name: "Fern", rank: "Manager", role: "manager", parent: "discord", area: "New", about: "", wake: "po-inbox" });
    const d = Mo.diff(M, Mo.build(Q));
    assert.strictEqual(d.layout, true);
    assert(d.rooms.includes("newbie"));
  });

  ok("diff: last one asleep → night", () => {
    const quiet = (Q) => { Q.agents.subagents = Q.agents.subagents.filter((s) => s.state !== "working"); Q.staff.forEach((t) => t.members.forEach((m) => { m.state = "idle"; m.health = "ok"; })); return Q; };
    const A = quiet(copy()); A.sessions = [{ seat: "mosaico", state: "idle", since: 1794322000, pid: 4000, parent: "discord", name: "m", cwd: "~", started_by: "x" }];
    const B = quiet(copy()); B.sessions = [];
    const a = Mo.build(A), b = Mo.build(B), d = Mo.diff(a, b);
    assert.strictEqual(a.night, false);
    assert.strictEqual(b.night, true);
    assert.strictEqual(d.night, true);
    assert.strictEqual(d.layout, false);
  });

  ok("diff: from nothing → everything", () => {
    const d = Mo.diff(null, M);
    assert.strictEqual(d.layout, true);
    assert.strictEqual(d.rooms.length, 1 + M.rooms.length + M.staff.length);
  });

  const fake = (k) => ({ ceo: { id: "orchestrator", kind: "ceo", people: [] }, staff: [{ id: "team-a", kind: "team", people: [] }],
    rooms: [...Array.from({ length: k }, (_, i) => ({ id: "r" + i, kind: "seat", people: [] })), { id: "pool", kind: "pool", people: [] }] });
  const overlap = (a, b) => Math.abs(a.x - b.x) * 2 < a.w + b.w && Math.abs(a.z - b.z) * 2 < a.d + b.d;

  ok("plan: a cell per room, none overlap, all inside the hall, for 0, 7 and 30 rooms", () => {
    for (const k of [0, 7, 30]) {
      const m = fake(k), p = L.plan(m), ids = [m.ceo, ...m.rooms, ...m.staff].map((r) => r.id), C = Object.values(p.cells);
      assert.deepStrictEqual(Object.keys(p.cells).sort(), ids.sort(), k + " rooms: one cell each");
      for (let i = 0; i < C.length; i++) for (let j = i + 1; j < C.length; j++) assert(!overlap(C[i], C[j]), k + " rooms: cells " + i + " and " + j + " overlap");
      for (const c of C) assert(c.x - c.w / 2 >= 0 && c.x + c.w / 2 <= p.hall.w && c.z - c.d / 2 >= 0 && c.z + c.d / 2 <= p.hall.d, "inside the hall");
      assert(p.hall.h > 0 && typeof p.home.az === "number" && typeof p.home.azTall === "number");
    }
    const p = L.plan(M);
    assert.strictEqual(p.cells.mooblox.slots, Mo.SLOTS);
    assert.strictEqual(p.cells.orchestrator.slots, 0);
    assert.strictEqual(L.plan(fake(30)).hall.d > L.plan(fake(7)).hall.d, true);
  });

  const shape = (c) => {
    for (const k of ["title", "rank", "sub"]) assert.strictEqual(typeof c[k], "string", k);
    assert(c.state && typeof c.state.pose === "string" && typeof c.state.text === "string");
    assert(Array.isArray(c.rows) && c.rows.every((r) => Array.isArray(r) && r.length >= 2 && r.length <= 3));
    assert(Array.isArray(c.actions));
    if ("bar" in c) assert(c.bar >= 0 && c.bar <= 100);
  };
  const rowOf = (c, label) => (c.rows.find((r) => r[0] === label) || [])[1];

  ok("card for each kind", () => {
    assert.deepStrictEqual(Object.keys(F.CARDS).sort(), ["agent", "ceo", "pool", "seat", "staff", "team", "worker"]);
    const ceo = F.card(M.who.orchestrator, NOW); shape(ceo);
    assert.strictEqual(ceo.title, "DarkSaddler");
    assert.strictEqual(rowOf(ceo, "Agents"), "2 working");
    assert.deepStrictEqual(ceo.actions, [{ label: "Message DarkSaddler", href: "#chat?ch=dm-orchestrator--owner" }]);
    const seat = F.card(M.who["tiny-epic-narrator"], NOW); shape(seat);
    assert.deepStrictEqual([seat.title, seat.rank, seat.sub], ["Bramble", "Manager", "Tiny Epic Narrator"]);
    assert.strictEqual(seat.state.text, "Now working · 30 min");
    assert.strictEqual(rowOf(seat, "Workers"), "2 workers, 1 working");
    assert.strictEqual(seat.actions[0].href, "#chat?ch=dm-owner--tiny-epic-narrator");
    const v = F.card(M.who.vass, NOW); shape(v);
    assert.strictEqual(v.state.text, "Now yours");
    const w = F.card(M.who.pid1003, NOW); shape(w);
    assert.deepStrictEqual([w.title, w.rank, w.sub], ["agent-T9001", "Worker", "Works for Bramble"]);
    assert.deepStrictEqual(w.actions, []);
    const a = F.card(M.who.a0000000000000002, NOW); shape(a);
    assert.deepStrictEqual([a.title, a.sub], ["T9003-04", "office renderer"]);
    assert.strictEqual(rowOf(a, "Now"), "Builds the stage");
    const st = F.card(M.who.sentinel, NOW); shape(st);
    assert.deepStrictEqual([st.title, st.rank], ["Ember", "Sentinel"]);
    assert.strictEqual(st.sub, "sentinel · Operations");
    assert.deepStrictEqual(st.actions, []);
    assert.strictEqual(rowOf(st, "Schedule"), "every 15 min");
    assert.deepStrictEqual(st.rows.find((r) => r[0] === "Result"), ["Result", "1", "bad"]);
    assert.strictEqual(rowOf(st, "Took"), "3 s");
    assert(st.bar >= 0 && st.bar <= 100);
    const off = F.card(M.who.toolsmith, NOW); shape(off);
    assert(!("bar" in off));
    const t = F.card(M.who["team-operations"], NOW); shape(t);
    assert.deepStrictEqual(t.roll, ["sentinel-digest", "maintenance", "moodle-keeper", "fleet-backup", "sentinel", "discord-liaison"]);
    const pool = F.card(M.who.pool, NOW); shape(pool);
    assert.strictEqual(pool.roll.length, 2);
    for (const id of Object.keys(M.who)) shape(F.card(M.who[id], NOW));
  });

  ok("pure: no DOM, no WebGL, no word with rain, under 12 KB", () => {
    for (const f of ["office/time.js", "office/model.js", "office/layout.js", "office/fields.js", "seats.js"]) {
      const s = fs.readFileSync(path.join(JS, f), "utf8");
      assert(s.length < 12000, f + " is " + s.length + " B");
      assert(!/\b(document|window|WebGL|three)\b/.test(s), f + " touches the DOM or WebGL");
      if (f.startsWith("office/")) assert(!/rain/i.test(s), f + " has a word with rain");
    }
  });

  console.log("all " + n + " passed");
})().catch((e) => { console.error("FAIL", e.message); process.exit(1); });
