// The office builders under node, on the shared fixture: sane buffers, vertex budget, quad kinds, state lamps, equal rebuilds, the 66-model kit.
// Run: node tests/test_office_build.js
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const js = (f) => import(path.join(__dirname, "../static/next/js/office", f));
const read = (f) => JSON.parse(fs.readFileSync(path.join(__dirname, f), "utf8"));
/* A stand-in text rasteriser: three lit rows of 5 px per letter. */
const ink = (text) => ({ w: text.length * 7 + 2, h: 14, runs: [...text].flatMap((c, i) => (c === " " ? [] : [4, 7, 10].map((y) => [1 + i * 7, 6 + i * 7, y]))) });
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const tinted = (lamps, col) => lamps.filter((l) => same(l.col, col));

(async () => {
  const [{ build }, { plan }, { chunk, HALL }, { decode }, { THEME }, { WINDOW, DOT, HOLO }] = await Promise.all(["model.js", "layout.js", "build/index.js", "kit.js", "theme.js", "build/props.js"].map(js));
  const raw = read("../static/next/office/kit.json"), kit = decode(raw);
  assert.strictEqual(Object.keys(kit.models).length, 66, "the kit has 66 models");
  assert.ok(/Kenney/.test(fs.readFileSync(path.join(__dirname, "../static/next/office/KIT-LICENSE.txt"), "utf8")), "the kit's licence is recorded");

  const M = build(read("fixtures/office.json")), P = plan(M), rooms = [M.ceo, ...M.rooms, ...M.staff];
  const make = (id, m = M) => chunk(id, m, P, THEME, kit, ink), all = [HALL, ...rooms.map((r) => r.id)].map((id) => make(id));
  let verts = 0;
  for (const c of all) {
    const n = c.position.length / 3;
    assert.ok(n > 0, c.id + ": has vertices");
    assert.ok(c.position.every(Number.isFinite), c.id + ": finite positions");
    assert.ok(c.color.every(Number.isFinite), c.id + ": finite colours");
    assert.strictEqual(c.color.length, c.position.length, c.id + ": colour and position lengths");
    assert.ok(c.index.length % 3 === 0 && c.index.every((i) => i < n), c.id + ": indices in range");
    assert.ok(c.quads.every((q) => [WINDOW, DOT, HOLO].includes(q.kind)), c.id + ": quad kinds");
    assert.ok(c.quads.every((q) => q.p.length === 4 && q.p.flat().every(Number.isFinite)), c.id + ": finite quads");
    assert.ok(c.lamps.every((l) => [l.x, l.y, l.z, l.i, l.r, ...l.col].every(Number.isFinite)), c.id + ": finite lamps");
    for (let k = 0; k < 3; k++) assert.ok(c.lo[k] <= c.hi[k], c.id + ": bounds");
    verts += n;
  }
  assert.ok(verts >= 100000 && verts <= 150000, "total vertices between 100,000 and 150,000, got " + verts);
  assert.ok(all[0].quads.some((q) => q.kind === WINDOW), "the hall has city windows");

  const actors = all.flatMap((c) => c.actors), people = rooms.flatMap((r) => r.people);
  assert.strictEqual(new Set(actors.map((a) => a.id)).size, actors.length, "one creature per id");
  for (const r of rooms) for (const p of r.people.slice(0, P.cells[r.id].slots)) assert.ok(actors.some((a) => a.id === p.id && a.pose === p.pose), p.id + ": has a creature in its pose");
  assert.ok(actors.length <= people.length && actors.every((a) => M.who[a.id]), "every creature is a person of the model");
  for (const r of rooms) assert.ok(all.some((c) => c.id === r.id && c.labels.some((l) => l.id === r.id && l.pos.every(Number.isFinite))), r.id + ": has a label point");

  const busy = M.rooms.find((r) => r.kind === "seat" && r.busy > 0), asleep = M.rooms.find((r) => r.kind === "seat" && !r.awake);
  assert.ok(busy && asleep, "the fixture has a working and a sleeping seat room");
  assert.ok(tinted(make(busy.id).lamps, THEME.accent).length > 0, "a working room has a lamp in the accent colour");
  assert.strictEqual(tinted(make(asleep.id).lamps, THEME.accent).length, 0, "a sleeping room has no accent lamp");
  const team = M.staff.find((r) => !r.awake);
  if (team) assert.strictEqual(tinted(make(team.id).lamps, THEME.accent).length, 0, "a sleeping team room has no accent lamp");

  for (const id of [HALL, busy.id]) {
    const a = make(id), b = make(id);
    for (const k of ["position", "color", "index"]) assert.ok(same(a[k], b[k]), id + ": equal " + k + " when built twice");
    for (const k of ["lamps", "quads", "actors", "labels", "lo", "hi"]) assert.deepStrictEqual(a[k], b[k], id + ": equal " + k + " when built twice");
  }
  console.log(`ok test_office_build: ${all.length} chunks, ${verts} vertices, ${all.reduce((n, c) => n + c.quads.length, 0)} quads, ${all.reduce((n, c) => n + c.lamps.length, 0)} lamps, ${actors.length} creatures`);
})().catch((e) => { console.error(e); process.exit(1); });
