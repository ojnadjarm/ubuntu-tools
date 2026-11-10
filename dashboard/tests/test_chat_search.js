// Chat search (T1545-D): the "Search messages" box over the channel list, 250 ms debounce and one request per query, results with
// the words marked (text only, a "<" stays text), channel tag opens the channel, Esc / cleared box / back arrow return, "/" focuses,
// cold #chat?q=, 400 and failures shown as text, the phone list at 400 (box 44 px, no sideways scroll, browser back), shots at 5 widths.
// Run: node tests/test_chat_search.js   (fixture API only; SHOTS=<dir> also writes search-<w>.png)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "mooblox", name: "Mooblox", role: "po", parent: "orchestrator", wake: "po-inbox", match: null }], sessions: [], hidden: 0 };
const T0 = Date.UTC(2026, 10, 9, 21, 0);
const row = (id, ch, from, text, kind = "msg") => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind, text, re: null, hop: 0 });
const STORE = {
  harness: [row(T0, "harness", "mooblox", "how do I drop a link?", "ask"), row(T0 + 1000, "harness", "orchestrator", "use drop-link: https://x.test/drop-link", "answer")],
  org: [row(T0 + 2000, "org", "orchestrator", "a <b>drop</b> of rain, no link"), row(T0 + 3000, "org", "mooblox", "nothing here")],
  "dm-mooblox--owner": [row(T0 + 4000, "dm-mooblox--owner", "owner", "Drop the LINK here")],
};
const asked = [];
const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const ch = q.get("ch") || "", after = +(q.get("after") || 0), all = Object.values(STORE).flat().sort((a, b) => a.id - b.id);
    return { messages: (ch ? STORE[ch] || [] : all).filter((m) => m.id > after), channels: Object.keys(STORE).map((c) => ({ ch: c, unread: 0 })), wakes: { today: {} }, thinking: [] };
  }
  if (u === "/api/chat/search") {
    const w = q.get("q") || "";
    asked.push(w);
    const fail = (code, error) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify({ error })); };
    if (w === "bad words") return fail(400, "bad <b>q</b>");
    if (w === "boom") return fail(500, "store unreadable");
    const ws = w.toLowerCase().split(/\s+/).filter(Boolean);
    return { q: w, messages: Object.values(STORE).flat().filter((m) => ws.every((x) => m.text.toLowerCase().includes(x))).sort((a, b) => a.id - b.id) };
  }
});
const h2 = (p) => p.textContent(".chat .stream header h2");
const wait = (p, f, arg) => p.waitForFunction(f, arg, { timeout: 6000 });

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  const errs = [];
  try {
    if (process.env.SHOTS) {
      for (const [w, h] of [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]]) {
        const c = await b.newContext({ viewport: { width: w, height: h } }), p = await c.newPage();
        await p.goto(base + "/#chat?q=drop%20link", { waitUntil: "load" });
        await p.waitForSelector(".chat .stream header h2", { state: "attached", timeout: 15000 });
        await p.waitForTimeout(1500);
        await p.screenshot({ path: `${process.env.SHOTS}/search-${w}.png` });
        await c.close();
      }
    }
    asked.length = 0;

    const ctx = await b.newContext({ viewport: { width: 1366, height: 768 } }), p = await ctx.newPage();
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto(base + "/#chat?ch=org", { waitUntil: "load" });
    await wait(p, () => (document.querySelector(".chat .stream header h2") || {}).textContent === "# org");
    const sq = ".chat .chans .csq input";
    assert.strictEqual(await p.getAttribute(sq, "aria-label"), "Search messages", "the box over the channel list is labelled Search messages");
    assert.ok(await p.$eval(sq, (e) => e.getBoundingClientRect().top < document.querySelector('.chat .chans a[data-ch=""]').getBoundingClientRect().top), "the box sits at the top of the list");
    await p.click(".chat .stream header h2");
    await p.keyboard.press("/");
    assert.ok(await p.$eval(sq, (e) => e === document.activeElement && e.value === ""), "/ focuses the box and is not typed");

    await p.keyboard.type("drop link", { delay: 40 });
    await wait(p, () => /results? for drop link/.test(document.querySelector(".chat .stream header h2").textContent));
    assert.strictEqual(await h2(p), "4 results for drop link", "N results for <words>");
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?q=drop%20link", "the search view has its own hash");
    assert.deepStrictEqual(asked, ["drop link"], "one request for the whole typed query (debounced)");
    assert.strictEqual(await p.$$eval(".chat .compose", (l) => l.length), 0, "no composer in the search view");
    const res = await p.$$eval(".chat .msg", (l) => l.map((m) => ({ who: m.querySelector(".who b").textContent, tag: (m.querySelector(".chtag") || {}).dataset?.ch, time: !!m.querySelector("time"),
      marks: [...m.querySelectorAll(".tx mark")].map((k) => k.textContent), tx: m.querySelector(".tx").textContent, b: !!m.querySelector(".tx b"), href: (m.querySelector(".tx a") || {}).href || "" })));
    assert.deepStrictEqual(res.map((r) => [r.who, r.tag, r.time]), [["Mooblox", "harness", true], ["Orchestrator", "harness", true], ["Orchestrator", "org", true], ["You", "dm-mooblox--owner", true]], "rows in Recent's shape: sender, channel tag, time");
    assert.deepStrictEqual(res.map((r) => r.marks), [["drop", "link"], ["drop", "link", "drop", "link"], ["drop", "link"], ["Drop", "LINK"]], "each matched word marked, any case");
    assert.strictEqual(res[1].href, "https://x.test/drop-link", "a link keeps its href (marks only in text, never in a tag)");
    assert.strictEqual(await p.$eval(".chat .msg .tx mark", (e) => getComputedStyle(e).color), "rgb(255, 209, 102)", "marks use the gold token");
    await p.waitForTimeout(3500);
    assert.deepStrictEqual(asked, ["drop link"], "no polling of the search");

    await p.fill(sq, "rain");
    await wait(p, () => document.querySelector(".chat .stream header h2").textContent === "1 result for rain");
    assert.ok(await p.$eval(".chat .msg .tx", (e) => e.textContent === "a <b>drop</b> of rain, no link" && !e.querySelector("b") && e.querySelector("mark").textContent === "rain"), "a < in a result stays text");
    await p.click('.chat .msg .chtag[data-ch="org"]');
    await wait(p, () => document.querySelector(".chat .stream header h2").textContent === "# org");
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=org", "the channel tag opens the channel");
    assert.strictEqual(await p.inputValue(sq), "", "opening a channel clears the box");

    await p.click('.chat .chans a[data-ch="harness"]');
    await wait(p, () => document.querySelector(".chat .stream header h2").textContent === "# harness");
    await p.fill(sq, "zzz");
    await wait(p, () => document.querySelector(".chat .msgs").textContent === "No message has zzz.");
    await p.press(sq, "Escape");
    await wait(p, () => document.querySelector(".chat .stream header h2").textContent === "# harness");
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=harness", "Esc returns to the channel he came from");
    assert.strictEqual(await p.inputValue(sq), "", "Esc clears the box");
    await p.fill(sq, "bad words");
    await wait(p, () => /Search failed: bad <b>q<\/b>/.test(document.querySelector(".chat .msgs").textContent));
    assert.strictEqual(await p.$$eval(".chat .msgs b", (l) => l.length), 0, "a 400's message is shown as text");
    await p.fill(sq, "boom");
    await wait(p, () => document.querySelector(".chat .msgs").textContent === "Search failed: store unreadable");
    await p.fill(sq, "");
    await wait(p, () => document.querySelector(".chat .stream header h2").textContent === "# harness");
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=harness", "clearing the box returns");
    assert.deepStrictEqual(errs, [], "no page errors");
    await ctx.close();

    const c2 = await b.newContext({ viewport: { width: 1920, height: 1080 } }), q = await c2.newPage();
    q.on("pageerror", (e) => errs.push(String(e)));
    await q.goto(base + "/#chat?q=link", { waitUntil: "load" });
    await wait(q, () => (document.querySelector(".chat .stream header h2") || {}).textContent === "4 results for link");
    assert.strictEqual(await q.inputValue(sq), "link", "a cold #chat?q= deep link opens the search with the box filled");
    await q.click(".chat .stream header h2");
    await q.keyboard.press("Escape");
    await wait(q, () => (document.querySelector(".chat .stream header h2") || {}).textContent === "Recent");
    assert.strictEqual(await q.evaluate(() => location.hash), "#chat", "Esc (focus outside the box) from a deep link returns to Recent, Chat stays");
    await c2.close();

    const c3 = await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true }), r = await c3.newPage();
    r.on("pageerror", (e) => errs.push(String(e)));
    await r.goto(base + "/#chat", { waitUntil: "load" });
    await r.waitForSelector(".chat.list .chans .csq input", { timeout: 15000 });
    const geo = await r.$eval(sq, (e) => ({ h: e.getBoundingClientRect().height, side: document.documentElement.scrollWidth <= innerWidth }));
    assert.ok(geo.h >= 44 && geo.side, `phone list: box ${geo.h} px >= 44, no sideways scroll`);
    await r.tap(sq);
    await r.keyboard.type("drop");
    await wait(r, () => document.querySelector(".chat.conv") && document.querySelector(".chat .stream header h2").textContent === "4 results for drop");
    assert.ok(await r.evaluate(() => { const a = document.activeElement; return a.matches(".chat .stream header .csq input") && a.value === "drop" && a.checkVisibility({ visibilityProperty: true }); }), "on the phone typing goes on in the search header");
    assert.ok(await r.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "phone search view: no sideways scroll");
    await r.goBack();
    await wait(r, () => !!document.querySelector(".chat.list"));
    assert.strictEqual(await r.evaluate(() => location.hash), "#chat", "browser back returns to the phone list");
    assert.strictEqual(await r.inputValue(sq), "", "and clears the box");
    await r.tap(sq);
    await r.keyboard.type("rain");
    await wait(r, () => document.querySelector(".chat .stream header h2").textContent === "1 result for rain");
    await r.tap(".chat [data-back]");
    await wait(r, () => !!document.querySelector(".chat.list"));
    assert.strictEqual(await r.evaluate(() => location.hash), "#chat", "the back arrow returns to the phone list");
    await c3.close();
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · box at the top of the list, / focuses · 1 request per query, no polling · N results, marks in text only, < stays text · tag opens channel · Esc, cleared box, back arrow, browser back return · cold #chat?q= · 400 and 500 as text · phone 44 px box, typing continues in the header");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
