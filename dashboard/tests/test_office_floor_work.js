// Office Personal and Work floors (T1759): a floor line with "deck": false has no raised office, no stairs, no mezzanine column. No DOM, no WebGL.
// Run: node --test --test-reporter=tap tests/test_office_floor_work.js
"use strict";
const test = require("node:test");
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const JS = path.join(__dirname, "..", "static", "next", "js");
const BASE = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8"));
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);

/* The fixture with the five floor lines of staff.json, bottom floor first. */
function five() {
  const P = JSON.parse(JSON.stringify(BASE));
  P.floors = [
    { id: "operations", name: "Operations", teams: ["operations", "quality", "improvement"], rest: ["team"] },
    { id: "work", name: "Work projects", teams: ["vass"], deck: false },
    { id: "personal", name: "Personal projects", teams: ["mooblox"], rest: ["po"], deck: false },
    { id: "discord", name: "Discord", teams: ["discord"], head: "discord" },
    { id: "ceo", name: "CEO", teams: ["orchestrator"], head: "orchestrator" },
  ];
  return P;
}
const session = (pid, extra) => ({ seat: null, state: "working", since: 1794322500, pid, name: "agent-x", cwd: "~", rank: "Worker", ...extra });

/* The models a builder draws for the hall of floor f: every B.model name. */
async function hallModels(V) {
  const { plan } = await load("office/layout.js"), { hall } = await load("office/build/hall.js"), { THEME } = await load("office/theme.js");
  const names = [], noop = () => {};
  const B = { push: noop, pop: noop, cells: noop, box: noop, cyl: noop, ring: noop, foot: noop, at: () => ({ x: 0, y: 0, z: 0, r: 0 }), model: (n) => names.push(n) };
  hall({ B, M: V, th: THEME, night: false, actors: [], lamps: [], glows: [null], glowIx: {}, labels: [], quads: [] }, plan(V));
  return names;
}

test("a floor line has its raised office by default; deck false names the floor in flat()", async () => {
  const F = await load("office/floors.js");
  assert.deepStrictEqual(F.flat(five()), ["work", "personal"]);
  assert.deepStrictEqual(F.flat(BASE), []);
  const { build } = await load("office/model.js"), M = build(five(), { needs: false });
  assert.strictEqual(F.view(M, "discord", five()).deck, true);
  assert.strictEqual(F.view(M, "ceo", five()).deck, true);
  assert.strictEqual(F.view(M, "personal").deck, true, "no payload: the default");
});

test("Personal and Work floors hold their projects in bays and nobody in a raised office", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), P = five();
  const M = build(P, { needs: false });
  for (const [f, id] of [["personal", "mooblox"], ["work", "vass"]]) {
    const V = F.view(M, f, P);
    assert.strictEqual(V.deck, false, f);
    assert.strictEqual(V.ceo, null, f + ": no raised office");
    assert.deepStrictEqual(V.rooms.map((r) => r.id), [id], f);
  }
  assert.strictEqual(F.view(M, "discord", P).ceo.id, "discord", "Discord keeps its head up there");
  assert.strictEqual(F.view(M, "ceo", P).ceo.id, "orchestrator");
  assert.deepStrictEqual(F.floors(P).map((f) => f.name), ["Operations", "Work projects", "Personal projects", "Discord", "CEO"]);
});

test("a floor with no deck: no mezzanine column, bays from the left wall, a pool takes a bay", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), L = await load("office/layout.js"), P = five();
  P.staff.push({ id: "labs", name: "Labs", members: [{ id: "lab-bot", name: "Lab", rank: "Staff", state: "running" }] });
  P.floors[2].teams.push("labs");
  P.sessions.push(session(2001, { parent: null, started_by: "lab-bot" }));
  const M = build(P, { needs: false }), V = F.view(M, "personal", P), D = F.view(M, "discord", P);
  const p = L.plan(V), d = L.plan(D);
  assert.ok(V.rooms.some((r) => r.id === "pool-personal"), "the worker's desk pool is on Personal");
  assert.strictEqual(p.hall.x0, L.GAP / 2);
  assert.strictEqual(d.hall.x0, L.X0);
  assert.ok(p.hall.w < d.hall.w - L.MW, "the hall loses the mezzanine column");
  const cells = Object.values(p.cells);
  assert.ok(cells.every((c) => c.w === L.IW && c.x - c.w / 2 >= L.GAP / 2 - 1e-9 && c.x + c.w / 2 <= p.hall.w), "every room a bay inside the hall");
  assert.strictEqual(new Set(cells.map((c) => c.x + "," + c.z)).size, cells.length, "no two rooms on one bay");
  assert.strictEqual(L.baysOf(V), 2, "mooblox and the pool");
});

test("the hall of a deck-less floor draws no stairs and no kitchen; Discord's still does; the CEO's own room (T1758) has no stairs", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), P = five(), M = build(P, { needs: false });
  for (const f of ["personal", "work"]) {
    const m = await hallModels(F.view(M, f, P));
    assert.ok(!m.includes("stairs") && !m.includes("kitchenFridgeSmall"), f);
  }
  assert.ok((await hallModels(F.view(M, "discord", P))).includes("stairs"), "discord");
  assert.ok(!(await hallModels(F.view(M, "ceo", P))).includes("stairs"), "ceo");
});

test("the hall chunk's stamp changes when a pool takes a bay on a deck-less floor", async () => {
  const { build } = await load("office/model.js"), F = await load("office/floors.js"), L = await load("office/layout.js"), I = await load("office/build/index.js");
  const P = five(), V = F.view(build(P, { needs: false }), "personal", P);
  const W = { ...V, rooms: [...V.rooms, { id: "pool-personal", kind: "pool", floor: "personal", people: [] }] };
  assert.notStrictEqual(I.stamp(I.HALL, V, L.plan(V)), I.stamp(I.HALL, W, L.plan(W)));
});
