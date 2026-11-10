// Office card fields (T1601-07, PLAN 2.1 O4-O8): the seat, worker and CEO cards carry every Org field in the old
// tooltip's order (Name · Rank, area, about, role line, wake line, state and since) plus workers, folder, started by,
// last active and Message; a protected seat names no folder or starter. Staff cards (T1601-08, PLAN 2.1 R4-R7, C7) carry every
// Roster field for the 5 runner kinds; a PO or manager seat's card adds its runner's 4 rows. Pure: runs under node on the shared fixture.
// Run: node tests/test_office_fields.js
"use strict";
process.env.TZ = "UTC";
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
    assert.deepStrictEqual(c.rows, [["Workers", "2 workers, 1 working"], ["Folder", "~/agents/po-tiny-epic-narrator"], ["Started by", "po-tiny-epic-narrator"], ["Last active", "30 min ago"],
      ["Last run", "13:10 · 1.8 h ago"], ["Last exit", "0"], ["Took", "640 s"], ["Report", "Two PRs open."]]);
    assert.deepStrictEqual(c.actions, [{ label: "Message Bramble", href: "#chat?ch=dm-owner--tiny-epic-narrator" }]);
  });

  ok("seat card without a session: no folder rows, its state, no workers, Message", () => {
    const c = C("mooblox");
    assert.deepStrictEqual([c.title, c.rank, c.sub], ["Mossfang", "Product Owner", "Mooblox"]);
    assert.deepStrictEqual(c.lines, ["A 3D island course in the browser.", ROLE_PO, INBOX]);
    assert.strictEqual(c.state.text, "Now asleep");
    assert.deepStrictEqual(c.rows, [["Workers", "no workers"], ["Last run", "08:12 · 6.8 h ago"], ["Last exit", "0"], ["Took", "312 s"], ["Report", "Shipped zone 3 props."]]);
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

  const head = (c) => [c.title, c.rank, c.sub, c.state.pose, c.state.text, c.actions.length, !!c.dim];
  ok("R4 timer agent: Name · Rank, its id and team, pill scheduled, schedule, countdown and next, last run, last exit, seconds, report, bar", () => {
    const c = C("sentinel-digest");
    assert.deepStrictEqual(head(c), ["Cinder", "Watch Reporter", "sentinel-digest · Operations", "sleep", "Asleep until its next run", 0, false]);
    assert.deepStrictEqual(c.rows, [["Status", "scheduled"], ["Schedule", "daily 07:00"], ["Next run", "in 15 h · Wed 06:00"], ["Last run", "06:02 · 9.0 h ago"], ["Last exit", "0"], ["Took", "130 s"], ["Report", "All quiet."]]);
    assert.strictEqual(Math.round(c.bar), 37);
    assert.strictEqual(C("maintenance").state.text, "Running now");
  });

  ok("R4 timer agent off: pill off, next off, dim, no bar", () => {
    const c = C("toolsmith");
    assert.deepStrictEqual(head(c), ["Soot", "Toolsmith", "toolsmith · Improvement", "sleep", "Off", 0, true]);
    assert.deepStrictEqual(c.rows, [["Status", "off"], ["Schedule", "Sun 05:00"], ["Next run", "off"], ["Last run", "Sun 04:40 · 2 d ago"], ["Last exit", "0"], ["Took", "2400 s"], ["Report", "Built 1 tool."]]);
    assert.ok(!("bar" in c));
  });

  ok("R5 bash timer, bad: error pose, pill failed and result in gold, unit, next, last check, seconds, fallback last ran, fallback report", () => {
    const c = C("sentinel");
    assert.deepStrictEqual(head(c), ["Ember", "Sentinel", "sentinel · Operations", "error", "Stuck on an error", 0, false]);
    assert.deepStrictEqual(c.rows, [["Status", "failed", "bad"], ["Schedule", "every 15 min"], ["Unit", "sentinel-check.timer"], ["Next run", "in 15 min · 15:15"], ["Last check", "14:58 · 2 min ago"],
      ["Result", "1", "bad"], ["Took", "3 s"], ["Fallback last ran", "07:00 · 8.0 h ago"], ["Fallback report", "disk check failed"]]);
  });

  ok("plain timer (a unit, no agent folder): the bash timer's rows without a fallback", () => {
    const c = C("fleet-backup");
    assert.deepStrictEqual(head(c), ["Yarrow", "Archivist", "fleet-backup · Operations", "sleep", "Asleep until its next run", 0, false]);
    assert.deepStrictEqual(c.rows, [["Status", "on"], ["Schedule", "daily 03:30"], ["Unit", "fleet-backup.timer"], ["Next run", "in 12 h · Wed 02:30"], ["Last check", "02:41 · 12.3 h ago"],
      ["Result", "0"], ["Took", "660 s"], ["Report", "no report yet"]]);
  });

  ok("R6 service: pill on, always on, unit, up since, unit state and sub-state, tmux alive; down: pill down, tmux missing in gold", () => {
    const c = C("night-relay");
    assert.deepStrictEqual(head(c), ["night-relay", "Staff", "night-relay · Unassigned", "sleep", "Always on", 0, false]);
    assert.deepStrictEqual(c.rows, [["Status", "on"], ["Schedule", "always on"], ["Unit", "night-relay.service"], ["Up since", "yesterday 07:00 · 32.0 h ago"], ["Unit state", "active · running"],
      ["Tmux", "night-relay · alive"], ["Report", "relay up"]]);
    const m = M.who["night-relay"], down = F.card({ ...m, raw: { ...m.raw, on: false, health: "warn", runner: { ...m.raw.runner, state: "inactive", sub: "dead", tmux_alive: false, since: "" } } }, NOW);
    assert.deepStrictEqual(down.rows.slice(0, 6), [["Status", "down"], ["Schedule", "always on"], ["Unit", "night-relay.service"], ["Up since", "—"], ["Unit state", "inactive · dead", "bad"], ["Tmux", "night-relay · missing", "bad"]]);
    assert.strictEqual(down.dim, true);
  });

  ok("R7 on demand (ci-fix, decision 1): pill off, on demand, last run, exit, seconds, report, dim", () => {
    const c = C("ci-fix");
    assert.deepStrictEqual(head(c), ["Flint", "CI Fixer", "ci-fix · Quality", "sleep", "Asleep until someone starts it", 0, true]);
    assert.deepStrictEqual(c.rows, [["Status", "off"], ["Schedule", "on demand"], ["Last run", "01:26 · 13.6 h ago"], ["Last exit", "0"], ["Took", "44 s"], ["Report", "Fixed a test drift."]]);
  });

  ok("R7 a seat with no runner (vass, mosaico) gets no runner rows", () => {
    for (const id of ["vass", "mosaico"]) assert.ok(!C(id).rows.some((r) => ["Last run", "Last exit", "Took", "Report"].includes(r[0])), id);
  });

  ok("the Unassigned room: last staff room, a team card that says why and rolls its members", () => {
    const r = M.staff[M.staff.length - 1], c = C("team-unassigned");
    assert.deepStrictEqual([r.id, r.name, r.people.map((p) => p.id)], ["team-unassigned", "Unassigned", ["night-relay"]]);
    assert.deepStrictEqual([c.title, c.rank, c.sub, c.lines, c.roll, c.actions], ["Unassigned", "Team", "1 staff", ["Rostered agents that no team in staff.json names."], ["night-relay"], []]);
  });

  ok("every staff card: no Message; a hidden id of staff.json appears nowhere", () => {
    const staff = Object.values(M.who).filter((p) => p.kind === "staff");
    assert.strictEqual(staff.length, 13);
    for (const p of staff) assert.deepStrictEqual(F.card(p, NOW).actions, [], p.id);
    const hidden = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "staff.json"), "utf8")).hidden, all = JSON.stringify(Object.values(M.who).map((p) => F.card(p, NOW)));
    assert.ok(hidden.length && hidden.every((h) => !(h in M.who) && !all.includes('"' + h + '"')), "hidden: " + hidden);
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
