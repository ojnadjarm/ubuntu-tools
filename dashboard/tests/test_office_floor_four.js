// Office four floors (T1757): CEO, Discord, Projects, Operations as data lines; the CEO's floor holds the CEO and the desk pool. No DOM, no WebGL.
// Run: node --test --test-reporter=tap tests/test_office_floor_four.js
"use strict";
const test = require("node:test");
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const JS = path.join(__dirname, "..", "static", "next", "js");
const BASE = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8"));
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);

/* The fixture with a Discord Crew team and the four floor lines of staff.json, bottom floor first. */
function four() {
  const P = JSON.parse(JSON.stringify(BASE)), ops = P.staff.find((t) => t.id === "operations");
  const liaison = ops.members.splice(ops.members.findIndex((m) => m.id === "discord-liaison"), 1)[0];
  P.staff.push({ id: "discord-crew", name: "Discord Crew", members: [liaison] });
  P.floors = [
    { id: "operations", name: "Operations", teams: ["operations", "quality", "improvement"], rest: ["team"] },
    { id: "projects", name: "Projects", teams: ["mooblox", "vass"], rest: ["po"] },
    { id: "discord", name: "Discord", teams: ["discord", "discord-crew"], head: "discord" },
    { id: "ceo", name: "CEO", teams: ["orchestrator"], head: "orchestrator" },
  ];
  return P;
}
const session = (pid, extra) => ({ seat: null, state: "working", since: 1794322500, pid, name: "agent-x", cwd: "~", rank: "Worker", ...extra });
const seat = (id, parent) => ({ id, name: id, rank: "PO", role: "po", parent, area: id, wake: "po-inbox" });
const on = (M, f) => [M.ceo, ...M.rooms, ...M.staff].filter((r) => r && r.floor === f).map((r) => r.id).sort();

test("the floors come from the data in its order, the CEO's floor on top, no main floor", async () => {
  const F = await load("office/floors.js");
  assert.deepStrictEqual(F.floors(four()), [{ id: "operations", name: "Operations" }, { id: "projects", name: "Projects" }, { id: "discord", name: "Discord" }, { id: "ceo", name: "CEO" }]);
  assert.strictEqual(F.home(four()), "ceo");
  assert.strictEqual(F.home(BASE), F.MAIN, "no line holds the CEO: the main floor");
});

test("the CEO's floor holds the CEO in the raised office and the desk pool only", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js");
  const M = build(four(), { needs: false }), C = F.view(M, "ceo");
  assert.strictEqual(C.ceo.id, "orchestrator");
  assert.strictEqual(C.ceo.kind, "ceo");
  assert.deepStrictEqual(C.rooms.map((r) => r.id), ["pool"]);
  assert.deepStrictEqual(C.staff, []);
  assert.strictEqual(M.who["pid1005"].room, "pool", "the orchestrator's own worker");
  assert.strictEqual(M.who["a0000000000000002"].room, "pool", "a sub-agent of the orchestrator");
});

test("each floor holds its teams: Discord with its head, Projects, Operations with Unassigned", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js");
  const M = build(four(), { needs: false });
  assert.deepStrictEqual(on(M, "discord"), ["discord", "mosaico", "team-discord-crew", "tiny-epic-narrator"]);
  assert.strictEqual(F.view(M, "discord").ceo.id, "discord");
  assert.deepStrictEqual(on(M, "projects"), ["mooblox", "vass"]);
  assert.strictEqual(F.view(M, "projects").ceo, null, "no head named: the raised office stays empty");
  assert.deepStrictEqual(on(M, "operations"), ["team-improvement", "team-operations", "team-quality", "team-unassigned"]);
  assert.deepStrictEqual(on(M, "ceo"), ["orchestrator", "pool"]);
});

test("a PO or team with no floor line lands on the rest floor, never on the CEO's", async () => {
  const { build } = await load("office/model.js");
  const P = four();
  P.seats.push(seat("newpo", "orchestrator"), seat("newmgr", "discord"), seat("sub", "newpo"));
  P.staff.push({ id: "labs", name: "Labs", members: [{ id: "lab-bot", name: "Lab", rank: "Staff", state: "running" }] });
  P.sessions.push(session(2001, { parent: null, started_by: "lab-bot" }), session(2002, { parent: null, started_by: "nobody-known" }));
  const M = build(P, { needs: false }), fl = (id) => [M.ceo, ...M.rooms, ...M.staff].find((r) => r && r.people.some((p) => p.id === id)).floor;
  assert.strictEqual(fl("newpo"), "projects");
  assert.strictEqual(fl("sub"), "projects", "its tree follows it");
  assert.strictEqual(fl("newmgr"), "discord", "under a listed seat: that seat's floor");
  assert.strictEqual(fl("lab-bot"), "operations");
  assert.strictEqual(fl("pid2001"), "operations", "a worker a new team's member starts");
  assert.strictEqual(fl("pid2002"), "ceo", "an unknown starter: the CEO's desk pool");
  const bare = four();
  bare.floors.forEach((f) => delete f.rest);
  bare.seats.push(seat("newpo", "orchestrator"));
  const B = build(bare, { needs: false });
  assert.strictEqual(B.rooms.find((r) => r.id === "newpo").floor, "ceo", "with no rest line the CEO's floor takes it");
});

test("an unknown or missing floor id falls back to the CEO's floor", async () => {
  const F = await load("office/floors.js");
  assert.strictEqual(F.pick(four(), "discord"), "discord");
  assert.strictEqual(F.pick(four(), "nope"), "ceo");
  assert.strictEqual(F.pick(four(), null), "ceo");
  assert.strictEqual(F.pick(four(), "main"), "ceo", "the old main id is gone with a CEO line");
  assert.strictEqual(F.pick(BASE, "nope"), F.MAIN);
});

test("the working count covers all four floors", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js");
  const P = four();
  P.sessions.push(session(2001, { parent: "mooblox", name: "T9101" }));
  const M = build(P, { needs: false }), n = F.working(M, F.floors(P));
  assert.deepStrictEqual(Object.keys(n), ["operations", "projects", "discord", "ceo"]);
  const count = (f) => [M.ceo, ...M.rooms, ...M.staff].filter((r) => r && r.floor === f).flatMap((r) => r.people).filter((p) => p.pose === "working").length;
  for (const f of Object.keys(n)) assert.strictEqual(n[f], count(f), f);
  assert.ok(n.projects >= 1);
});
