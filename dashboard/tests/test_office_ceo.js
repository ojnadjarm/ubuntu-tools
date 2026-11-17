// The Switchboard (T1758): the CEO floor's own room. Cables per floor, sheets, the owner's lamp, capsule events, the plan and the chunks. No DOM, no WebGL.
// Run: node --test --test-reporter=tap tests/test_office_ceo.js
"use strict";
const test = require("node:test");
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.join(__dirname, ".."), JS = path.join(ROOT, "static", "next", "js");
const BASE = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8"));
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const NOW = Date.parse("2026-11-10T15:00:00Z");

/* The fixture on five floors with nobody running. */
function calm() {
  const P = JSON.parse(JSON.stringify(BASE));
  P.floors = [
    { id: "operations", name: "Operations", teams: ["operations", "quality", "improvement"], rest: ["team"] },
    { id: "work", name: "Work projects", teams: ["vass"], deck: false },
    { id: "personal", name: "Personal projects", teams: ["mooblox"], rest: ["po"], deck: false },
    { id: "discord", name: "Discord", teams: ["discord"], head: "discord" },
    { id: "ceo", name: "CEO", teams: ["orchestrator"], head: "orchestrator" },
  ];
  P.sessions = P.sessions.filter((s) => s.seat === "orchestrator");
  P.agents.subagents = [];
  return P;
}
const sub = (id, label, state, started) => ({ id, label, type: "worker", started, last: started, state, doing: "x", report: "" });
const worker = (pid, seat, n) => ({ seat: null, parent: seat, state: "working", since: 1794322500 + pid, pid, name: "T" + n, cwd: "~", rank: "Worker", started_by: seat + "-T" + n });
const ink = (t) => ({ w: t.length * 7 + 2, h: 14, runs: [...t].flatMap((c, i) => (c === " " ? [] : [4, 7, 10].map((y) => [1 + i * 7, 6 + i * 7, y]))) });

async function kit() {
  const { decode } = await load("office/kit.js");
  return decode(JSON.parse(fs.readFileSync(path.join(ROOT, "static", "next", "office", "kit.json"), "utf8")));
}

test("idle: one column per floor, top floor first, bare jacks, no sheets, lamp off", async () => {
  const { build } = await load("office/model.js"), D = await load("office/ceo/desk.js");
  const M = build(calm(), { now: NOW, needs: false }), cols = D.columns(M.ceo.desk);
  assert.deepStrictEqual(cols.map((c) => [c.n, c.id]), [[5, "ceo"], [4, "discord"], [3, "personal"], [2, "work"], [1, "operations"]]);
  assert.deepStrictEqual(cols.map((c) => c.jacks.length), [0, 0, 0, 0, 0]);
  assert.strictEqual(D.sheets(M.ceo.desk).length, 0);
  assert.strictEqual(D.lampOn(M.ceo.live), false);
});

test("three tickets on two floors: a cable per ticket in its floor's column, a sheet per ticket, the newest last", async () => {
  const { build } = await load("office/model.js"), D = await load("office/ceo/desk.js"), P = calm();
  P.agents.subagents = [sub("a1", "T9001 build", "working", "2026-11-10T14:40:00Z"), sub("a2", "T9002 fix", "working", "2026-11-10T14:55:00Z")];
  P.sessions.push(worker(3001, "mooblox", 9003));
  const M = build(P, { now: NOW, needs: false }), cols = D.columns(M.ceo.desk), by = Object.fromEntries(cols.map((c) => [c.id, c.jacks.map((t) => t.id)]));
  assert.deepStrictEqual([by.ceo.sort(), by.personal.length, by.discord, by.work, by.operations], [["a1", "a2"], 1, [], [], []]);
  assert.ok(M.ceo.desk.tickets.every((t) => t.state === "working"));
  const S = D.sheets(M.ceo.desk);
  assert.strictEqual(S.length, 3);
  assert.strictEqual(S[0].id, "a1", "oldest at the bottom");
  assert.strictEqual(D.sheets(M.ceo.desk, 2).length, 2);
});

test("a failed sub-agent is a failing ticket in the CEO's column; done ones are gone", async () => {
  const { build } = await load("office/model.js"), D = await load("office/ceo/desk.js"), P = calm();
  P.agents.subagents = [sub("a1", "T9001 build", "working", "2026-11-10T14:40:00Z"), sub("a2", "T9002 fix", "error", "2026-11-10T14:57:00Z"), sub("a3", "T9003 old", "done", "2026-11-10T14:00:00Z")];
  const M = build(P, { now: NOW, needs: false }), T = M.ceo.desk.tickets;
  assert.deepStrictEqual(T.map((t) => [t.id, t.state, t.floor]), [["a1", "working", "ceo"], ["a2", "failing", "ceo"]]);
  assert.strictEqual(D.columns(M.ceo.desk)[0].jacks.length, 2);
});

test("the owner's lamp follows the needs verdict only", async () => {
  const { build } = await load("office/model.js"), D = await load("office/ceo/desk.js");
  assert.strictEqual(D.lampOn(build(calm(), { now: NOW, needs: true }).ceo.live), true);
  assert.strictEqual(D.lampOn(build(calm(), { now: NOW, needs: false }).ceo.live), false);
  assert.strictEqual(D.lampOn(undefined), false);
});

test("capsule events: out when a ticket starts, back when it ends or fails, none when nothing moved", async () => {
  const { build, diff } = await load("office/model.js"), D = await load("office/ceo/desk.js"), P0 = calm(), P1 = calm(), P2 = calm(), P3 = calm();
  P1.agents.subagents = [sub("a1", "T9001 build", "working", "2026-11-10T14:40:00Z")];
  P2.agents.subagents = [sub("a1", "T9001 build", "error", "2026-11-10T14:58:00Z")];
  P3.agents.subagents = [sub("a1", "T9001 build", "done", "2026-11-10T14:40:00Z")];
  const [M0, M1, M2, M3] = [P0, P1, P2, P3].map((P) => build(P, { now: NOW, needs: false }));
  assert.deepStrictEqual(D.events(M0.ceo.desk, M1.ceo.desk), [{ id: "a1", dir: "out", floor: "ceo" }]);
  assert.deepStrictEqual(D.events(M1.ceo.desk, M3.ceo.desk), [{ id: "a1", dir: "back", floor: "ceo" }]);
  assert.deepStrictEqual(D.events(M1.ceo.desk, M2.ceo.desk), [{ id: "a1", dir: "back", floor: "ceo" }]);
  assert.deepStrictEqual(D.events(M2.ceo.desk, M0.ceo.desk), [], "a failed ticket leaving sends nothing");
  assert.deepStrictEqual(D.events(null, M1.ceo.desk), []);
  assert.deepStrictEqual(diff(M0, M1).events, [{ id: "a1", dir: "out", floor: "ceo" }]);
  assert.ok(!("events" in diff(M1, M1)) && !("events" in diff(null, M1)));
  assert.ok(diff(M0, M1).rooms.includes(M1.ceo.id), "a new ticket rebuilds the CEO's chunk");
});

test("the CEO's floor is the Switchboard: own plan, no mezzanine; other floors and a one-floor office keep the loft", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), L = await load("office/layout.js"), C = await load("office/ceo/plan.js"), P = calm();
  const M = build(P, { now: NOW, needs: false }), V = F.view(M, "ceo", P), p = L.plan(V);
  assert.strictEqual(V.shell, "ceo");
  assert.deepStrictEqual(Object.keys(p.cells).sort(), ["orchestrator", "pool"]);
  assert.strictEqual(p.cells.orchestrator.y - p.cells.pool.y, C.STEP, "the pit is one step lower");
  assert.ok(C.STEP > 0 && C.STEP < 0.3);
  for (const f of ["discord", "personal", "work", "operations"]) assert.strictEqual(F.view(M, f, P).shell, undefined, f);
  const one = JSON.parse(JSON.stringify(BASE)); delete one.floors;
  const M1 = build(one, { now: NOW, needs: false });
  assert.strictEqual(F.view(M1, F.home(one), one).shell, undefined);
  const desks = Array.from({ length: C.SLOTS }, (_, k) => C.desk(k));
  for (const d of desks) {
    assert.ok(d.z > C.EDGE && d.x > 0.4 && d.x < C.ROOM.w - 0.4 && d.z < C.ROOM.d - 0.3, "desk in the pit");
    const to = Math.atan2(C.TABLE.x - d.x, C.TABLE.z - d.z);
    assert.ok(Math.abs(Math.atan2(Math.sin(d.r - to), Math.cos(d.r - to))) < 1e-6, "desk faces the table");
  }
  for (let i = 0; i < desks.length; i++) for (let j = 0; j < i; j++) assert.ok(Math.hypot(desks[i].x - desks[j].x, desks[i].z - desks[j].z) > 0.8, "desks apart");
});

test("chunks: three, finite, three rails, a pilot and a cable per ticket, the amber lamp only when needed, a night flip is colour-only", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), L = await load("office/layout.js"), I = await load("office/build/index.js"), { THEME } = await load("office/theme.js"), K = await kit();
  const make = (P, needs) => { const M = build(P, { now: NOW, needs }), V = F.view(M, "ceo", P), p = L.plan(V); return { V, p, c: Object.fromEntries([I.HALL, ...Object.keys(p.cells)].map((id) => [id, I.chunk(id, V, p, THEME, K, ink)])) }; };
  const amber = (c) => c.lamps.filter((l) => l.col && l.col[0] > 0.9 && l.col[2] < 0.5).length, busy = calm();
  busy.agents.subagents = [sub("a1", "T9001 build", "working", "2026-11-10T14:40:00Z"), sub("a2", "T9002 fix", "working", "2026-11-10T14:55:00Z")];
  const idle = make(calm(), false), run = make(busy, false), need = make(calm(), true);
  assert.deepStrictEqual(Object.keys(idle.c), ["hall", "orchestrator", "pool"]);
  for (const c of Object.values(run.c)) assert.ok(c.position.length > 0 && c.position.every(Number.isFinite) && c.color.every(Number.isFinite));
  assert.strictEqual(idle.c.orchestrator.rails.length, 3);
  assert.ok(idle.c.orchestrator.rails.every((r) => r.a[1] > r.b[1]), "rails run down");
  assert.strictEqual(run.c.orchestrator.lamps.length - idle.c.orchestrator.lamps.length, 2 * 2 + 1, "two lamps a cable, one over the sheets");
  assert.ok(run.c.orchestrator.position.length > idle.c.orchestrator.position.length);
  assert.deepStrictEqual([amber(idle.c.orchestrator), amber(need.c.orchestrator)], [0, 2]);
  assert.deepStrictEqual(idle.c.orchestrator.actors.map((a) => [a.id, a.role]), [["orchestrator", "ceo"]]);
  assert.strictEqual(run.c.pool.actors.length, 2, "both sub-agents sit in the pit");
  assert.ok(run.c.pool.actors.every((a) => a.z > run.p.cells.orchestrator.d && a.z > run.c.orchestrator.actors[0].z), "the workers sit in the pit, in front of the table");
  const all = [...Object.values(idle.c), ...Object.values(run.c)];
  assert.ok(Math.max(...all.map((c) => c.position.length / 3)) < 20000, "each chunk under 20,000 vertices");
  for (const [id, c] of Object.entries(run.c)) assert.strictEqual(c.relight({ ...run.V, night: !run.V.night }, run.p), true, id);
  for (const f of fs.readdirSync(path.join(JS, "office", "build", "ceo")).map((f) => "office/build/ceo/" + f).concat(["office/ceo/desk.js", "office/ceo/plan.js", "office/gl/capsule.js", "office/diff.js"]))
    assert.ok(fs.statSync(path.join(JS, f)).size < 12000, f);
});
