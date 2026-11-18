// T1767: the Switchboard polished. A new ticket is seen from /api/agents before the next office read; the patch-wall plates read on a phone; the room has a top floor's volume.
// Run: node --test --test-reporter=tap tests/test_office_ceo_polish.js
"use strict";
const test = require("node:test");
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.join(__dirname, ".."), JS = path.join(ROOT, "static", "next", "js");
const BASE = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8"));
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const sub = (id, state) => ({ id, label: id + " x", type: "worker", started: "2026-11-10T14:40:00Z", last: "2026-11-10T14:40:00Z", state, doing: "x", report: "" });
const NAMES = ["5F CEO", "4F Discord", "3F Personal", "2F Work", "1F Operations"];

test("behind: a working agent the office read lacks, or a state change, asks for a read; equal lists and po-work rows do not", async () => {
  const D = await load("office/ceo/desk.js"), P = JSON.parse(JSON.stringify(BASE));
  P.agents.subagents = [sub("a1", "working"), sub("a2", "done")];
  P.sessions.push({ seat: null, parent: "mooblox", state: "working", since: 1, pid: 4242, name: "T1", started_by: "mooblox-T1" });
  const A = (rows) => ({ subagents: rows });
  assert.strictEqual(D.behind(P, A([sub("a1", "working"), sub("a2", "done"), sub("pid4242", "working")])), false, "same rows, the moved po-work row counts as known");
  assert.strictEqual(D.behind(P, A([sub("a1", "working"), sub("a2", "done"), sub("a3", "working")])), true, "a new ticket");
  assert.strictEqual(D.behind(P, A([sub("a1", "done"), sub("a2", "done")])), true, "a ticket ended");
  assert.strictEqual(D.behind(P, A([sub("a1", "working"), sub("a2", "done"), sub("a0", "done")])), false, "an old ended row is no news");
  assert.strictEqual(D.behind(null, A([sub("a3", "working")])), false);
  assert.strictEqual(D.behind(P, undefined), false);
});

test("the office polls /api/agents every 5 s while it is on screen, idle or not, and reads /api/office when behind", () => {
  const app = fs.readFileSync(path.join(JS, "app.js"), "utf8"), org = fs.readFileSync(path.join(JS, "screens", "org.js"), "utf8");
  const fast = app.slice(app.indexOf("function fast()"), app.indexOf("function tick()"));
  assert.ok(/cur !== "org"\)\s*return/.test(fast) && !/WORKING/.test(fast), "no idle exception in fast()");
  assert.ok(/behind\(P, store\.A\)/.test(org), "org tick reads the office when the agents list moved");
});

test("plates: every floor name the same size, at least 0.24 m capitals, numerals larger, columns as wide as their names filling the wall, under its top", async () => {
  const W = await load("office/build/ceo/wall.js"), C = await load("office/ceo/plan.js");
  const L = W.plates(NAMES), names = L.filter((l) => !/^\dF$/.test(l.text)), nums = L.filter((l) => /^\dF$/.test(l.text)), cap = (l) => l.top[1] - l.bot[1];
  assert.deepStrictEqual(names.map((l) => l.text), ["CEO", "DISCORD", "PERSONAL", "WORK", "OPERATIONS"]);
  assert.strictEqual(new Set(names.map((l) => cap(l).toFixed(4))).size, 1, "one size for every name");
  assert.ok(cap(names[0]) >= 0.24, "name capitals " + cap(names[0]).toFixed(3) + " m");
  assert.ok(nums.every((l) => cap(l) > cap(names[0]) * 1.3), "numerals larger");
  for (const l of L) assert.ok(l.w <= l.cw - 0.1 && l.top[1] <= C.WALL.y1 + C.STEP + 1e-6, l.text);
  assert.ok(Math.abs(nums.reduce((t, l) => t + l.cw, 0) - C.WALL.w) < 1e-6, "the columns fill the wall");
  assert.ok(nums[4].cw > nums[0].cw && nums.every((l) => l.cw >= 1), "OPERATIONS gets more wall than CEO, every column 1 m at least");
});

test("the room: a top floor's volume, the pit one clear step lower, glass up to the head beam", async () => {
  const C = await load("office/ceo/plan.js");
  assert.ok(C.ROOM.w >= 10.5 && C.ROOM.d >= 9 && C.ROOM.h >= 4, "plan and height");
  assert.ok(C.STEP >= 0.24, "one clear step");
  assert.ok(C.WALL.w >= C.ROOM.w * 0.85, "the patch wall spans the back");
  assert.ok(C.WALL.y1 <= C.ROOM.h - 0.3, "the wall stands under the head beam");
});
