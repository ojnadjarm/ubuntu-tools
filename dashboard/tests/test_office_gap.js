// Office room spacing (T1601-18, owner 2026-11-10: "put more space between offices"): every two rooms of the plan (seat, team, pool, CEO deck)
// stand at least the layout's one GAP apart, and that gap is a walkway (at least 1.2 m; it was 0.35 m between bays).
// Run: node tests/test_office_gap.js
"use strict";
const assert = require("assert");
const path = require("path");
const { pathToFileURL } = require("url");
const FIX = require("./fixtures/office.json");
const load = (f) => import(pathToFileURL(path.join(__dirname, "..", "static", "next", "js", "office", f)).href);
const WALK = 1.2;

(async () => {
  const Mo = await load("model.js"), L = await load("layout.js"), cells = Object.entries(L.plan(Mo.build(FIX)).cells);
  let min = 1e9, pair = "";
  for (const [a, p] of cells) for (const [b, q] of cells) {
    if (a >= b) continue;
    const g = Math.max(Math.abs(p.x - q.x) - (p.w + q.w) / 2, Math.abs(p.z - q.z) - (p.d + q.d) / 2);
    if (g < min) { min = g; pair = a + " | " + b; }
  }
  assert.ok(Math.abs(min - L.GAP) < 1e-9 && min >= WALK, `the nearest two rooms (${pair}) stand ${min.toFixed(2)} m apart: the layout's GAP (${L.GAP}), at least ${WALK}`);
  console.log(`ok test_office_gap: ${cells.length} rooms, nearest two ${min.toFixed(2)} m apart`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
