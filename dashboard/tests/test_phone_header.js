// Phone header: the band (eye perch, title, summary) is at most 120 px tall at 400 on the 6 list screens; dock links are at least 32 px tall at 1366; fixture API.
// Run: node tests/test_phone_header.js   (PWC = path to playwright-core, defaults to the Playwright MCP copy under `npm root -g` of this node)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [] }, needs: [] };
const SCREENS = ["services", "sites", "todo", "docs", "files", "style"];

const srv = serveStatic((u) => u === "/api/status" ? STATUS : u === "/api/ls" ? { path: "", items: [], count: 0, bytes: 0 } : undefined);

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const p = await b.newPage({ viewport: { width: 400, height: 850 }, reducedMotion: "reduce" });
    await p.goto(base + "/#services", { waitUntil: "load" });
    for (const s of SCREENS) {
      await p.evaluate((h) => { location.hash = "#" + h; }, s);
      await p.waitForFunction((h) => (document.querySelector(".band")?.getAttribute("aria-label") || "").toLowerCase().replace(/ /g, "").startsWith(h), s, { timeout: 10000 });
      await p.waitForTimeout(300);
      const h = await p.evaluate(() => Math.round(document.querySelector(".band").getBoundingClientRect().height));
      console.log("400 px " + s + ": band " + h + " px");
      assert.ok(h <= 120, "400 px " + s + ": band " + h + " px > 120");
    }
    await p.setViewportSize({ width: 1366, height: 768 });
    await p.waitForTimeout(300);
    const dock = await p.evaluate(() => [...document.querySelectorAll(".dock a")].map((a) => Math.round(a.getBoundingClientRect().height)));
    console.log("1366 px dock links: " + dock.join(" ") + " px");
    assert.ok(dock.length && dock.every((x) => x >= 32), "1366 px: dock link under 32 px tall: " + dock.join(" "));
    console.log("ok");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message || e); process.exit(1); });
