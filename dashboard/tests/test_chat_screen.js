// Chat screen (T1515-P10): cold load of #chat?ch=, a direct message per seat, unread badges and /seen, the composer (sent, woke, held), fixed at 400, swipe-proof stream, wakes today.
// P38: wakes today as plain numbers; "<seat> is thinking" / "woken, starting" under the last message and a marker on its channel.
// V3: Familiars in rows, the channel box and the direct list; a new message makes its sender talk for about 2 s.
// Run: node tests/test_chat_screen.js   (fixture API only: every POST lands in this file's server, nothing reaches the real store)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "mooblox", name: "Mooblox", role: "po", parent: "orchestrator", wake: "po-inbox", match: "~/agents/po-mooblox" },
  { id: "discord", name: "Discord", role: "po", parent: "orchestrator", wake: "po-inbox", match: "~/agents/po-discord" },
  { id: "vass", name: "Vass seat", role: "po", parent: "orchestrator", wake: "pull", match: null }], sessions: [], hidden: 0 };
const T0 = Date.UTC(2026, 10, 9, 21, 0);
const row = (id, ch, from, text, kind = "msg") => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind, text, re: null, hop: 0 });
const STORE = {
  harness: [row(T0, "harness", "mooblox", "how do I drop a link?", "ask"), row(T0 + 1000, "harness", "orchestrator", "use drop-link", "answer")],
  org: [row(T0 + 2000, "org", "orchestrator", "one"), row(T0 + 3000, "org", "discord", "two")],
};
let unread = { harness: 0, org: 2 }, posts = [], seen = [], answer = null, thinking = [];

const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const ch = q.get("ch") || "", after = +(q.get("after") || 0);
    return { messages: (STORE[ch] || []).filter((m) => m.id > after), channels: Object.keys(STORE).map((c) => ({ ch: c, unread: unread[c] || 0 })), wakes: { today: { mooblox: 13, orchestrator: 5 } }, thinking };
  }
});
/* The two POSTs: answered from the body once it is read, so the status can be the fixture's (422 for held). */
const files = srv.listeners("request")[0];
srv.removeAllListeners("request");
srv.on("request", (req, res) => {
  const u = req.url.split("?")[0];
  if (req.method !== "POST") return files(req, res);
  let b = "";
  req.on("data", (d) => (b += d));
  req.on("end", () => {
    const body = JSON.parse(b);
    if (u === "/api/chat/seen") { seen.push(body); unread[body.ch] = 0; return res.end('{"ok":true}'); }
    posts.push(body);
    const [code, j] = answer(body);
    if (code === 200) (STORE[body.ch] = STORE[body.ch] || []).push(row(j.id, body.ch, "owner", body.text));
    res.writeHead(code, { "Content-Type": "application/json" });
    res.end(JSON.stringify(j));
  });
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const ctx = await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true });
    const p = await ctx.newPage(), cdp = await ctx.newCDPSession(p);
    const errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));

    await p.goto(base + "/#chat?ch=dm-mooblox--owner", { waitUntil: "load" });
    await p.waitForSelector(".chat .stream header h2", { timeout: 15000 });
    assert.strictEqual(await p.textContent(".chat .stream header h2"), "Mooblox", "cold load opens the hash's channel");
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=dm-mooblox--owner", "cold load keeps the hash");
    const chans = await p.$$eval(".chat .chans a", (as) => as.map((a) => a.dataset.ch));
    assert.deepStrictEqual(chans, ["", "harness", "org", "mooblox", "discord", "dm-orchestrator--owner", "dm-mooblox--owner", "dm-discord--owner", "dm-owner--vass"], "Recent, rooms, PO channels (no room for the pull seat vass) and a direct message per seat before any message");
    await p.waitForFunction(() => /2/.test((document.querySelector('#subs [data-nav="chat"] i') || {}).textContent || ""), null, { timeout: 5000 });
    assert.strictEqual(await p.textContent('.chat [data-ch="org"] .unread'), "2", "unread badge on the channel");

    await p.waitForTimeout(1000);
    const box = await p.evaluate(() => { const r = document.querySelector(".chat .compose").getBoundingClientRect(), d = document.querySelector(".dock").getBoundingClientRect(); return { pos: getComputedStyle(document.querySelector(".chat .compose")).position, bottom: Math.round(r.bottom), dock: Math.round(d.top) }; });
    assert.deepStrictEqual([box.pos, box.bottom], ["fixed", box.dock], "at 400 the composer is fixed on top of the dock");

    await p.click('.chat [data-ch="org"]');
    await p.waitForFunction(() => document.querySelector(".chat .stream header h2").textContent === "# org");
    await p.waitForFunction(() => !document.querySelector('.chat [data-ch="org"] .unread'), null, { timeout: 5000 });
    assert.deepStrictEqual(seen, [{ ch: "org", id: T0 + 3000 }], "opening a channel with unread posts /seen once with its newest id");
    await p.waitForFunction(() => !document.querySelector('#subs [data-nav="chat"] i'), null, { timeout: 5000 });

    answer = () => [200, { id: T0 + 9000, wakes: [{ seat: "mooblox", outcome: "delivered" }] }];
    await p.fill(".chat .compose textarea", "@mooblox what is left?");
    await p.press(".chat .compose textarea", "Enter");
    await p.waitForFunction(() => /Woke Mooblox/.test(document.querySelector(".chat .compose .hint").textContent), null, { timeout: 5000 });
    assert.deepStrictEqual(posts, [{ ch: "org", text: "@mooblox what is left?" }], "Enter posts the text to the open channel");
    assert.strictEqual(await p.inputValue(".chat .compose textarea"), "", "a sent message clears the box");
    await p.waitForFunction(() => [...document.querySelectorAll(".chat .msg.him .tx")].some((e) => e.textContent === "@mooblox what is left?"), null, { timeout: 5000 });

    answer = () => [422, { held: "secret" }];
    await p.fill(".chat .compose textarea", "token=abcdefghijklmnop1234");
    await p.click(".chat .compose button");
    await p.waitForFunction(() => /^Held \(secret\)/.test(document.querySelector(".chat .compose .hint").textContent), null, { timeout: 5000 });
    assert.strictEqual(await p.inputValue(".chat .compose textarea"), "token=abcdefghijklmnop1234", "a held message stays in the box");
    await p.fill(".chat .compose textarea", "line one");
    await p.press(".chat .compose textarea", "Shift+Enter");
    assert.strictEqual(posts.length, 2, "Shift+Enter does not send");

    const pt = await p.evaluate(() => { const r = document.querySelector(".chat .msgs").getBoundingClientRect(); return { x: Math.round(r.left + r.width * 0.8), y: Math.round(r.top + 30) }; });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [pt] });
    for (let k = 1; k <= 10; k++) await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: pt.x - k * 25, y: pt.y }] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await p.waitForTimeout(400);
    assert.ok((await p.evaluate(() => location.hash)).startsWith("#chat"), "a sideways swipe on the stream stays on Chat");

    await p.setViewportSize({ width: 1366, height: 768 });
    await p.waitForSelector(".chat .wakes .wk", { state: "visible", timeout: 5000 });
    const wk = await p.$$eval(".chat .wakes .wk", (r) => r.map((x) => x.querySelector("span").textContent + " " + x.querySelector("b").textContent));
    assert.deepStrictEqual(wk, ["Orchestrator 5", "Mooblox 13", "Discord 0"], "wakes today per seat as plain numbers (no limit, P38); the pull seat vass is never woken");
    assert.strictEqual(await p.$$eval(".chat .wakes progress", (l) => l.length), 0, "no bar to a limit");
    const fixed = await p.evaluate(() => getComputedStyle(document.querySelector(".chat .compose")).position);
    assert.strictEqual(fixed, "static", "from 900 px the composer sits under the stream");

    thinking = [{ seat: "discord", ch: "org", state: "thinking", since: 1 }, { seat: "mooblox", ch: "dm-mooblox--owner", state: "starting", since: 1 }];
    await p.waitForSelector(".chat .msgs > .thinking:last-child", { timeout: 6000 });
    assert.deepStrictEqual(await p.$$eval(".chat .msgs .thinking", (l) => l.map((e) => e.textContent.trim())), ["Discord is thinking"], "P38: under the last message, the agent woken from this channel is thinking; the other channel's wake is not here");
    assert.strictEqual(await p.$$eval(".chat .msgs .thinking .fam svg.cr", (l) => l.length), 1, "P38: the thinking row shows its Familiar");
    assert.strictEqual(await p.$$eval(".chat .msgs .thinking .dots i", (l) => l.length), 3, "P38: three animated dots");
    assert.deepStrictEqual(await p.$$eval(".chat .chans .think", (l) => l.map((e) => e.closest("a").dataset.ch + ":" + e.title)),
      ["org:Discord is thinking", "dm-mooblox--owner:Mooblox woken, starting"], "P38: a small marker on each channel with a woken agent");
    await p.click('.chat [data-ch="dm-mooblox--owner"]');
    await p.waitForFunction(() => (document.querySelector(".chat .msgs .thinking") || {}).textContent === "Mooblox woken, starting", null, { timeout: 6000 });
    thinking = [];
    await p.waitForFunction(() => !document.querySelector(".chat .thinking, .chat .think"), null, { timeout: 6000 });
    await p.click('.chat [data-ch="org"]');
    await p.waitForFunction(() => document.querySelector(".chat .stream header h2").textContent === "# org");

    assert.strictEqual(await p.$$eval('.chat .chans a[data-ch^="dm-"] .fam svg.cr', (l) => l.length), 4, "each direct message shows its seat's Familiar");
    await p.waitForSelector(".chat .msg:not(.him) .av .fam svg.cr.sleep", { timeout: 5000 }).catch(() => assert.fail("asleep senders rest in the stream"));
    assert.strictEqual(await p.$$eval(".chat .cr.talking", (l) => l.length), 0, "his own messages made nobody talk");
    STORE.org.push(row(T0 + 20000, "org", "discord", "three"));
    await p.waitForSelector(".chat .msgs .msg:last-child .cr.talking", { timeout: 6000 });
    const t0 = Date.now(), where = await p.$$eval(".chat .cr.talking", (l) => l.map((e) => (e.closest(".msgs") ? "row" : e.closest(".cside") ? "side" : "dm") + ":" + e.closest(".fam").dataset.fam).sort());
    assert.deepStrictEqual(where, ["dm:discord", "row:discord", "side:discord"], "a new message: its row, its sender in the channel box and in the direct list talk, older rows do not");
    await p.waitForFunction(() => !document.querySelector(".chat .cr.talking"), null, { timeout: 4000 });
    assert.ok(Date.now() - t0 > 1200 && Date.now() - t0 < 3200, "talking lasts about 2 s");
    await p.emulateMedia({ reducedMotion: "reduce" });
    assert.strictEqual(await p.$eval(".chat .cside .fam", (e) => getComputedStyle(e).animationName), "none", "prefers-reduced-motion stops the motion");
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · cold #chat?ch= · 8 channels, no vass room · unread + /seen · composer sent/woke/held · fixed at 400 · swipe-proof · wakes today as numbers · thinking row + channel marker · Familiars in rows, channel box and direct list; sender talks ~2 s, owner silent");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
