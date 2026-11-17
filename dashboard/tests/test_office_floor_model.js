// Office floors (T1755): office/floors.js + model.js + layout.js on the shared fixture with a floors line. No DOM, no WebGL.
// Run: node --test tests/test_office_floor_model.js
"use strict";
const test = require("node:test");
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const JS = path.join(__dirname, "..", "static", "next", "js");
const BASE = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8"));
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);

/* The fixture with the liaison moved to a Discord Crew team and the Discord floor line. */
function withFloors() {
  const P = JSON.parse(JSON.stringify(BASE)), ops = P.staff.find((t) => t.id === "operations");
  const liaison = ops.members.splice(ops.members.findIndex((m) => m.id === "discord-liaison"), 1)[0];
  P.staff.push({ id: "discord-crew", name: "Discord Crew", members: [liaison] });
  P.floors = [{ id: "discord", name: "Discord", teams: ["discord", "discord-crew"] }];
  return P;
}
const session = (pid, extra) => ({ seat: null, state: "working", since: 1794322500, pid, name: "agent-x", cwd: "~", rank: "Worker", ...extra });
const floorOf = (M, id) => [M.ceo, ...M.rooms, ...M.staff].find((r) => r && r.people.some((p) => p.id === id)).floor;

test("rooms stand on the floor their team's line names, the rest on the main floor", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js");
  const M = build(withFloors(), { needs: false });
  const on = (f) => [M.ceo, ...M.rooms, ...M.staff].filter((r) => r && r.floor === f).map((r) => r.id).sort();
  assert.deepStrictEqual(on("discord"), ["discord", "mosaico", "team-discord-crew", "tiny-epic-narrator"]);
  assert.deepStrictEqual(on(F.MAIN), ["mooblox", "orchestrator", "pool", "team-improvement", "team-operations", "team-quality", "team-unassigned", "vass"]);
  assert.deepStrictEqual(F.floors(withFloors()).map((f) => f.id), ["main", "discord"]);
});

test("one floor's view holds only its rooms; the CEO stays on the main floor; the plan has a cell for each", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), L = await load("office/layout.js");
  const M = build(withFloors(), { needs: false }), D = F.view(M, "discord"), A = F.view(M, F.MAIN);
  assert.strictEqual(D.ceo, null);
  assert.ok(A.ceo && A.ceo.id === "orchestrator");
  assert.deepStrictEqual(Object.keys(L.plan(D).cells).sort(), ["discord", "mosaico", "team-discord-crew", "tiny-epic-narrator"]);
  assert.ok(!Object.keys(L.plan(A).cells).some((id) => ["discord", "mosaico", "team-discord-crew"].includes(id)));
  assert.strictEqual(M.who["mosaico"].room, "mosaico", "cards still find every person on any floor");
});

test("a worker a Discord manager starts lands on the Discord floor; a non-Discord one never does", async () => {
  const { build } = await load("office/model.js");
  const P = withFloors();
  P.sessions.push(session(2001, { parent: "mosaico", name: "T9101" }), session(2002, { parent: "mooblox", name: "T9102" }));
  P.sessions.push(session(2003, { parent: null, started_by: "discord-liaison" }), session(2004, { parent: null, started_by: "discord-liaison-job-7" }));
  P.sessions.push(session(2005, { parent: null, started_by: "toolsmith" }), session(2006, { parent: null, started_by: "discord-liaisonx" }));
  const M = build(P, { needs: false });
  assert.strictEqual(floorOf(M, "pid2001"), "discord");
  assert.strictEqual(floorOf(M, "pid1003"), "discord", "the fixture's tiny-epic-narrator worker");
  assert.strictEqual(floorOf(M, "pid2002"), "main");
  assert.strictEqual(floorOf(M, "pid2003"), "discord");
  assert.strictEqual(M.who["pid2003"].room, "pool-discord");
  assert.strictEqual(floorOf(M, "pid2004"), "discord");
  assert.strictEqual(floorOf(M, "pid2005"), "main");
  assert.strictEqual(floorOf(M, "pid2006"), "main", "a longer id is not the liaison");
  assert.strictEqual(floorOf(M, "pid1005"), "main", "the orchestrator's own worker");
  assert.strictEqual(floorOf(M, "a0000000000000002"), "main", "a sub-agent of the orchestrator");
  assert.strictEqual(M.who["pool-discord"].kind, "pool");
});

test("the count names the people working on each floor", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js");
  const P = withFloors();
  P.sessions.push(session(2001, { parent: "mosaico", name: "T9101" }), session(2002, { parent: "mosaico", name: "T9102", state: "idle" }));
  const M = build(P, { needs: false }), n = F.working(M, F.floors(P));
  const count = (f) => [M.ceo, ...M.rooms, ...M.staff].filter((r) => r && r.floor === f).flatMap((r) => r.people).filter((p) => p.pose === "working").length;
  assert.deepStrictEqual(n, { main: count("main"), discord: count("discord") });
  assert.ok(n.discord >= 3, "tiny-epic-narrator, its T9001 and mosaico's T9101");
  const before = n.discord;
  P.sessions.push(session(2003, { parent: "mosaico", name: "T9103" }));
  assert.strictEqual(F.working(build(P, { needs: false }), F.floors(P)).discord, before + 1);
});

test("a third floor is one data line; without floors every room is on the main floor", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js");
  const P = withFloors();
  P.floors.push({ id: "labs", name: "Labs", teams: ["mooblox"] });
  const M = build(P, { needs: false });
  assert.deepStrictEqual(F.floors(P).map((f) => f.id), ["main", "discord", "labs"]);
  assert.deepStrictEqual(F.view(M, "labs").rooms.map((r) => r.id), ["mooblox"]);
  const one = build(BASE, { needs: false });
  assert.deepStrictEqual(F.floors(BASE).map((f) => f.id), ["main"]);
  assert.ok([one.ceo, ...one.rooms, ...one.staff].every((r) => r.floor === "main"));
  assert.strictEqual(F.view(one, "main").rooms.length, one.rooms.length);
});

test("layout keeps two bay rows at least and puts staff teams on rows of their own", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), L = await load("office/layout.js");
  const M = build(withFloors(), { needs: false });
  assert.deepStrictEqual(L.rowsOf(F.view(M, "discord")), { rows: 1, all: 2 });
  assert.deepStrictEqual(L.rowsOf(F.view(M, F.MAIN)), { rows: 1, all: 2 });
  M.staff.push(...M.staff.slice(0, 1).map((r) => ({ ...r, id: "team-x" })));
  assert.deepStrictEqual(L.rowsOf(F.view(M, F.MAIN)), { rows: 1, all: 3 }, "a fifth team opens a second staff row");
  assert.deepStrictEqual(L.rowsOf(build(BASE, { needs: false })), { rows: 2, all: 3 }, "the single-floor fixture's grid is unchanged");
});
