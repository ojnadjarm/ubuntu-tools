// Office parity, Roster rows (R1-R8, T1601-14): the band, next runs, and the timer-agent, bash-timer, service and on-demand cards; `hello` hidden.
// Run alone: node tests/test_office_parity_roster.js   (prints its rows; tests/test_office_parity.js runs every area and writes PARITY.md)
"use strict";
const assert = require("assert");
const { ago, until, bad, has, inScene, lastRows } = require("./lib/parity-fixture");

/* The Roster rows over the fixture view V. */
function area(row, V) {
  const { seats, members, L, up, q } = V;
  row("R1", "Roster band: N of M agents on · next up <name> in <time>", "band line", (X) => {
    assert.ok(new RegExp(`${up.length} of ${L.length} (agents|staff) on · next up (${q[0].id}|${q[0].name}) in ${until(q[0].next)}`).test(X.band), X.band);
  });
  row("R2", "Roster next runs: name, in <time>, progress bar, bad mark", "staff card Next run + bar; team room card Next runs (failed mark)", (X) => {
    for (const r of q) {
      const c = X.cards[r.id], t = X.cards["team-" + r.team], n = t.rows.find((x) => x[0] === r.name);
      has(c, "in " + until(r.next)); assert.ok(c.bar != null, r.id + ": no bar");
      assert.ok(n && n[1].includes("in " + until(r.next)), r.id + ": not in its team's Next runs");
      assert.strictEqual(/failed/.test(n[1]) || /bad/.test(n[2]), bad(r), r.id + ": bad mark");
    }
  });
  row("R4", "Roster timer agent card: pill, schedule, countdown, next, last run, exit, seconds, report; gold when bad, dim when off", "staff card (every field) + scene pose", (X) => {
    for (const r of members.filter((r) => r.kind === "timer-agent")) {
      const c = X.cards[r.id]; inScene(X, r.id); has(c, r.name, r.on ? "scheduled" : "off", r.schedule); lastRows(c, r);
      if (r.on && r.next) { has(c, "in " + until(r.next)); assert.ok(c.bar != null, r.id + ": bar"); }
      assert.strictEqual(c.rows.some((x) => /bad/.test(x[2])), bad(r), r.id + ": gold"); assert.strictEqual(c.dim, !r.on, r.id + ": dim");
      assert.strictEqual(X.M.who[r.id].pose, r.state === "running" ? "working" : bad(r) ? "error" : "sleep", r.id + ": scene pose");
    }
  });
  row("R5", "Roster bash-timer card: pill, schedule, unit, next, last check, result, seconds, fallback last ran, fallback report", "staff card (every field)", (X) => {
    for (const r of members.filter((r) => r.kind === "bash-timer")) {
      const c = X.cards[r.id]; has(c, r.on ? (bad(r) ? "failed" : "on") : "down", r.schedule, r.runner.unit, "in " + until(r.next)); lastRows(c, r); if (r.fallback && r.report) assert.ok(c.rows.some((x) => /fallback report/i.test(x[0]) && x[1].includes(r.report)), r.id + ": fallback report");
      if (r.fallback) has(c, ago(r.fallback.end) + " ago");
    }
  });
  row("R6", "Roster service card: pill, always on, unit, state · sub, up since, tmux alive / missing", "staff card (every field)", (X) => {
    for (const r of members.filter((r) => r.kind === "service")) {
      const u = r.runner, c = X.cards[r.id];
      has(c, r.on ? "on" : bad(r) ? "failed" : r.health === "warn" ? "down" : "off", "always on", u.unit, u.state + (u.sub ? " · " + u.sub : ""), u.tmux + " · " + (u.tmux_alive ? "alive" : "missing"));
      if (r.on) has(c, ago(u.since) + " ago");
    }
  });
  row("R7", "Roster on-demand card (po-*, ci-fix): off, on demand, last run, exit, seconds, report", "po-*: the seat's card; ci-fix: staff card", (X) => {
    for (const s of seats.filter((s) => s.runner)) lastRows(X.cards[s.id], s.runner);
    const r = members.find((r) => r.id === "ci-fix"), c = X.cards[r.id]; has(c, "off", "on demand"); lastRows(c, r);
  });
  row("R8", "Roster hides `hello`", "staff.json `hidden` + lib/staff.assign", (X) => {
    assert.ok(X.hidden.hidden.includes("hello"), "staff.json hidden"); assert.ok(!JSON.stringify(X.hidden.teams).includes('"hello"'), "hello placed in a team");
  });
}

module.exports = area;
if (require.main === module) require("./lib/parity").main([area], { name: "test_office_parity_roster" });
