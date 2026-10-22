// Boot without a tap freeze: at 400 px, warm load, no long task over 120 ms in the first 3 s while the WebGL stage builds; fixture API, no live services.
// Run: node tests/test_boot_longtask.js   (PWC = path to playwright-core; LT_W = viewport width, default 400; LT_DEBUG=1 prints the long tasks)
"use strict";
const fs = require("fs"), path = require("path"), http = require("http"), assert = require("assert");
const pwc = () => {
  const root = require("child_process").execFileSync("npm", ["root", "-g"], { encoding: "utf8", env: { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + process.env.PATH } }).trim();
  return [path.join(root, "@playwright/mcp/node_modules/playwright-core"), path.join(root, "playwright-core")].find((d) => fs.existsSync(d));
};
const { chromium } = require(process.env.PWC || pwc());
const STATIC = path.join(__dirname, "..", "static");
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml" };
const MAX_MS = 120, WINDOW_MS = 3000, W = +(process.env.LT_W || 400);
const now = new Date().toISOString();
const STATUS = {
  host: "fixture",
  sites: Array.from({ length: 6 }, (_, i) => ({ port: 9000 + i, path: "/", name: "site " + i, url: "http://fixture:" + (9000 + i) + "/", group: ["mine", "moodle", "metrics"][i % 3], state: "up", ms: 3 })),
  units: Array.from({ length: 6 }, (_, i) => ({ unit: "fixture-" + i + ".service", group: "fleet", active: "active", sub: "running", rss: 0 })),
  sparks: { cpu: { values: [5, 6, 7] } }, timers: [], docker: [], plans: [], drop: { files: [] }, errors: {},
  verdict: { ok: false, problems: [], asks: [], needs: [{ kind: "need", t: now, text: "fixture need" }] },
};

const srv = http.createServer((req, res) => {
  const u = req.url.split("?")[0];
  if (u.startsWith("/api/")) { res.writeHead(200, { "Content-Type": "application/json" }); return res.end(JSON.stringify(u === "/api/status" ? STATUS : u === "/api/agents" ? { agents: [], roster: [] } : {})); }
  const file = u === "/" ? path.join(STATIC, "next", "index.html") : path.join(STATIC, u.replace(/^\/static\//, ""));
  if (!file.startsWith(STATIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream", "Cache-Control": "max-age=600" });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ headless: true, args: ["--mute-audio"] });
  try {
    const p = await (await b.newContext({ viewport: { width: W, height: W < 800 ? 860 : 768 } })).newPage();
    const errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.addInitScript(() => {
      window.__lt = [];
      new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__lt.push([Math.round(e.startTime), Math.round(e.duration)]))).observe({ type: "longtask", buffered: true });
    });
    await p.goto(base + "/", { waitUntil: "load" });
    await p.waitForFunction(() => document.body.classList.contains("gl") || document.body.classList.contains("nogl"), null, { timeout: 15000 });
    await p.reload({ waitUntil: "load" });
    await p.waitForTimeout(WINDOW_MS);
    const r = await p.evaluate((win) => ({ lt: window.__lt.filter(([t]) => t < win), gl: document.body.classList.contains("gl"), frames: window.__stage ? window.__stage.frames() : 0 }), WINDOW_MS);
    if (process.env.LT_DEBUG) console.log(JSON.stringify(r));
    assert.deepStrictEqual(errs, [], "no page errors");
    assert.ok(r.gl, "the WebGL stage booted (body.gl)");
    assert.ok(r.frames > 0, "the stage drew frames");
    const worst = Math.max(0, ...r.lt.map(([, d]) => d));
    assert.ok(worst <= MAX_MS, `longest task in the first ${WINDOW_MS} ms is ${worst} ms (> ${MAX_MS}): ${JSON.stringify(r.lt)}`);
    console.log(`ok boot long tasks at ${W} px: worst ${worst} ms, ${r.lt.length} over 50 ms, ${r.frames} frames`);
  } finally {
    await b.close();
    srv.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
