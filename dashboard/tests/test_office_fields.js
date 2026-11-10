// Office card fields (T1601-07, PLAN 2.1 O4-O8): the seat, worker and CEO cards carry every Org field in the old
// tooltip's order (Name · Rank, area, about, role line, wake line, state and since) plus workers, folder, started by,
// last active and Message; a protected seat names no folder or starter. Pure: runs under node on the shared fixture.
// Run: node tests/test_office_fields.js
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const JS = path.join(__dirname, "..", "static", "next", "js");
const P = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8"));
const NOW = Date.parse("2026-11-10T15:00:00Z");
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const ROLE_MGR = "Project manager. Never posts.", ROLE_PO = "Product owner.", ROLE_CEO = "Runs the fleet and answers questions about the harness.";
const INBOX = "Asleep until someone writes to its inbox.", CHANNEL = "Always on; woken through its chat channel.", PULL = "Reads its messages when it next runs.";
let n = 0;
const ok = (name, fn) => { fn(); n++; console.log("ok " + n + " " + name); };

(async () => {
  const Mo = await load("office/model.js"), F = await load("office/fields.js"), T = await load("office/time.js");
  const M = Mo.build(P), C = (id) => F.card(M.who[id], NOW), ago = (s) => T.ago(s, NOW) + " ago";

  ok("O4/O5/O6 seat card: Name · Rank, area, about, role, wake, state and since, workers, folder, started by, last active, Message", () => {
    const c = C("tiny-epic-narrator");
    assert.deepStrictEqual([c.title, c.rank, c.sub], ["Bramble", "Manager", "Tiny Epic Narrator"]);
    assert.deepStrictEqual(c.lines, ["A narrated board-game helper.", ROLE_MGR, INBOX]);
    assert.strictEqual(c.state.text, "Now working · 30 min");
    assert.deepStrictEqual(c.rows, [["Workers", "2 workers, 1 working"], ["Folder", "~/agents/po-tiny-epic-narrator"], ["Started by", "po-tiny-epic-narrator"], ["Last active", "30 min ago"]]);
    assert.deepStrictEqual(c.actions, [{ label: "Message Bramble", href: "#chat?ch=dm-owner--tiny-epic-narrator" }]);
  });

  ok("seat card without a session: no folder rows, its state, no workers, Message", () => {
    const c = C("mooblox");
    assert.deepStrictEqual([c.title, c.rank, c.sub], ["Mossfang", "Product Owner", "Mooblox"]);
    assert.deepStrictEqual(c.lines, ["A 3D island course in the browser.", ROLE_PO, INBOX]);
    assert.strictEqual(c.state.text, "Now asleep");
    assert.deepStrictEqual(c.rows, [["Workers", "no workers"]]);
    assert.strictEqual(c.actions[0].href, "#chat?ch=dm-mooblox--owner");
  });

  ok("protected seat: state and last active only, the folder reads protected project", () => {
    const c = C("vass");
    assert.deepStrictEqual(c.lines, ["A client project.", ROLE_PO, PULL]);
    assert.strictEqual(c.state.text, "Now yours");
    assert.deepStrictEqual(c.rows, [["Workers", "no workers"], ["Folder", "protected project"], ["Last active", ago(1794322086)]]);
    assert.ok(!JSON.stringify(c).includes("~/"), "no path of a protected seat");
  });

  ok("CEO card: Name · Rank, about, role, wake, state, agents, folder, started by, last active, Message", () => {
    const c = C("orchestrator");
    assert.deepStrictEqual([c.title, c.rank, c.sub], ["DarkSaddler", "CEO", ""]);
    assert.deepStrictEqual(c.lines, ["Runs the fleet.", ROLE_CEO, CHANNEL]);
    assert.strictEqual(c.state.text, "Now working · " + T.ago(1794320000, NOW));
    assert.deepStrictEqual(c.rows, [["Agents working", "2"], ["At the desk pool", "2"], ["Folder", "~"], ["Started by", "owner"], ["Last active", ago(1794320000)]]);
    assert.deepStrictEqual(c.actions, [{ label: "Message DarkSaddler", href: "#chat?ch=dm-orchestrator--owner" }]);
  });

  ok("O7 worker card: name, rank, Works for, state and since, folder, started by, last active, no Message", () => {
    const c = C("pid1003");
    assert.deepStrictEqual([c.title, c.rank, c.sub], ["agent-T9001", "Worker", "Works for Bramble"]);
    assert.strictEqual(c.state.text, "Now working · " + T.ago(1794321500, NOW));
    assert.deepStrictEqual(c.rows, [["Folder", "~/projects/example-a"], ["Started by", "T9001"], ["Last active", ago(1794321500)]]);
    assert.deepStrictEqual(c.actions, []);
    assert.strictEqual(C("pid1004").state.text, "Now idle · " + T.ago(1794321600, NOW));
  });

  ok("every card: lines, when given, are non-empty strings; rows are [label, value, tone?]", () => {
    for (const id of Object.keys(M.who)) {
      const c = F.card(M.who[id], NOW);
      if ("lines" in c) assert.ok(Array.isArray(c.lines) && c.lines.every((l) => typeof l === "string" && l), id);
      assert.ok(c.rows.every((r) => r.length >= 2 && r.length <= 3 && r[1] !== "" && r[1] != null), id);
    }
  });

  ok("pure and small: no DOM, under 12 KB", () => {
    const s = fs.readFileSync(path.join(JS, "office", "fields.js"), "utf8");
    assert.ok(s.length < 12000 && !/\b(document|window)\b/.test(s));
  });
  console.log("all " + n + " passed");
})().catch((e) => { console.error("FAIL", e.message); process.exit(1); });
