// Phone touch scroll: a vertical swipe that starts on a table row scrolls the page on Files, Services and Sites; fixture API, raw CDP touch events.
// Run: node tests/test_files_touch.js   (PWC = path to playwright-core, defaults to the Playwright MCP copy under `npm root -g` of this node)
"use strict";
const fs = require("fs"), path = require("path"), http = require("http"), assert = require("assert");
const pwc = () => {
  const root = require("child_process").execFileSync("npm", ["root", "-g"], { encoding: "utf8", env: { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + process.env.PATH } }).trim();
  return [path.join(root, "@playwright/mcp/node_modules/playwright-core"), path.join(root, "playwright-core")].find((d) => fs.existsSync(d));
};
const { chromium } = require(process.env.PWC || pwc());
const STATIC = path.join(__dirname, "..", "static");
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml" };
const row = (i) => ({ port: 9000 + i, path: "/", name: "site " + i, what: "fixture row " + i, url: "http://fixture:" + (9000 + i) + "/", group: ["mine", "moodle", "metrics"][i % 3], state: "up", ms: 3, uptime: "1 h", tls: false });
const STATUS = { host: "fixture", sites: Array.from({ length: 18 }, (_, i) => row(i)), units: Array.from({ length: 18 }, (_, i) => ({ unit: "fixture-" + i + ".service", what: "fixture unit " + i, group: i % 2 ? "fleet" : "yours", active: "active", sub: "running", since: "", rss: 0 })), timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [] }, needs: [] };
const LS = { path: "", items: Array.from({ length: 30 }, (_, i) => ({ name: "fixture-file-" + i + ".png", dir: false, bytes: 1000 * i, mtime: 1792394211 - i * 3600, kind: "image", mime: "image/png" })), count: 30, bytes: 435000 };

const srv = http.createServer((req, res) => {
  const u = req.url.split("?")[0];
  if (u.startsWith("/api/")) { res.writeHead(200, { "Content-Type": "application/json" }); return res.end(JSON.stringify(u === "/api/status" ? STATUS : u === "/api/ls" ? LS : u === "/api/agents" ? { agents: [], roster: [] } : {})); }
  const file = u === "/" ? path.join(STATIC, "next", "index.html") : path.join(STATIC, u.replace(/^\/static\//, ""));
  if (!file.startsWith(STATIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const ctx = await b.newContext({ viewport: { width: 400, height: 860 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2, reducedMotion: "reduce" });
    const p = await ctx.newPage(), cdp = await ctx.newCDPSession(p);
    for (const screen of ["files", "services", "sites"]) {
      await p.goto(base + "/#" + screen, { waitUntil: "load" });
      await p.waitForSelector(".tw tbody tr td", { timeout: 10000 });
      await p.waitForTimeout(800);
      const latch = await p.evaluate(() => [...document.querySelectorAll(".tw")].filter((t) => t.scrollHeight > t.clientHeight || t.scrollWidth > t.clientWidth).length);
      assert.strictEqual(latch, 0, screen + ": a .tw has its own scroll overflow");
      const ta = await p.evaluate(() => getComputedStyle(document.querySelector(".tw")).touchAction);
      assert.strictEqual(ta, "pan-y", screen + ": .tw touch-action " + ta);
      const pt = await p.evaluate(() => {
        const first = document.querySelector(".tw tbody tr:not(.grp) td").getBoundingClientRect();
        if (first.top > 600) scrollTo(0, scrollY + first.top - 450);
        const td = [...document.querySelectorAll(".tw tbody tr:not(.grp) td")].find((e) => { const r = e.getBoundingClientRect(); return r.top > 420 && r.bottom < 760; });
        const r = td.getBoundingClientRect(); return { x: Math.round(r.left + 40), y: Math.round(r.top + r.height / 2) };
      });
      const y0 = await p.evaluate(() => scrollY);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [pt] });
      for (let k = 1; k <= 20; k++) { await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: pt.x, y: pt.y - k * 15 }] }); await p.waitForTimeout(16); }
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      await p.waitForTimeout(600);
      const dy = (await p.evaluate(() => scrollY)) - y0;
      console.log(screen + ": swipe on a row scrolled the page " + dy + " px");
      assert.ok(dy >= 250, screen + ": swipe on a row scrolled " + dy + " px (< 250)");
    }
    console.log("ok");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message || e); process.exit(1); });
