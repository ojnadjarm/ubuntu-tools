// Office court (T1601-10, PLAN 2.1 C1-C5): DarkSaddler's running agents sit at the desk pool under their ticket, a pid session an
// agent started is one person in its seat's room, the agent card, the Running now rows, the CEO's motes, lamp
// and error pose as Court's crowd() set them, and a staff agent that is off reads apart from one asleep until its next run. Pure: node, fixture.
// Run: node tests/test_office_court.js
"use strict";
process.env.TZ = "UTC";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.join(__dirname, "..");
require("module").registerHooks({ resolve: (spec, ctx, next) => next(spec.startsWith("/static/") ? pathToFileURL(path.join(ROOT, spec)).href : spec, ctx) });
const JS = path.join(ROOT, "static", "next", "js");
const FIX = fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8");
const copy = () => JSON.parse(FIX);
const NOW = Date.parse("2026-11-10T15:00:00Z"), S = NOW / 1000;
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const ink = (text) => ({ w: text.length * 7 + 2, h: 14, runs: [] });
const ended = (id, label, state, last, extra = {}) => ({ id, label, type: "worker", started: "2026-11-10T12:00:00Z", last, state, doing: "npm test", report: "", ...extra });
let n = 0;
const ok = (name, fn) => { fn(); n++; console.log("ok " + n + " " + name); };

(async () => {
  const [Mo, F, { chunk }, { plan }, { THEME }, { decode }, { store }] = await Promise.all(
    ["office/model.js", "office/fields.js", "office/build/index.js", "office/layout.js", "office/theme.js", "office/kit.js", "store.js"].map(load));
  const kit = decode(JSON.parse(fs.readFileSync(path.join(ROOT, "static/next/office/kit.json"), "utf8")));
  const M = Mo.build(copy(), { now: NOW });
  const built = (m, id) => chunk(id, m, plan(m), THEME, kit, ink);

  ok("C1: every working sub-agent sits at the desk pool, named by its ticket, a tag over its desk", () => {
    const pool = M.rooms.find((r) => r.kind === "pool");
    assert.deepStrictEqual(pool.people.map((p) => [p.id, p.kind, p.name, p.rank, p.pose]).sort(),
      [["a0000000000000002", "agent", "T9003-04", "worker-max", "working"], ["pid1005", "agent", "T9002", "session", "working"]]);
    const c = built(M, "pool");
    assert.deepStrictEqual(c.labels.map((l) => l.id).sort(), ["a0000000000000002", "pid1005", "pool"]);
    assert.deepStrictEqual(c.actors.map((a) => [a.id, a.pose]).sort(), [["a0000000000000002", "working"], ["pid1005", "working"]]);
  });

  ok("C2: a pid session a seat's worker started is one person, in its seat's room, never at the pool", () => {
    const Q = copy();
    Q.agents.subagents.push({ id: "pid1003", label: "T9001", type: "session", started: "2026-11-10T14:00:00Z", last: S - 60, state: "working", doing: "live session · pid 1003", report: "" });
    const m = Mo.build(Q, { now: NOW }), all = [m.ceo, ...m.rooms, ...m.staff].flatMap((r) => r.people);
    assert.deepStrictEqual(all.filter((p) => p.id === "pid1003" || (p.raw.session && p.raw.session.pid === 1003)).map((p) => [p.id, p.kind, p.room]), [["pid1003", "agent", "tiny-epic-narrator"]]);
    assert.ok(!m.rooms.find((r) => r.kind === "pool").people.some((p) => p.id === "pid1003"));
    assert.deepStrictEqual(m.ceo.live.motes.sort(), ["a0000000000000002", "pid1003", "pid1005"], "one mote each");
  });

  ok("agent card: ticket, label, type, state, running since, doing now; its session's pid and starter", () => {
    const a = F.card(M.who.a0000000000000002, NOW);
    assert.deepStrictEqual([a.title, a.rank, a.sub, a.state.pose, a.state.text], ["T9003-04", "worker-max", "office renderer", "working", "Now working · 20 min"]);
    assert.deepStrictEqual(a.rows, [["Type", "worker-max"], ["Running since", "14:40 · 20 min ago"], ["Now", "Builds the stage"]]);
    const s = F.card(M.who.pid1005, NOW);
    assert.deepStrictEqual(s.rows.slice(0, 4), [["Type", "session"], ["Running since", "14:53 · 7 min ago"], ["Now", "live session · pid 1005"], ["Session", "pid 1005"]]);
    assert.strictEqual(s.rows.find((r) => r[0] === "Started by")[1], "T9002");
    assert.deepStrictEqual(s.actions, []);
  });

  ok("C3: Running now rows (the boards and Recent 24 h are gone, owner 2026-11-10)", () => {
    const Q = copy();
    Q.agents.subagents.push(ended("e1", "T9006 broken build", "error", S - 120, { report: "2 of 5 red" }), ended("e2", "T9007 stopped run", "stale", S - 3000));
    const m = Mo.build(Q, { now: NOW });
    assert.deepStrictEqual(m.panels.running.map((r) => [r.id, r.ticket, r.label, r.type, r.doing]),
      [["pid1005", "T9002", "", "session", "live session · pid 1005"], ["a0000000000000002", "T9003-04", "office renderer", "worker-max", "Builds the stage"]]);
  });

  ok("C4: the CEO has a mote per working agent, the lamp ok, and stands in the error pose only while an agent failed < 10 min ago", () => {
    assert.deepStrictEqual(M.ceo.live, { motes: ["pid1005", "a0000000000000002"], lamp: "ok", failing: null });
    assert.strictEqual(M.ceo.pose, "working");
    const a = built(M, "orchestrator").actors.find((x) => x.id === "orchestrator");
    assert.deepStrictEqual([a.pose, a.live.lamp, a.live.failing, a.live.motes.map((x) => x.id)], ["working", "ok", null, ["pid1005", "a0000000000000002"]]);
    const Q = copy(); Q.agents.subagents.push(ended("e1", "T9006 broken", "error", S - 9 * 60));
    const bad = Mo.build(Q, { now: NOW });
    assert.deepStrictEqual([bad.ceo.pose, bad.ceo.state, bad.who.orchestrator.pose, bad.ceo.live.failing], ["error", "error", "error", "e1"]);
    assert.deepStrictEqual(built(bad, "orchestrator").actors.find((x) => x.id === "orchestrator").live.failing, "e1");
    assert.deepStrictEqual(Mo.diff(M, bad).rooms, ["orchestrator"], "the CEO's room alone is rebuilt");
    const old = copy(); old.agents.subagents.push(ended("e1", "T9006 broken", "error", S - 11 * 60));
    assert.strictEqual(Mo.build(old, { now: NOW }).ceo.pose, "working", "an error older than 10 min is over");
  });

  ok("C4: the lamp says needs you when the status verdict has a need (the CEO's room changes)", () => {
    assert.strictEqual(Mo.build(copy(), { now: NOW, needs: true }).ceo.live.lamp, "needs");
    store.D = { verdict: { needs: [{ kind: "need", text: "fix the backup" }] } };
    const m = Mo.build(copy(), { now: NOW });
    store.D = null;
    assert.strictEqual(m.ceo.live.lamp, "needs", "read from the store's status by default");
    assert.deepStrictEqual(Mo.diff(M, m).rooms, ["orchestrator"]);
    assert.strictEqual(Mo.build(copy(), { now: NOW }).ceo.live.lamp, "ok");
  });

  ok("C4: a mote comes and goes with an agent: the CEO's room and the pool change", () => {
    const Q = copy(); Q.agents.subagents.push({ id: "n1", label: "T9008 new", type: "worker", started: "2026-11-10T14:59:00Z", last: S, state: "working", doing: "Read", report: "" });
    const m = Mo.build(Q, { now: NOW });
    assert.deepStrictEqual(m.ceo.live.motes, ["pid1005", "a0000000000000002", "n1"]);
    assert.deepStrictEqual(Mo.diff(M, m).rooms.sort(), ["orchestrator", "pool"]);
  });

  ok("C5: the CEO card: name, rank, state, agents working; the failed agent while in the error pose", () => {
    const c = F.card(M.who.orchestrator, NOW);
    assert.deepStrictEqual([c.title, c.rank, c.state.pose, c.rows[0]], ["DarkSaddler", "CEO", "working", ["Agents", "2 working"]]);
    const Q = copy(); Q.agents.subagents.push(ended("e1", "T9006 broken", "error", S - 120));
    const e = F.card(Mo.build(Q, { now: NOW }).who.orchestrator, NOW);
    assert.strictEqual(e.state.text.split(" · ")[0], "Now stuck on an error");
    assert.deepStrictEqual(e.rows.find((r) => r[0] === "Failed"), ["Failed", "T9006 · 2 min ago", "bad"]);
  });

  ok("off reads apart from asleep: an off staff agent's desk is dark, one asleep until its next run shows a standby light", () => {
    const team = (m) => m.staff.find((r) => r.people.some((p) => p.id === "code-review"));
    assert.deepStrictEqual([M.who["code-review"].pose, M.who["code-review"].on, M.who.toolsmith.pose, M.who.toolsmith.on], ["sleep", true, "sleep", false]);
    const Q = copy(); Q.staff.forEach((t) => t.members.forEach((x) => { if (x.id === "code-review") x.on = false; }));
    const m = Mo.build(Q, { now: NOW });
    assert.notStrictEqual(team(m).key, team(M).key, "on is in the room's key");
    assert.deepStrictEqual(Mo.diff(M, m).rooms, [team(M).id]);
    const a = built(M, team(M).id), b = built(m, team(m).id), lit = (c) => c.glows.filter(Boolean).length;
    assert.ok(lit(a) > lit(b), `the asleep desk has a standby glow the off one has not (${lit(a)} vs ${lit(b)})`);
    assert.ok(a.position.length > b.position.length, "the standby light is geometry of its own");
  });

  ok("night stays the last element of every room key (build/index.js stamp() strips it)", () => {
    for (const r of [M.ceo, ...M.rooms, ...M.staff]) assert.strictEqual(JSON.parse(r.key).at(-1), M.night);
  });

  console.log("all " + n + " passed");
})().catch((e) => { console.error("FAIL", e.message); process.exit(1); });
