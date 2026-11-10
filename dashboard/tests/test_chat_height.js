// T1572: from 900 px the Chat page is exactly as tall as the screen (the stream and the list scroll inside their boxes),
// also with the band wrapped (stale + degraded) and with the reply chip and attachment chips shown; the stream box at
// 1366x768 stays >= 430 px; the opened channel shows its newest line; below 900 px the open conversation does not scroll the page either.
// Run: node tests/test_chat_height.js [shot-dir]   (fixture API only; a shot-dir gets one PNG per width at height 768, plain and wrapped)
"use strict";
const assert = require("assert"), path = require("path");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "DarkSaddler", rank: "CEO", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "mooblox", name: "Mooblox", role: "po", parent: "orchestrator", wake: "po-inbox", match: "~/agents/po-mooblox" }], sessions: [], hidden: 0 };
const T0 = Date.UTC(2026, 10, 9, 21, 0);
const row = (id, ch, from, text) => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind: "msg", text, re: null, hop: 0 });
const STORE = { org: Array.from({ length: 40 }, (_, i) => row(T0 + i * 1000, "org", i % 2 ? "owner" : "mooblox", "line " + i + " of a long room")) };
const WRAP = { paused: true, degraded: "ValueError: match must be ~ or ~/<path> and the store answered slowly while the org file was rewritten" };
let extra = {};
const srv = serveStatic((u, res) => {
  const after = +(new URL(res.req.url, "http://x").searchParams.get("after") || 0);
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") return { messages: STORE.org.filter((m) => m.id > after), channels: [{ ch: "org", unread: 0 }], wakes: { today: {} }, thinking: [], ...extra };
});
const W = [400, 768, 1366, 1920, 2560], H = [768, 900, 1080, 1440];
const shots = process.argv[2];

/* The stream at its newest line, page overflow (scrollHeight - innerHeight), the stream box height and the composer's bottom. */
const measure = (p) => p.evaluate(() => ({ end: (({ scrollHeight: a, scrollTop: b, clientHeight: c }) => a - b - c < 2)(document.querySelector(".chat .msgs")), over: document.documentElement.scrollHeight - innerHeight, box: Math.round(document.querySelector(".chat .msgs").getBoundingClientRect().height),
  low: Math.round(document.querySelector(".chat .compose").getBoundingClientRect().bottom) }));
/* Waits until two animation frames pass with the same measure. */
const settle = async (p) => { let a = await measure(p); for (let i = 0; i < 20; i++) { await p.waitForTimeout(60); const b = await measure(p); if (JSON.stringify(a) === JSON.stringify(b)) return b; a = b; } return a; };

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  const bad = [], errs = [];
  let box1366 = 0;
  try {
    for (const w of W) {
      const ctx = await b.newContext({ viewport: { width: w, height: H[0] }, reducedMotion: "reduce" }), p = await ctx.newPage();
      p.on("pageerror", (e) => errs.push(String(e)));
      extra = {};
      await p.goto(base + "/#chat?ch=org", { waitUntil: "load" });
      await p.waitForSelector(".chat .compose textarea", { timeout: 15000 });
      for (const h of H) {
        await p.setViewportSize({ width: w, height: h });
        for (const k of ["plain", "wrapped", "chips"]) {
          if (k === "wrapped") {
            extra = WRAP;
            await p.waitForFunction(() => /degraded/.test(document.querySelector(".chat .bsum").textContent), null, { timeout: 8000 });
            await p.route("**/api/chat?**", (r) => r.abort());
            await p.waitForFunction(() => /stale/.test(document.querySelector(".chat .bsum").textContent), null, { timeout: 8000 });
            await p.unroute("**/api/chat?**");
          }
          if (k === "chips") {
            await p.$$eval(".chat .msg [data-reply]", (l) => l[l.length - 1].click());
            await p.setInputFiles(".chat .compose input[type=file]", [1, 2, 3, 4, 5].map((i) => ({ name: "file-" + i + "-with-a-long-name.txt", mimeType: "text/plain", buffer: Buffer.from("x") })));
            await p.waitForFunction(() => document.querySelectorAll(".chat .compose .chip").length === 5 && !document.querySelector(".chat .compose .reply").hidden, null, { timeout: 5000 });
          }
          const m = await settle(p);
          if (shots && h === 768 && k !== "chips") await p.screenshot({ path: path.join(shots, `chat-${w}-${k}.png`) });
          console.log(`${w}x${h} ${k}: over ${m.over} box ${m.box} low ${m.low}`);
          if (Math.abs(m.over) > 1) bad.push(`${w}x${h} ${k}: page overflow ${m.over} px`);
          if (m.low > h + 1) bad.push(`${w}x${h} ${k}: composer below the screen (${m.low})`);
          if (w === 1366 && h === 768 && k === "plain") box1366 = m.box;
          if (h === H[0] && k === "plain" && !m.end) bad.push(`${w}x${h}: the opened channel does not show its newest line`);
        }
        while (await p.$(".chat .compose .chip")) await p.$eval('.chat .compose .chip button[aria-label^="Remove"]', (x) => x.click());
        await p.$eval(".chat .compose .reply button", (x) => x.click());
        extra = {};
        await p.waitForFunction(() => !/degraded|stale/.test(document.querySelector(".chat .bsum").textContent), null, { timeout: 8000 });
      }
      await ctx.close();
    }
    assert.deepStrictEqual(bad, [], "the page is as tall as the screen at every width and height");
    assert.ok(box1366 >= 430, `at 1366x768 the messages box is at least 430 px (${box1366})`);
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · overflow 0 (±1) at 5 widths x 4 heights, plain, band wrapped, reply + 5 chips · box " + box1366 + " >= 430 at 1366x768");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
