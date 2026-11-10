// Office card glance (T1601-21, owner 2026-11-10: "keep the card minimalistic"): every card opens with its glance tier only (first line,
// state, Now, next run, gold lines, running sub-agents, team link, Message) and one closed "Details" fold (44 px, keyboard) with every other row;
// opening the fold shows every row the card has; the fold is not kept open into the next card; closed, a card is ≤ 360 px at 1366x768 and ≤ 420 px at 400x800.
// Run: node tests/test_office_card_glance.js   (fixture API only, no GPU; ONLY=pure|1366|400)
"use strict";
const assert = require("assert");
const path = require("path");
const { pathToFileURL } = require("url");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ONLY = process.env.ONLY || "", MAXH = { 1366: 360, 400: 420 };
const JS = path.join(process.env.STATIC_ROOT || path.join(__dirname, "..", "static"), "next", "js");
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
let n = 0;
const ok = (name) => console.log("ok " + ++n + " " + name);

/* Every card of the fixture: the two tiers split its rows and parts with nothing lost; the glance rows are Now, a scheduled next run or gold. */
async function pure() {
  const Mo = await load("office/model.js"), F = await load("office/fields.js"), T = await load("office/tier.js"), M = Mo.build(FIX, { needs: true });
  for (const p of Object.values(M.who)) {
    const c = F.card(p), t = T.tiers(c), lines = c.lines || [], parts = c.parts || [];
    assert.deepStrictEqual([...t.top.rows, ...t.fold.rows].length, c.rows.length, p.id + ": every row in one tier");
    assert.deepStrictEqual([...t.top.lines, ...t.fold.lines], lines, p.id + ": every line in one tier");
    assert.strictEqual(t.top.parts.length + t.fold.parts.length, parts.length, p.id + ": every part in one tier");
    assert.ok(t.top.lines.length <= 1, p.id + ": one description line at a glance");
    for (const [k, v, tone] of t.top.rows) assert.ok(tone === "bad" || k === "Now" || (k === "Next run" && /^in /.test(v)), `${p.id}: ${k} is not a glance row`);
    for (const x of t.top.parts) assert.ok(["Sub-agents running", "Needs you"].includes(x.h) && x.rows.length + x.chips.length > 0, `${p.id}: ${x.h} is not a glance part`);
    assert.ok(!c.roll || t.fold.roll, p.id + ": Members in the fold");
  }
  ok(`${Object.keys(M.who).length} cards: glance rows only Now, next run, gold; nothing lost between the tiers`);
}

/* Opens every card at w×h through the list and chips: closed fold height, glance-only visible rows, fold 44 px; opened, every row shows; not kept into the next card. */
async function fit(b, base, w, h) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 })).newPage(), errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector('.office .olist [data-who="tiny-epic-narrator"]', { state: "attached", timeout: 20000 });
  const R = await p.evaluate(() => {
    const route = {}, out = {}, seen = (e) => e.checkVisibility();
    for (const x of document.querySelectorAll(".office .olist [data-who]")) route[x.dataset.who] = route[x.dataset.who] || [x.dataset.who];
    const todo = Object.keys(route);
    while (todo.length) {
      const id = todo.shift();
      if (out[id]) continue;
      const o = document.getElementById("office-card");
      if (o && o.matches(":popover-open")) o.hidePopover();
      document.querySelector(`.office .olist [data-who="${CSS.escape(route[id][0])}"]`).click();
      for (const k of route[id].slice(1)) document.querySelector(`#office-card [data-who="${CSS.escape(k)}"]`).click();
      const c = document.getElementById("office-card"), d = c.querySelector("details.cdet"), all = [...c.querySelectorAll("dt")];
      const r = { h: Math.round(c.getBoundingClientRect().height), sh: c.scrollHeight, open: !!(d && d.open), sum: d ? Math.round(d.querySelector("summary").getBoundingClientRect().height) : 0,
        top: all.filter(seen).map((e) => [e.textContent, e.nextElementSibling.className]), rows: all.length, ln: [...c.querySelectorAll(".cbody > .ln")].map((e) => Math.round(e.getBoundingClientRect().height / parseFloat(getComputedStyle(e).lineHeight))) };
      if (d) { d.querySelector("summary").click(); r.after = all.filter(seen).length; r.hidden = [...c.querySelectorAll("dt, .chip, .ln, h3")].filter((e) => !seen(e)).length; }
      out[id] = r;
      for (const k of [...c.querySelectorAll("[data-who]")].map((e) => e.dataset.who)) if (!route[k]) { route[k] = [...route[id], k]; todo.push(k); }
    }
    return out;
  });
  const ids = Object.keys(R);
  assert.ok(["orchestrator", "tiny-epic-narrator", "team-operations", "pool", "sentinel"].every((id) => ids.includes(id)), `${w}: CEO, seat, team, pool and staff cards reached`);
  for (const [id, c] of Object.entries(R)) {
    assert.ok(!c.open, `${w} ${id}: the fold starts closed`);
    assert.ok((w > 600 ? c.h : c.sh) <= MAXH[w], `${w}x${h} ${id}: ${w > 600 ? c.h : c.sh} px with the fold closed (> ${MAXH[w]})`);
    for (const [k, tone] of c.top) assert.ok(tone === "bad" || ["Now", "Next run"].includes(k), `${w} ${id}: ${k} shows at a glance`);
    assert.ok(c.ln.every((l) => l <= 1), `${w} ${id}: description cut to one line ${JSON.stringify(c.ln)}`);
    if (c.rows > c.top.length) assert.ok(c.sum >= 44, `${w} ${id}: Details fold ${c.sum} px (< 44) or missing`);
    if (c.sum) assert.deepStrictEqual([c.after, c.hidden], [c.rows, 0], `${w} ${id}: every row shows once the fold is open`);
  }
  await p.evaluate(() => document.querySelector('.office .olist [data-who="tiny-epic-narrator"]').click());
  await p.click("#office-card .cdet > summary");
  await p.evaluate(() => document.querySelector('.office .olist [data-who="sentinel"]').click());
  assert.strictEqual(await p.$eval("#office-card .cdet", (d) => d.open), false, `${w}: the next card opens with its fold closed`);
  await p.focus("#office-card");
  for (let i = 0; i < 20 && !(await p.evaluate(() => !!document.activeElement.closest("#office-card summary"))); i++) await p.keyboard.press("Tab");
  await p.keyboard.press("Enter");
  assert.strictEqual(await p.$eval("#office-card .cdet", (d) => d.open), true, `${w}: Tab reaches Details, Enter opens it`);
  assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll`);
  assert.deepStrictEqual(errs, []);
  ok(`${w}x${h}: ${ids.length} cards, tallest closed ${Math.max(...Object.values(R).map((c) => (w > 600 ? c.h : c.sh)))} px (≤ ${MAXH[w]}), glance rows only, Details ≥ 44 px, every row once open, closed on the next card, keyboard`);
  await p.context().close();
}

(async () => {
  if (!ONLY || ONLY === "pure") await pure();
  if (ONLY === "pure") return;
  const srv = serveStatic((u) => {
    if (u === "/api/status") return STATUS;
    if (u === "/api/office") return FIX;
    if (u === "/api/org") return { seats: FIX.seats, sessions: FIX.sessions, hidden: 0 };
    if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
    if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + srv.address().port, b = await chromium.launch({ headless: true, args: ["--mute-audio"] });
  try { for (const [w, h] of [[1366, 768], [400, 800]]) if (!ONLY || ONLY === String(w)) await fit(b, base, w, h); }
  finally { await b.close(); srv.close(); }
  console.log(`ok test_office_card_glance: ${n} checks`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
