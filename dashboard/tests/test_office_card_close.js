// Office card lifetime and fit (T1601-23, owner 2026-11-11: "it took me to the chat now I can not close the modal ... I cannot scroll down the modal"):
// the card closes and its node goes on every way out of the Office (Message, a tab, back/forward, a hash change); ×, Esc and a click outside close it
// after every open path; with Details open, every card kind at 1366x768, 400x800 and 1366x480 stays inside the window, scrolls inside (wheel, keyboard), keeps × in view
// and the page behind does not scroll.
// Run: node tests/test_office_card_close.js   (fixture API only, no GPU; ONLY=leave|close|1366|400|1366x480)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ONLY = process.env.ONLY || "", KINDS = ["orchestrator", "tiny-epic-narrator", "team-operations", "pool", "sentinel"];
let n = 0;
const ok = (name) => console.log("ok " + ++n + " " + name);

/* A page on #org at w×h with the list ready; page errors are kept on p.errs. */
async function office(b, base, w, h) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 })).newPage();
  p.errs = []; p.on("pageerror", (e) => p.errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector('.office .olist [data-who="orchestrator"]', { state: "attached", timeout: 20000 });
  return p;
}
/* Opens the card of id from its list name button scrolled to the bottom of the window (the lowest anchor), else through a chip of another card. */
const openFromList = (p, id) => p.evaluate((id) => {
  const hide = () => { const o = document.getElementById("office-card"); if (o && o.matches(":popover-open")) o.hidePopover(); };
  const btn = (k) => { const q = `.office .olist [data-who="${CSS.escape(k)}"]`; return document.querySelector(q + ":not(.avb)") || document.querySelector(q); };
  hide();
  const bt = btn(id);
  if (bt) { bt.scrollIntoView({ block: "end" }); bt.click(); return !!document.querySelector("#office-card:popover-open"); }
  for (const k of new Set([...document.querySelectorAll(".office .olist [data-who]")].map((e) => e.dataset.who))) {
    hide(); btn(k).click();
    const chip = document.querySelector(`#office-card [data-who="${CSS.escape(id)}"]`);
    if (chip) { chip.click(); return document.getElementById("office-card").dataset.for === id; }
  }
  return false;
}, id);
const cards = (p) => p.evaluate(() => document.querySelectorAll("#office-card, .ocard").length);
const shown = (p) => p.evaluate(() => !!document.querySelector("#office-card:popover-open"));
const screen = (p, id) => p.waitForFunction((id) => location.hash.startsWith("#" + id) && !!document.querySelector("#grid > .nxs:not(.office), #grid > :not(h1):not(.nxs)"), id, { timeout: 10000 });

/* Every way out of the Office takes the card and its node with it. */
async function leave(b, base) {
  const p = await office(b, base, 1366, 768);
  assert.ok(await openFromList(p, "orchestrator"), "the CEO card opens");
  await p.click("#office-card a.btn");
  await screen(p, "chat");
  assert.strictEqual(await cards(p), 0, "Message DarkSaddler: Chat shows and no card node remains");
  await p.evaluate(() => document.querySelector('a[data-nav="org"]').click());
  await p.waitForSelector('.office .olist [data-who="orchestrator"]', { state: "attached" });
  await openFromList(p, "sentinel");
  await p.evaluate(() => document.querySelector('a[data-nav="chat"]').click());
  await screen(p, "chat");
  assert.strictEqual(await cards(p), 0, "the Chat tab: no card node remains");
  await p.goBack(); await p.waitForSelector('.office .olist [data-who="orchestrator"]', { state: "attached" });
  await openFromList(p, "team-operations");
  await p.goForward(); await screen(p, "chat");
  assert.strictEqual(await cards(p), 0, "browser forward: no card node remains");
  await p.goBack(); await p.waitForSelector('.office .olist [data-who="orchestrator"]', { state: "attached" });
  await openFromList(p, "tiny-epic-narrator");
  await p.evaluate(() => { location.hash = "#sites"; });
  await screen(p, "sites");
  assert.strictEqual(await cards(p), 0, "a hash change: no card node remains");
  await p.evaluate(() => { location.hash = "#org"; });
  await p.waitForSelector('.office .olist [data-who="orchestrator"]', { state: "attached" });
  assert.ok(await openFromList(p, "orchestrator"), "the card opens again after coming back");
  assert.deepStrictEqual(p.errs, []);
  ok("Message, Chat tab, forward and a hash change leave 0 card nodes; the card opens again on return");
  await p.context().close();
}

/* ×, Esc and a click outside close the card after a list button, a chip in the card and a refresh with Details open. */
async function closes(b, base) {
  const p = await office(b, base, 1366, 768), ways = [];
  const paths = {
    list: () => openFromList(p, "team-operations"),
    chip: async () => { await openFromList(p, "team-operations"); await p.evaluate(() => document.querySelector("#office-card [data-who]").click()); },
    details: async () => { await openFromList(p, "orchestrator"); await p.click("#office-card .cdet > summary"); },
  };
  const how = {
    x: () => p.click("#office-card .cx"),
    esc: async () => { await p.focus("#office-card"); await p.keyboard.press("Escape"); },
    outside: () => p.mouse.click(1350, 760),
  };
  for (const [pk, open] of Object.entries(paths)) for (const [hk, close] of Object.entries(how)) {
    await open();
    assert.ok(await shown(p), `${pk}: the card is open`);
    await close();
    assert.ok(!(await shown(p)), `${pk} then ${hk}: the card closes`);
    assert.ok(await p.evaluate(() => location.hash.startsWith("#org")), `${pk} then ${hk}: still on the Office`);
    ways.push(pk + "/" + hk);
  }
  assert.deepStrictEqual(p.errs, []);
  ok(`× , Esc and a click outside close the card: ${ways.join(", ")}`);
  await p.context().close();
}

/* With Details open, every card kind at w×h: inside the window, the last row scrolls into view by wheel and End, × stays in view, the page stays put. */
async function fit(b, base, w, h) {
  const p = await office(b, base, w, h), out = [];
  for (const id of KINDS) {
    assert.ok(await openFromList(p, id), `${w} ${id}: the card opens`);
    if (await p.$("#office-card .cdet")) await p.click("#office-card .cdet > summary");
    await p.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    const box = await p.$eval("#office-card", (c) => { const r = c.getBoundingClientRect(); return { top: r.top, bottom: r.bottom, x: r.left + r.width / 2, y: r.top + r.height / 2, over: c.scrollHeight > c.clientHeight + 1 }; });
    assert.ok(box.top >= 0 && box.bottom <= h, `${w}x${h} ${id}: the card ${Math.round(box.top)}-${Math.round(box.bottom)} px is inside the window`);
    const page = await p.evaluate(() => scrollY);
    await p.mouse.move(box.x, box.y);
    for (let i = 0; i < 30 && box.over; i++) await p.mouse.wheel(0, 300);
    await p.waitForTimeout(150);
    const r = await p.$eval("#office-card", (c) => {
      const last = [...c.querySelectorAll("dd, .chip, .quiet, .more, summary")].pop().getBoundingClientRect(), x = c.querySelector(".cx").getBoundingClientRect(), cb = c.getBoundingClientRect();
      return { last: last.bottom, lastTop: last.top, cb: cb.bottom, x: [x.top, x.bottom], st: c.scrollTop, end: c.scrollHeight - c.clientHeight };
    });
    assert.ok(r.last <= r.cb + 1 && r.lastTop >= 0, `${w}x${h} ${id}: the last row (${Math.round(r.lastTop)}-${Math.round(r.last)}) scrolled into the card (bottom ${Math.round(r.cb)})`);
    assert.ok(r.x[0] >= 0 && r.x[1] <= h, `${w}x${h} ${id}: × in the window after scrolling (${Math.round(r.x[0])}-${Math.round(r.x[1])})`);
    assert.strictEqual(await p.evaluate(() => scrollY), page, `${w}x${h} ${id}: the page behind did not scroll`);
    if (box.over) {
      await p.$eval("#office-card", (c) => { c.scrollTop = 0; c.focus(); });
      await p.keyboard.press("End");
      await p.waitForTimeout(150);
      assert.ok(await p.$eval("#office-card", (c) => c.scrollTop >= c.scrollHeight - c.clientHeight - 2), `${w}x${h} ${id}: End scrolls the card to its last row`);
    }
    out.push(id + (box.over ? " (scrolls)" : ""));
  }
  assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll`);
  assert.deepStrictEqual(p.errs, []);
  ok(`${w}x${h}: Details open, ${out.join(", ")}: inside the window, last row reachable, × in view, the page stays`);
  await p.context().close();
}

(async () => {
  const srv = serveStatic((u) => {
    if (u === "/api/status") return STATUS;
    if (u === "/api/office") return FIX;
    if (u === "/api/org") return { seats: FIX.seats, sessions: FIX.sessions, hidden: 0 };
    if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
    if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + srv.address().port, b = await chromium.launch({ headless: true, args: ["--mute-audio"] });
  try {
    if (!ONLY || ONLY === "leave") await leave(b, base);
    if (!ONLY || ONLY === "close") await closes(b, base);
    for (const [w, h] of [[1366, 768], [400, 800], [1366, 480]]) if (!ONLY || ONLY === String(w) || ONLY === `${w}x${h}`) await fit(b, base, w, h);
  } finally { await b.close(); srv.close(); }
  console.log(`ok test_office_card_close: ${n} checks`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
