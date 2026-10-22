// Overview fold: with three needs and tall side panes, the verdict block ends inside the first screen at 400x760, 1366x768, 1920x960 and 2560x1300; fixture API, no live services.
// Run: node tests/test_fold.js   (PWC = path to playwright-core, defaults to the Playwright MCP copy under `npm root -g` of this node)
"use strict";
const fs = require("fs"), path = require("path"), http = require("http"), assert = require("assert");
const pwc = () => {
  const root = require("child_process").execFileSync("npm", ["root", "-g"], { encoding: "utf8", env: { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + process.env.PATH } }).trim();
  return [path.join(root, "@playwright/mcp/node_modules/playwright-core"), path.join(root, "playwright-core")].find((d) => fs.existsSync(d));
};
const { chromium } = require(process.env.PWC || pwc());
const STATIC = path.join(__dirname, "..", "static");
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml" };
const v = (o) => Object.fromEntries(Object.entries(o).map(([k, x]) => [k, { value: x }]));
const now = new Date().toISOString();
const STATUS = {
  host: "fixture",
  status: { sections: {
    power: v({ battery: "72%", source: "AC", profile: "balanced", lid: "closed", battery_health: "72%, 310 cycles" }),
    resources: v({ ram_available: "27000 MB of 31000 MB", disk_root: "42%, 280G free", temp_max: "55 C" }),
    host: v({ load: "0.36", uptime: "2 days, 3 hours" }),
    network: v({ internet: "online", wifi_ssid: "fixture-wifi", lan_ip: "<lan-ip>", tailscale: "Running", tailscale_ip: "<tailnet-ip>" }),
    disk: v({ smart: "PASSED", percent_used: "6%", available_spare: "100%" }),
  } },
  docker: Array.from({ length: 11 }, (_, i) => ({ name: "fixture-" + i + "-app-1", state: "running", status: "Up 7 h", ports: [] })),
  events: Array.from({ length: 6 }, (_, i) => ({ t: now, kind: "incident", prio: "high", text: "FAIL fixture." + i + "\tdetail" })),
  sparks: Object.fromEntries(["cpu", "io", "net", "ram"].map((k) => [k, { values: Array.from({ length: 30 }, (_, i) => 10 + (i % 7)) }])),
  owner: { running: 5, done: 168, waiting: 3, queued: 1 },
  test_site: [{ name: "index", url: "http://fixture/a" }, { name: "board", url: "http://fixture/b" }],
  verdict: { ok: false, problems: [], asks: [], needs: [1, 2, 3].map((i) => ({ kind: "need", t: now, text: "fixture need " + i + " failed twice; the report is in ~/drop/fixture/" + i + ".md and needs a decision only the owner can take" })) },
  sites: [], units: [], timers: [], plans: [], drop: { files: [] }, errors: {},
};

const srv = http.createServer((req, res) => {
  const u = req.url.split("?")[0];
  if (u.startsWith("/api/")) { res.writeHead(200, { "Content-Type": "application/json" }); return res.end(JSON.stringify(u === "/api/status" ? STATUS : u === "/api/agents" ? { agents: [], roster: [] } : {})); }
  const file = u === "/" ? path.join(STATIC, "next", "index.html") : path.join(STATIC, u.replace(/^\/static\//, ""));
  if (!file.startsWith(STATIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] }); // no WebGL stage: its SwiftShader frames cost ~130 CPU s
  try {
    for (const [w, h] of [[400, 760], [1366, 768], [1920, 960], [2560, 1300]]) {
      const p = await (await b.newContext({ viewport: { width: w, height: h }, reducedMotion: "reduce" })).newPage();
      await p.goto(base + "/#eye", { waitUntil: "load" });
      await p.waitForSelector(".eyebox .probs li");
      const r = await p.evaluate(() => ({ n: document.querySelectorAll(".eyebox .probs li").length, bottom: document.querySelector(".eyebox .verdict").getBoundingClientRect().bottom, vh: innerHeight }));
      assert.strictEqual(r.n, 3, w + "x" + h + ": three need lines");
      assert.ok(r.bottom <= r.vh, w + "x" + h + ": verdict bottom " + Math.round(r.bottom) + " > " + r.vh);
      console.log("ok", w + "x" + h, "verdict bottom", Math.round(r.bottom), "of", r.vh);
      await p.close();
    }
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message); process.exit(1); });
