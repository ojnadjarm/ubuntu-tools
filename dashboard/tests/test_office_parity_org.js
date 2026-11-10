// Office parity, Org rows (O1-O10, T1601-14): the old Org screen's band, tree, seat cards, tooltip, Message, workers, talk, sessions table and load text.
// Run alone: node tests/test_office_parity_org.js   (prints its rows; tests/test_office_parity.js runs every area and writes PARITY.md)
"use strict";
const assert = require("assert");
const { tk, ago, ROLE, WAKE, dmOf, bad, has, inScene } = require("./lib/parity-fixture");

/* The Org rows over the fixture view V. */
function area(row, V) {
  const { seats, S0, subs, nowOf, seatState } = V;
  row("O1", "Org band: N Claude sessions, N working, `stale: <error>`", "band line over the office", (X) => {
    assert.ok(X.band.startsWith(`${S0.length} Claude sessions on this laptop, ${S0.filter((s) => s.state === "working").length} working`), X.band);
    assert.ok(X.staleBand.includes("stale: office source failed: agents"), X.staleBand);
  });
  row("O2", "Org tree: who reports to whom, N seats", "scene: every seat has a room, a sub-seat's room in its parent's team; list: child nested under parent", (X) => {
    for (const s of seats) inScene(X, s.id);
    const R = (id) => X.M.rooms.find((r) => r.id === id);
    assert.strictEqual(R("beta").team, R("alpha").team, "beta's room not in alpha's team");
    for (const s of seats.filter((s) => s.parent !== "owner")) assert.ok(X.nest[s.id] === s.parent, `${s.id} not under ${s.parent} in the list: ${X.nest[s.id]}`);
  });
  row("O4", "Org seat card: Familiar in state and role gear, name, rank, state dot", "scene creature at the lead desk (pose) + seat card (figure, name, rank, state)", (X) => {
    const POSE = { working: "working", idle: "idle", asleep: "sleep", off: "sleep" };
    for (const s of seats) {
      const c = X.cards[s.id], st = seatState(s);
      inScene(X, s.id); assert.ok(c.fig, s.id + ": no figure"); has(c, s.name, s.rank);
      assert.ok(c.stText.startsWith("Now " + nowOf(s)), `${s.id}: state "${c.stText}" not ${nowOf(s)}`);
      if (POSE[st] && s.id !== "orchestrator") assert.strictEqual(X.M.who[s.id].pose, s.runner && bad(s.runner) ? "error" : POSE[st], s.id + ": scene pose");
    }
  });
  row("O5", "Org seat tooltip: Name · Rank, area, about, role line, wake line, Now <state>.", "seat card", (X) => {
    for (const s of seats) has(X.cards[s.id], s.name, s.rank, s.area, s.about, ROLE[s.role], WAKE[s.wake], "Now " + nowOf(s));
  });
  row("O6", "Org Message button `#chat?ch=dm-…`", "seat card button", (X) => {
    for (const s of seats) assert.ok(X.cards[s.id].hrefs.includes("#chat?ch=" + dmOf(s.id)), s.id + ": no message link");
  });
  row("O7", "Org workers under a seat: N workers, M working, 3 shown, hidden N, name or pid, state, name · Worker", "seat card Workers row + scene desks + worker card", (X) => {
    const H_ = S0.filter((s) => !s.seat && s.parent === "beta");
    assert.ok(X.cards.beta.text.includes(`${H_.length} workers, ${H_.filter((s) => s.state === "working").length} working`), "beta card: worker count");
    for (const s of H_) {
      const id = "pid" + s.pid, c = X.cards[id];
      const merged = subs.some((a) => a.id === id);
      inScene(X, id); has(c, merged ? tk(subs.find((a) => a.id === id).label) : s.name || "pid " + s.pid);
      if (merged) assert.ok(Object.values(X.cards).some((k) => k.rows.some((r) => r[0] === s.name)), id + ": session name on no card"); else has(c, s.rank);
      assert.ok(c.st.includes(s.state === "working" ? "working" : "idle"), id + ": state " + c.st);
      if (!merged) has(c, "Works for Bramble");
    }
  });
  row("O8", "Org: a seat talks for 2 s when it posts", "scene creature pose (card shows it while open)", (X) => {
    assert.ok(X.talkCard, "alpha's open card did not talk");
    assert.ok(X.talkScene, "the 3D scene never drew alpha talking after it posted");
  });
  row("O9", "Org sessions table: Session, Seat, Folder, State, Started by, Last active; protected row", "room card Sessions (CEO card when no avatar) + the session's person card", (X) => {
    const all = Object.values(X.cards);
    for (const s of S0) {
      if (!("pid" in s)) { has(X.cards[s.seat], "protected project"); assert.ok(all.some((c) => c.rows.some((r) => r[0] === "protected project" && r[1].startsWith(s.state))), "protected row"); continue; }
      const name = s.name || "pid " + s.pid, list = all.find((c) => c.rows.some((r) => r[0] === name)) || all.find((c) => c.text.includes(name));
      assert.ok(list, `session name "${name}" (${s.seat || s.parent}, folder ${s.cwd}) on no card`);
      const r = list.rows.find((r) => r[0] === name); if (r) assert.ok(r[1].startsWith(s.state), name + ": state");
      const me = X.cards[s.seat || "pid" + s.pid];
      has(me, s.cwd, s.started_by, ago(s.since) + " ago");
      const boss = seats.find((x) => x.id === (s.seat || s.parent));
      assert.ok([me.text, list.text].some((t) => t.includes(boss.name) || t.includes(boss.area) || (boss.role === "ceo" && /CEO/.test(t))), name + ": its seat");
    }
  });
  row("O10", "Org loading and error text", "page text while /api/office is slow or fails", (X) => {
    assert.ok(X.slow.includes("reading the org…"), X.slow);
    assert.ok(X.fail.startsWith("org unreadable · "), X.fail);
  });
}

module.exports = area;
if (require.main === module) require("./lib/parity").main([area], { name: "test_office_parity_org" });
