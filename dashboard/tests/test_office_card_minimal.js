// Office card minimal (T1601-20, owner 2026-11-10: "keep the card minimalistic"): no card kind carries a Held files list or a Full path row
// (held files are one "Files held" row: count · tickets, no paths); every list on a card shows at most 5 rows then "+N more"; long texts are cut;
// on a heavy fixture every card fits the viewport with no inner scroll at 1366x768 and is at most one screen tall at 400x800, no row over 2 lines.
// Run: node tests/test_office_card_minimal.js   (fixture API only, no GPU: the still office and its list; ONLY=pure|1366|400)
"use strict";
process.env.TZ = "UTC";
const assert = require("assert");
const path = require("path");
const { pathToFileURL } = require("url");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const NOW = Date.parse("2026-11-10T15:00:00Z"), ONLY = process.env.ONLY || "";
const JS = path.join(process.env.STATIC_ROOT || path.join(__dirname, "..", "static"), "next", "js");
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const LONG = "reads every file of the office overlay and rewrites the card layout so that nothing wraps past two lines on a phone screen ".repeat(3).trim();
const deep = (p) => "/home/someone/projects/collab/a-very-long-worktree-name-for-the-test/" + p;
/* The fixture made heavy: 9 sub-agents in the pool, 9 files held by one ticket with long paths, a loose claim, long reports and steps. */
const HEAVY = JSON.parse(JSON.stringify(FIX));
for (let i = 0; i < 9; i++) HEAVY.agents.subagents.push({ id: "a00000000000001" + i, label: "T95" + i + " heavy worker", type: "general-purpose", started: "2026-11-10T14:" + (10 + i) + ":00Z", last: NOW / 1000 - 20, state: "working", doing: LONG, report: "" });
HEAVY.agents.claims.push("T9001 · " + Array.from({ length: 9 }, (_, i) => deep("js/part-" + i + "-of-the-chapter.js")).join(" ") + " · " + LONG + " · 2026-11-10 21:26");
HEAVY.agents.claims.push("T7777 · " + deep("css/loose.css") + " · nobody's · 2026-11-10 10:00");
for (const t of HEAVY.staff) for (const m of t.members) m.report = LONG;
let n = 0;
const ok = (name) => console.log("ok " + ++n + " " + name);

/* Every card of the heavy model: no Held files part, no Full path row, no path, lists capped at 5 with the rest counted, long text cut. */
async function pure() {
  const Mo = await load("office/model.js"), F = await load("office/fields.js"), M = Mo.build(HEAVY, { now: NOW, needs: true });
  const cards = Object.values(M.who).map((p) => [p, F.card(p, NOW)]), kinds = new Set(cards.map(([p]) => p.kind));
  assert.deepStrictEqual(["ceo", "seat", "worker", "agent", "staff", "team", "pool"].filter((k) => !kinds.has(k)), [], "every card kind is in the heavy fixture");
  for (const [p, c] of cards) {
    const parts = c.parts || [], rows = [...c.rows, ...parts.flatMap((x) => x.rows)], text = JSON.stringify(c);
    assert.ok(!parts.some((x) => x.h === "Held files"), p.id + ": no Held files list");
    assert.ok(!rows.some((r) => r[0] === "Full path"), p.id + ": no Full path row");
    assert.ok(!/js\/part-|loose\.css|office\/model\.js/.test(text), p.id + ": no held path on the card");
    for (const x of parts) assert.ok(x.rows.length + x.chips.length <= 5, `${p.id} · ${x.h}: ${x.rows.length + x.chips.length} rows (> 5)`);
    assert.ok(!c.roll || c.roll.length <= 5, p.id + ": members capped at 5");
    for (const r of rows) assert.ok(String(r[1]).length <= 80, `${p.id} · ${r[0]}: ${String(r[1]).length} chars (> 80)`);
  }
  const C = (id) => F.card(M.who[id], NOW), row = (c, k) => (c.rows.find((r) => r[0] === k) || [])[1];
  assert.strictEqual(row(C("tiny-epic-narrator"), "Files held"), "11 · T9001, T9001", "the seat: one Files held row, count and tickets");
  assert.strictEqual(row(C("room-tiny-epic-narrator"), "Files held"), "11 · T9001, T9001", "its room: the same row");
  assert.strictEqual(row(C("orchestrator"), "Files held"), "1 · T7777", "the CEO: the files no avatar holds");
  const pool = C("pool"), subs = pool.parts.find((x) => x.h === "Sub-agents running"), all = M.panels.running.filter((a) => M.who.pool.info.subs.includes(a)).length;
  assert.deepStrictEqual([subs.chips.length, subs.more, pool.roll], [5, all - 5, null], "pool: 5 sub-agents, the rest counted, not listed again as members");
  const ops = C("team-operations");
  assert.deepStrictEqual([ops.roll.length, ops.rollMore], [5, 1], "operations: 5 members, +1 more");
  ok(`${cards.length} cards, ${kinds.size} kinds: no Held files list, no Full path row, no path; Files held one row; lists ≤ 5 + more; rows ≤ 80 chars`);
}

/* Opens every card at w×h through the list and the chips on cards; each fits (1366: no inner scroll, inside the viewport; 400: ≤ one screen), no row over 2 lines. */
async function fit(b, base, w, h) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 })).newPage(), errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector('.office .olist [data-who="tiny-epic-narrator"]', { state: "attached", timeout: 20000 });
  const R = await p.evaluate(() => {
    const route = {}, out = {};
    for (const x of document.querySelectorAll(".office .olist [data-who]")) route[x.dataset.who] = route[x.dataset.who] || [x.dataset.who];
    const todo = Object.keys(route);
    while (todo.length) {
      const id = todo.shift();
      if (out[id]) continue;
      const o = document.getElementById("office-card");
      if (o && o.matches(":popover-open")) o.hidePopover();
      document.querySelector(`.office .olist [data-who="${CSS.escape(route[id][0])}"]`).click();
      for (const k of route[id].slice(1)) document.querySelector(`#office-card [data-who="${CSS.escape(k)}"]`).click();
      const c = document.getElementById("office-card"), r = c.getBoundingClientRect();
      const tall = [...c.querySelectorAll("dd, .chip span, .ln")].filter((e) => e.getBoundingClientRect().height > parseFloat(getComputedStyle(e).fontSize) * 3.2 + 1).map((e) => e.textContent.slice(0, 40));
      out[id] = { h: Math.round(r.height), sh: c.scrollHeight, ch: c.clientHeight, top: Math.round(r.top), bottom: Math.round(r.bottom), heads: [...c.querySelectorAll("h3")].map((e) => e.textContent),
        full: [...c.querySelectorAll("dt")].filter((e) => e.textContent === "Full path").length, more: [...c.querySelectorAll(".more")].map((e) => e.textContent), tall };
      for (const k of [...c.querySelectorAll("[data-who]")].map((e) => e.dataset.who)) if (!route[k]) { route[k] = [...route[id], k]; todo.push(k); }
    }
    return out;
  });
  const ids = Object.keys(R);
  assert.ok(ids.includes("orchestrator") && ids.includes("room-tiny-epic-narrator") && ids.includes("team-operations") && ids.includes("pool"), `${w}: the CEO, a seat room, a team and the pool are reached`);
  for (const [id, c] of Object.entries(R)) {
    assert.ok(!c.heads.includes("Held files") && !c.full, `${w} ${id}: no Held files list, no Full path row`);
    assert.deepStrictEqual(c.tall, [], `${w} ${id}: rows over 2 lines`);
    if (w > 600) assert.ok(c.sh <= c.ch + 1 && c.top >= 0 && c.bottom <= h, `${w}x${h} ${id}: fits with no inner scroll ${JSON.stringify(c)}`);
    else assert.ok(c.sh <= h, `${w}x${h} ${id}: content ${c.sh} px is more than one screen`);
  }
  assert.deepStrictEqual([R.pool.more.length, /^\+[1-9]\d* more$/.test(R.pool.more[0]), R["team-operations"].more], [1, true, ["+1 more", "+1 more"]], `${w}: "+N more" under a long list (operations: members, next runs) ${JSON.stringify(R.pool.more)}`);
  assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll`);
  assert.deepStrictEqual(errs, []);
  ok(`${w}x${h}: ${ids.length} cards, tallest ${Math.max(...Object.values(R).map((c) => c.sh))} px, no inner scroll${w > 600 ? "" : " beyond one screen"}, no row over 2 lines, +N more`);
  await p.context().close();
}

(async () => {
  if (!ONLY || ONLY === "pure") await pure();
  if (ONLY === "pure") return;
  const srv = serveStatic((u) => {
    if (u === "/api/status") return STATUS;
    if (u === "/api/office") return HEAVY;
    if (u === "/api/org") return { seats: HEAVY.seats, sessions: HEAVY.sessions, hidden: 0 };
    if (u === "/api/agents") return { ...HEAVY.agents, agents: [], roster: [] };
    if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + srv.address().port, b = await chromium.launch({ headless: true, args: ["--mute-audio"] });
  try { for (const [w, h] of [[1366, 768], [400, 800]]) if (!ONLY || ONLY === String(w)) await fit(b, base, w, h); }
  finally { await b.close(); srv.close(); }
  console.log(`ok test_office_card_minimal: ${n} checks`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
