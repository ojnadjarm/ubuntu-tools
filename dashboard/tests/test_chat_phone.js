// Chat on the phone (T1515-P39): below 900 px a messenger list (Recent, rooms, direct messages; rows by last activity, preview, time,
// unread, thinking dots, >= 44 px), a tap opens one conversation full screen (back arrow, Familiar, state, composer on the dock),
// back returns to the list at its scroll, deep link + browser back; the page never scrolls and a new message never moves the stream
// unless he is at its end (else a "new messages" pill), at 400 and at 1366.
// Run: node tests/test_chat_phone.js   (fixture API only: every POST lands in this file's server)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const PO = ["mooblox", "discord", "alpha", "beta", "gamma", "delta", "eps", "zeta"];
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  ...PO.map((id) => ({ id, name: id[0].toUpperCase() + id.slice(1), role: "po", parent: "orchestrator", wake: "po-inbox", match: "~/agents/po-" + id }))], sessions: [], hidden: 0 };
const T0 = Date.now() - 3600e3;
const row = (id, ch, from, text) => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind: "msg", text, re: null, hop: 0 });
const STORE = {
  harness: [row(T0, "harness", "mooblox", "how do I drop a link?")],
  org: Array.from({ length: 60 }, (_, i) => row(T0 + 1000 + i, "org", i % 2 ? "discord" : "orchestrator", "line " + i + " of a long thread")),
  attic: [row(T0 - 40 * 864e5, "attic", "mooblox", "a note from last month")],
  "dm-discord--owner": [row(T0 + 5000, "dm-discord--owner", "owner", "ship the relay\nplease, today")],
};
let thinking = [];
/* What chat_store.channels() gives per channel: its newest message, text clipped, attachments counted. */
const lastOf = (rows) => { const m = rows[rows.length - 1]; return { id: m.id, from: m.from, ts: m.ts, kind: m.kind, text: m.text.slice(0, 80), files: 0 }; };
const next = () => STORE.org[STORE.org.length - 1].id + 1000;
const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const ch = q.get("ch") || "", after = +(q.get("after") || 0);
    const rows = ch ? STORE[ch] || [] : Object.values(STORE).flat().sort((a, b) => a.id - b.id).slice(-50);
    return { messages: rows.filter((m) => m.id > after), channels: Object.keys(STORE).map((c) => ({ ch: c, unread: c === "harness" ? 1 : 0, last: lastOf(STORE[c]) })), wakes: { today: {} }, thinking };
  }
});
const posted = [];
const files = srv.listeners("request")[0];
srv.removeAllListeners("request");
srv.on("request", (req, res) => { if (req.method === "POST") { posted.push(req.url); return res.end('{"ok":true}'); } files(req, res); });

/* A new message lands in org; the stream must not move while he reads above it, and the page never scrolls. */
async function keepsPlace(p, label) {
  await p.waitForFunction(() => { const b = document.querySelector(".chat .msgs"); return b && b.scrollHeight > b.clientHeight + 200; }, null, { timeout: 8000 });
  await p.evaluate(() => { document.querySelector(".chat .msgs").scrollTop = 40; });
  await p.waitForTimeout(300);
  const before = await p.evaluate(() => ({ y: scrollY, top: document.querySelector(".chat .msgs").scrollTop }));
  STORE.org.push(row(next(), "org", "discord", "a new line while he reads above"));
  await p.waitForSelector(".chat .newer:not([hidden])", { timeout: 8000 });
  const after = await p.evaluate(() => ({ y: scrollY, top: document.querySelector(".chat .msgs").scrollTop }));
  assert.deepStrictEqual(after, before, label + ": a new message while scrolled up keeps window.scrollY and the stream's scrollTop");
  assert.match(await p.textContent(".chat .newer"), /1 new message ↓/, label + ": the pill counts it");
  await p.click(".chat .newer");
  await p.waitForFunction(() => { const b = document.querySelector(".chat .msgs"); return b.scrollHeight - b.scrollTop - b.clientHeight < 40; }, null, { timeout: 3000 });
  assert.ok(await p.$eval(".chat .newer", (e) => e.hidden), label + ": the pill jumps to the end and goes");
  STORE.org.push(row(next(), "org", "discord", "and one more at the end"));
  await p.waitForFunction(() => [...document.querySelectorAll(".chat .msg .tx")].some((e) => e.textContent === "and one more at the end"), null, { timeout: 8000 });
  await p.waitForTimeout(100);
  assert.ok(await p.evaluate(() => { const b = document.querySelector(".chat .msgs"); return b.scrollHeight - b.scrollTop - b.clientHeight < 40; }), label + ": at the end it follows the newest line");
  assert.strictEqual(await p.evaluate(() => scrollY), before.y, label + ": the page did not scroll");
}

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const ctx = await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true });
    const p = await ctx.newPage(), errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    thinking = [{ seat: "discord", ch: "dm-discord--owner", state: "thinking", since: 1 }];

    await p.goto(base + "/#chat", { waitUntil: "load" });
    await p.waitForSelector(".chat.list .chans a .tm", { timeout: 15000 });
    await p.waitForFunction(() => document.querySelectorAll(".chat .chans .tm").length >= 5, null, { timeout: 8000 });
    assert.ok(await p.$eval(".chat .stream", (e) => getComputedStyle(e).display === "none"), "the list view shows no stream");
    const rows = await p.$$eval(".chat .chans a", (as) => as.map((a) => { const r = a.getBoundingClientRect(); return { ch: a.dataset.ch, x: Math.round(r.left), w: Math.round(r.width), h: r.height }; }));
    assert.deepStrictEqual(rows.slice(0, 4).map((r) => r.ch), ["", "org", "harness", "attic"], "Recent first, then rooms by last activity, channels outside Recent's 50 too");
    assert.strictEqual(rows.find((r) => r.ch.startsWith("dm-")).ch, "dm-discord--owner", "direct messages by last activity");
    assert.ok(rows.every((r) => r.h >= 44 && r.x === rows[0].x && r.w === rows[0].w), "full-width vertical rows, tap targets >= 44 px");
    const dm = await p.$eval('.chat .chans [data-ch="dm-discord--owner"]', (a) => ({ fam: !!a.querySelector(".fam svg.cr"), pv: a.querySelector(".pv").textContent, pvW: a.querySelector(".pv").scrollHeight <= a.querySelector(".pv").clientHeight + 1, dots: a.querySelectorAll(".think .dots i").length, tm: a.querySelector(".tm").textContent }));
    assert.deepStrictEqual([dm.fam, dm.pv, dm.pvW, dm.dots, /^\d\d:\d\d$/.test(dm.tm)], [true, "You: ship the relay please, today", true, 3, true], "a row: Familiar, one-line preview, time, thinking dots");
    assert.strictEqual(await p.textContent('.chat .chans [data-ch="harness"] .unread'), "1", "unread badge on its row");
    assert.match(await p.textContent('.chat .chans [data-ch="harness"] .pv'), /^Mooblox: how do I drop a link\?$/, "room preview names the sender");
    const attic = await p.$eval('.chat .chans [data-ch="attic"]', (a) => [a.querySelector(".pv").textContent, a.querySelector(".tm").textContent]);
    assert.deepStrictEqual(attic, ["Mooblox: a note from last month", new Date(T0 - 40 * 864e5).toLocaleDateString("en-GB", { day: "numeric", month: "short" })], "a channel older than Recent's 50: preview and day from its last message");
    assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), 400, "no sideways scroll");

    await p.evaluate(() => scrollTo(0, 260));
    const listY = await p.evaluate(() => scrollY);
    assert.ok(listY > 100, "the list scrolls as a page");
    await p.tap('.chat .chans [data-ch="org"]');
    await p.waitForSelector(".chat.conv", { timeout: 5000 });
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=org", "a tap opens the conversation in the hash");
    const conv = await p.evaluate(() => {
      const s = document.querySelector(".chat .stream").getBoundingClientRect(), h = document.querySelector(".chat .stream header").getBoundingClientRect();
      const c = document.querySelector(".chat .compose").getBoundingClientRect(), d = document.querySelector(".dock").getBoundingClientRect(), r = document.getElementById("rail").getBoundingClientRect();
      const back = document.querySelector(".chat .back").getBoundingClientRect();
      return { top: Math.round(s.top - r.bottom), head: Math.round(h.top - r.bottom), foot: Math.round(d.top - c.bottom), w: Math.round(s.width), back: back.width >= 44 && back.height >= 44, h2: document.querySelector(".chat .stream header h2").textContent, over: getComputedStyle(document.documentElement).overflowY };
    });
    assert.deepStrictEqual(conv, { top: 0, head: 0, foot: 0, w: 400, back: true, h2: "# org", over: "hidden" }, "full screen: header under the bar, composer on the dock, page locked");
    await keepsPlace(p, "400");

    await p.tap(".chat [data-back]");
    await p.waitForSelector(".chat.list", { timeout: 5000 });
    await p.waitForTimeout(200);
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat", "back returns to the list");
    assert.strictEqual(await p.evaluate(() => scrollY), listY, "back returns to the list at the same scroll");

    await p.goto(base + "/#chat", { waitUntil: "load" });
    await p.waitForSelector(".chat.list .chans a", { timeout: 15000 });
    await p.goto(base + "/#chat?ch=dm-discord--owner");
    await p.waitForSelector(".chat.conv", { timeout: 15000 });
    assert.strictEqual(await p.textContent(".chat .stream header h2"), "Discord", "deep link opens the conversation");
    const head = await p.$eval(".chat .stream header", (h) => ({ fam: !!h.querySelector(".hav .fam svg.cr"), st: h.querySelector(".st").textContent, dots: h.querySelectorAll(".st .dots i").length }));
    assert.deepStrictEqual(head, { fam: true, st: "Discord is thinking", dots: 3 }, "header: Familiar, name and thinking state");
    await p.goBack();
    await p.waitForSelector(".chat.list", { timeout: 5000 });
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat", "browser back goes to the list");

    await p.setViewportSize({ width: 1366, height: 768 });
    await p.tap('.chat .chans [data-ch="org"]');
    await p.waitForFunction(() => document.querySelector(".chat .stream header h2").textContent === "# org");
    const desk = await p.evaluate(() => ({ chans: getComputedStyle(document.querySelector(".chat .chans")).visibility, pv: getComputedStyle(document.querySelector(".chat .chans .pv")).display, back: getComputedStyle(document.querySelector(".chat .back")).display, pos: getComputedStyle(document.querySelector(".chat .stream")).position }));
    assert.deepStrictEqual(desk, { chans: "visible", pv: "none", back: "none", pos: "relative" }, "from 900 px the desktop layout: channels left, stream right");
    await keepsPlace(p, "1366");
    assert.deepStrictEqual(posted.filter((u) => !u.startsWith("/api/chat/seen")), [], "nothing posted");
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · phone list (Recent, rooms, DMs by activity; preview, time, unread, dots; >= 44 px) · tap → full-screen conversation · back at the same scroll · deep link + browser back · new message keeps the place, pill, follows at the end (400, 1366)");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
