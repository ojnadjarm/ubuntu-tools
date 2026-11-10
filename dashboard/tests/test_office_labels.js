// Office name tags (T1601-07): at the default view no two tags overlap at 400, 768, 1366, 1920 and 2560 px; a working
// seat keeps its own spot (the CEO's tag sits on its point); a moved tag draws a leader line to its point; after a turn
// the tags still do not overlap and a second place() moves nothing (no jitter). GPU flags: the real projection.
// Run: node tests/test_office_labels.js   (fixture API only)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const SIZES = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];
const srv = serveStatic((u) => (u === "/api/status" ? STATUS : u === "/api/office" ? FIX : u === "/api/chat" ? { messages: [], channels: [] } : undefined));

/* Every shown tag: id, box, its lead (px moved off its point), its transform. */
const tags = (p) => p.$$eval(".office .otags .otag", (l) => l.filter((t) => !t.hidden && t.offsetWidth).map((t) => {
  const r = t.getBoundingClientRect();
  return { id: t.dataset.who, l: r.left, r: r.right, t: r.top, b: r.bottom, lead: parseFloat(t.style.getPropertyValue("--lead") || "0"), tf: t.style.transform };
}));
/* Pairs of tags whose boxes intersect by more than half a pixel. */
const overlaps = (T) => T.flatMap((a, i) => T.slice(i + 1).filter((b) => Math.min(a.r, b.r) - Math.max(a.l, b.l) > 0.5 && Math.min(a.b, b.b) - Math.max(a.t, b.t) > 0.5).map((b) => a.id + "/" + b.id));

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ headless: true, args: ["--mute-audio", ...GPU] });
  let fails = 0;
  const check = (fn, msg) => { try { fn(); console.log("ok " + msg); } catch (e) { fails++; console.error("not ok " + msg + ": " + e.message); } };
  try {
    for (const [w, h] of SIZES) {
      const p = await (await b.newContext({ viewport: { width: w, height: h } })).newPage();
      const errs = [];
      p.on("pageerror", (e) => errs.push(String(e)));
      await p.goto(base + "/#org", { waitUntil: "load" });
      await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1 && document.querySelector(".office .otags .otag"), null, { timeout: 30000 });
      await p.waitForTimeout(500);
      const T = await tags(p);
      check(() => assert.ok(T.length >= 11, `${T.length} tags`), `${w}px: the room tags are shown`);
      check(() => assert.deepStrictEqual(overlaps(T), []), `${w}px: 0 intersecting tag boxes at the default view`);
      check(() => assert.strictEqual(T.find((t) => t.id === "orchestrator").lead, 0), `${w}px: the working CEO keeps its spot`);
      const moved = T.filter((t) => Math.abs(t.lead) > 2).map((t) => t.id);
      const leds = await p.$$eval(".office .otags .otag.led", (l) => l.filter((t) => !t.hidden && t.offsetWidth).map((t) => [t.dataset.who, getComputedStyle(t, "::after").height]));
      check(() => { assert.deepStrictEqual(leds.map((x) => x[0]).sort(), moved.slice().sort()); assert.ok(leds.every((x) => parseFloat(x[1]) > 0)); }, `${w}px: each of the ${moved.length} moved tags draws a leader line`);
      if (w === 1366) {
        const c = await p.$eval(".office .stage canvas", (e) => { const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; });
        await p.mouse.move(c[0], c[1]); await p.mouse.down();
        for (let k = 1; k <= 8; k++) await p.mouse.move(c[0] + k * 30, c[1], { steps: 2 });
        await p.mouse.up();
        await p.waitForTimeout(500);
        const A = await tags(p);
        check(() => assert.deepStrictEqual(overlaps(A), []), `${w}px: 0 intersecting tag boxes after a turn`);
        await p.evaluate(() => document.querySelector(".office .stage canvas").dispatchEvent(new Event("view")));
        const B = await tags(p);
        check(() => assert.deepStrictEqual(B.map((t) => t.tf), A.map((t) => t.tf)), `${w}px: placing again moves no tag (no jitter)`);
      }
      check(() => assert.deepStrictEqual(errs, []), `${w}px: no page errors`);
      await p.context().close();
    }
  } finally { await b.close(); srv.close(); }
  console.log(fails ? `FAIL ${fails}` : "ok test_office_labels");
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
