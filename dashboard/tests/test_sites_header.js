// Machine screens at 400 px: the screen title and summary never sit under the sub-tabs, at any scroll position; fixture API, no live services.
// Run: node tests/test_sites_header.js   (PWC = path to playwright-core, defaults to the Playwright MCP copy under `npm root -g` of this node)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const row = (i) => ({ port: 9000 + i, path: "/", name: "site " + i, what: "fixture row " + i, url: "http://fixture:" + (9000 + i) + "/", group: ["mine", "moodle", "metrics"][i % 3], state: "up", ms: 3, uptime: "1 h", tls: false });
const STATUS = { host: "fixture", sites: Array.from({ length: 18 }, (_, i) => row(i)), units: Array.from({ length: 18 }, (_, i) => ({ unit: "fixture-" + i + ".service", what: "fixture unit " + i, group: i % 2 ? "fleet" : "yours", active: "active", sub: "running", since: "", rss: 0 })), timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [] }, needs: [] };

const srv = serveStatic((u) => u === "/api/status" ? STATUS : undefined);

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis"] }); // no WebGL stage: its SwiftShader frames cost ~130 CPU s
  try {
    const p = await (await b.newContext({ viewport: { width: 400, height: 860 }, deviceScaleFactor: 2, reducedMotion: "reduce" })).newPage();
    for (const screen of ["sites", "services"]) {
      await p.goto(base + "/#" + screen);
      await p.waitForSelector(".band .bsum", { timeout: 15000 });
      const max = await p.evaluate(() => document.documentElement.scrollHeight - innerHeight);
      assert.ok(max > 200, screen + ": fixture page scrolls (" + max + " px)");
      for (let y = 0; y <= Math.min(max, 600); y += 20) {
        const hit = await p.evaluate((y) => {
          scrollTo(0, y);
          const s = document.getElementById("subs").getBoundingClientRect();
          return [".kin", ".bsum"].filter((q) => { const r = document.querySelector(".band " + q).getBoundingClientRect(); return r.bottom > s.top && r.top < s.bottom; });
        }, y);
        assert.deepStrictEqual(hit, [], screen + " at scrollY " + y + ": " + hit.join(", ") + " under the sub-tabs");
      }
      assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), 400, screen + ": no horizontal scroll at 400 px");
    }
    console.log("sites header: 2 screens, title and summary never under the sub-tabs at 400 px");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message); process.exit(1); });
