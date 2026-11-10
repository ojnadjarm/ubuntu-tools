// Office parity, Court rows (C1-C11, T1601-14): running now, live sessions, recent (removed), the Conductor, the orchestrator button, persistent crew, claims, badge, refresh.
// Run alone: node tests/test_office_parity_court.js   (prints its rows; tests/test_office_parity.js runs every area and writes PARITY.md)
"use strict";
const assert = require("assert");
const { tk, ago, until, has, inScene } = require("./lib/parity-fixture");

/* The Court rows over the fixture view V. */
function area(row, V) {
  const { F0, S0, subs, members, live } = V;
  row("C1", "Court running now: creature, ticket, label, state, running <time>, now · <doing>", "scene creature + agent card", (X) => {
    for (const a of live) { const c = X.cards[a.id]; inScene(X, a.id); has(c, ...a.label.split(/\s+/), ago(a.started) + " ago", a.doing); assert.ok(c.st.includes("working"), a.id + " state"); }
  });
  row("C2", "Court rows of live sessions an agent started: pid, started by", "one creature per session; its agent card: Session pid N, Started by", (X) => {
    for (const a of live.filter((a) => /^pid/.test(a.id))) {
      const s = S0.find((x) => "pid" + x.pid === a.id);
      has(X.cards[a.id], "pid " + s.pid, s.started_by);
      const same = Object.values(X.cards).filter((c) => [s.name, tk(a.label)].some((n) => c.title === n || c.title.startsWith(n + " · "))).map((c) => c.id);
      assert.deepStrictEqual(same, [a.id], a.id + ": shown once, cards " + same.join(" "));
    }
  });
  row("C3", "Court recent · 24 h drawer", "removed on the owner's word (2026-11-10, T1601-17 addition 3)", null);
  row("C4", "Court Conductor: 1 mote per live agent, lamp ok / needs you, error pose < 10 min", "scene CEO (motes, lamp, pose) + CEO card Failed and Needs you", (X) => {
    const L = X.M.ceo.live;
    assert.deepStrictEqual([L.motes.length, L.lamp, X.M.ceo.pose], [live.length, "needs", "error"]);
    has(X.cards.orchestrator, "T8004", ago(subs.find((s) => s.id === "a8004").last) + " ago", "Needs you");
  });
  row("C5", "Court orchestrator button: name, rank, state, N working", "CEO card", (X) => {
    const c = X.cards.orchestrator; has(c, "DarkSaddler", "CEO");
    assert.ok(new RegExp(`working\\D{0,4}${live.length}\\b|\\b${live.length} working`).test(c.text), `CEO card does not say ${live.length} working (old Court: every live agent); rows ${c.rows.slice(0, 2).map((r) => r[0] + " = " + r[1]).join(", ")}`);
  });
  row("C7", "Court persistent: creature, name, state pill, next / on demand / always on, last run ago", "scene creature in its team room + staff card", (X) => {
    for (const r of members.filter((r) => r.state && (r.state !== "off" || r.kind === "on-demand"))) {
      const c = X.cards[r.id]; inScene(X, r.id); has(c, r.name);
      assert.strictEqual(c.st.includes("working"), r.state === "running", r.id + ": running");
      has(c, r.next ? "in " + until(r.next) : r.kind === "on-demand" ? "on demand" : "always on");
      if (r.last && r.last.end) has(c, ago(r.last.end) + " ago");
    }
  });
  row("C8", "Court claims board: who, note, paths (short, full on hover), empty text", "room card Files held row \"N · who\" of the owner's room (CEO card when no owner); paths, note and empty text removed on the owner's word (2026-11-10, minimal card)", (X) => {
    const all = Object.values(X.cards);
    for (const c of F0.agents.claims.map(X.claimRow)) {
      const k = all.find((x) => x.rows.some((r) => r[0] === "Files held" && r[1].split(" · ")[1].split(", ").includes(c.who)));
      assert.ok(k, c.who + ": on no card"); assert.ok(!c.paths.some((p) => k.text.includes(p.full)), c.who + ": a path on the card");
    }
  });
  row("C10", "Dock and sub-tab: gold count of failed agents, green count of working", "Office sub-tab badge (PLAN §2.1: ticket 15)", (X) => {
    assert.strictEqual(X.badge, String(subs.filter((s) => s.state === "error").length), `Office sub-tab badge is "${X.badge}"`);
  });
  row("C11", "Court and Roster: 5 s refresh while someone works", "quiet 20 s while someone works: /api/agents every ≤ 6.5 s; /api/office ≥ 3 reads, gap ≤ 10 s (a cycle skips a read < 4.5 s old)", (X) => {
    const A = X.gaps["/api/agents"], O = X.gaps["/api/office"];
    assert.ok(A.n >= 4 && A.max <= 6500, "/api/agents: " + JSON.stringify(A)); assert.ok(O.n >= 3 && O.max <= 10000, "/api/office: " + JSON.stringify(O));
  });
}

module.exports = area;
if (require.main === module) require("./lib/parity").main([area], { name: "test_office_parity_court" });
