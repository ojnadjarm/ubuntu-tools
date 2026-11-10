// Chat list scroll (T1550): the channel list, scrolled down to a direct message, keeps its scrollTop (± 1 px) when the row is clicked, on the 3 s poll repaint, through a
// search and its browser back, at 1366, 1920 and 2560; on the phone list (400, 768) back from a conversation returns to the same scrollY.
// Run: node tests/test_chat_list_scroll.js   (fixture API only; ONLY=<width> runs one width; VIDEO=<dir> records the 1366 run)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const PO = Array.from({ length: 40 }, (_, i) => "seat" + String(i).padStart(2, "0"));
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  ...PO.map((id) => ({ id, name: "Spidey " + id, role: "worker", parent: "orchestrator", wake: "pull", match: null }))], sessions: [], hidden: 0 };
const T0 = Date.now() - 3600e3;
const row = (id, ch, from, text) => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind: "msg", text, re: null, hop: 0 });
const STORE = { harness: [row(T0, "harness", "orchestrator", "a line in harness")], org: [row(T0 + 1000, "org", "orchestrator", "a line in org")] };
PO.forEach((id, i) => { STORE["dm-owner--" + id] = [row(T0 + 2000 + i, "dm-owner--" + id, id, "hello from " + id)]; });
const lastOf = (rows) => { const m = rows[rows.length - 1]; return { id: m.id, from: m.from, ts: m.ts, kind: m.kind, text: m.text, files: 0 }; };
const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const ch = q.get("ch") || "", after = +(q.get("after") || 0), all = Object.values(STORE).flat().sort((a, b) => a.id - b.id);
    return { messages: (ch ? STORE[ch] || [] : all.slice(-50)).filter((m) => m.id > after), channels: Object.keys(STORE).map((c) => ({ ch: c, unread: 0, last: lastOf(STORE[c]) })), wakes: { today: {} }, thinking: [] };
  }
  if (u === "/api/chat/search") {
    const w = (q.get("q") || "").toLowerCase();
    return { q: w, messages: Object.values(STORE).flat().filter((m) => m.text.toLowerCase().includes(w)).sort((a, b) => a.id - b.id) };
  }
});
srv.on("request", (req, res) => { if (req.method === "POST" && !res.headersSent) res.end('{"ok":true}'); });
const h2 = (p) => p.textContent(".chat .stream header h2");
const top = (p) => p.$eval(".chat .chans", (e) => e.scrollTop);
/* The direct message with the oldest last message: the lowest messaged row of the list. */
const lowest = () => Object.keys(STORE).filter((c) => c.startsWith("dm-")).sort((a, b) => STORE[a].at(-1).id - STORE[b].at(-1).id)[0];
let base = "";
const near = (a, b, label) => assert.ok(Math.abs(a - b) <= 1, `${label}: list scrollTop ${b} → ${a}`);

/* Desktop at w x h in its own context (VIDEO: recorded at 1366). */
async function desktop(b, w, h) {
  const ctx = await b.newContext({ viewport: { width: w, height: h }, ...(process.env.VIDEO && w === 1366 ? { recordVideo: { dir: process.env.VIDEO, size: { width: w, height: h } } } : {}) });
  try { await steps(await ctx.newPage(), w); } finally { await ctx.close(); }
}
/* Scroll the list down to a direct message, click it, a poll repaint with a new row, a search, browser back. */
async function steps(p, w) {
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#chat?ch=org", { waitUntil: "load" });
  await p.waitForFunction(() => document.querySelectorAll(".chat .chans a[data-ch^='dm-']").length >= 40, null, { timeout: 15000 });
  await p.waitForTimeout(500);
  const dm = await p.$eval(`.chat .chans a[data-ch="${lowest()}"]`, (a) => { a.scrollIntoView({ block: "center" }); return [a.dataset.ch, a.querySelector(".cn").textContent]; });
  await p.waitForTimeout(300);
  const t0 = await top(p);
  assert.ok(t0 > 200, `${w}: the list scrolls (scrollTop ${t0})`);
  await p.click(`.chat .chans a[data-ch="${dm[0]}"]`);
  await p.waitForFunction((n) => document.querySelector(".chat .stream header h2").textContent === n, dm[1], { timeout: 5000 });
  near(await top(p), t0, `${w} click ${dm[1]}`);

  STORE[dm[0]].push(row(Date.now(), dm[0], dm[0].split("--")[1], "a new line on the poll"));
  STORE["room" + w] = [row(Date.now(), "room" + w, "orchestrator", "a new room, one more row")];
  await p.waitForFunction(() => [...document.querySelectorAll(".chat .msg .tx")].some((e) => e.textContent === "a new line on the poll"), null, { timeout: 8000 });
  await p.waitForSelector(`.chat .chans a[data-ch="room${w}"]`, { timeout: 8000 });
  near(await top(p), t0, `${w} poll repaint with a new row`);

  await p.$eval(".chat .chans .csq input", (e) => { e.value = "hello"; e.dispatchEvent(new Event("input", { bubbles: true })); });
  await p.waitForFunction(() => /results? for hello/.test(document.querySelector(".chat .stream header h2").textContent), null, { timeout: 5000 });
  near(await top(p), t0, `${w} search results`);
  await p.goBack();
  await p.waitForFunction((n) => document.querySelector(".chat .stream header h2").textContent === n, dm[1], { timeout: 5000 });
  near(await top(p), t0, `${w} browser back from the search`);
  assert.deepStrictEqual(errs, [], `${w}: no page errors`);
}

/* Phone list (the page scrolls): scroll down, tap a direct message, back arrow and browser back return to the same scrollY. */
async function phone(b, w, h, base) {
  const ctx = await b.newContext({ viewport: { width: w, height: h }, hasTouch: true, isMobile: true }), p = await ctx.newPage();
  await p.goto(base + "/#chat", { waitUntil: "load" });
  await p.waitForFunction(() => document.querySelectorAll(".chat.list .chans a[data-ch^='dm-']").length >= 40, null, { timeout: 15000 });
  const ch = lowest();
  await p.$eval(`.chat .chans a[data-ch="${ch}"]`, (a) => a.scrollIntoView({ block: "center" }));
  await p.waitForTimeout(300);
  const y0 = await p.evaluate(() => scrollY);
  assert.ok(y0 > 200, `${w}: the phone list scrolls (scrollY ${y0})`);
  await p.tap(`.chat .chans a[data-ch="${ch}"]`);
  await p.waitForSelector(".chat.conv", { timeout: 5000 });
  await p.tap(".chat [data-back]");
  await p.waitForSelector(".chat.list", { timeout: 5000 });
  await p.waitForTimeout(200);
  near(await p.evaluate(() => scrollY), y0, `${w} back arrow`);
  await p.waitForTimeout(3500);
  near(await p.evaluate(() => scrollY), y0, `${w} poll repaint on the list`);
  await p.tap(`.chat .chans a[data-ch="${ch}"]`);
  await p.waitForSelector(".chat.conv", { timeout: 5000 });
  await p.goBack();
  await p.waitForSelector(".chat.list", { timeout: 5000 });
  await p.waitForTimeout(200);
  near(await p.evaluate(() => scrollY), y0, `${w} browser back`);
  await ctx.close();
}

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"], slowMo: process.env.VIDEO ? 600 : 0 });
  try {
    const only = (w) => !process.env.ONLY || process.env.ONLY === String(w);
    for (const [w, h] of [[1366, 768], [1920, 1080], [2560, 1440]]) if (only(w)) await desktop(b, w, h);
    for (const [w, h] of [[400, 850], [768, 1024]]) if (only(w)) await phone(b, w, h, base);
    console.log("ok · list scrollTop kept on click, poll repaint, search, browser back (1366, 1920, 2560) · phone list scrollY kept on back arrow, repaint, browser back (400, 768)");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
