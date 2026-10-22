// Band counts match their panels: Files band = the browser's ~/drop items (a failed /api/ls says "as of HH:MM" / "drop unreadable"), Services band timers = the timers panel, Overview owner line names its todo count "to do"; fixture API, no live services.
// Run: node tests/test_counts.js   (PWC = path to playwright-core, defaults to the Playwright MCP copy under `npm root -g` of this node)
"use strict";
const fs = require("fs"), path = require("path"), http = require("http"), assert = require("assert");
const pwc = () => {
  const root = require("child_process").execFileSync("npm", ["root", "-g"], { encoding: "utf8", env: { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + process.env.PATH } }).trim();
  return [path.join(root, "@playwright/mcp/node_modules/playwright-core"), path.join(root, "playwright-core")].find((d) => fs.existsSync(d));
};
const { chromium } = require(process.env.PWC || pwc());
const STATIC = path.join(__dirname, "..", "static");
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml" };
const now = new Date().toISOString(), sec = Date.now() / 1000;
const timer = (unit) => ({ unit, every: "1h", next: now, last: now });
const STATUS = {
  host: "fixture", status: { sections: {} }, docker: [], events: [], sparks: {}, sites: [], plans: [], errors: {},
  owner: { running: 2, done: 9, waiting: 1, queued: 0 },
  todo: [{ id: "1", text: "fixture step", t: now }],
  verdict: { ok: false, problems: [], asks: [], needs: [
    { kind: "need", t: now, text: "fixture push one failed" }, { kind: "need", t: now, text: "fixture push two failed" },
    { kind: "todo", todo: "1", t: now, text: "fixture step" }] },
  units: [{ unit: "a.service", group: "fleet", active: "active", sub: "running", what: "a" }],
  timers: ["agent@x.timer", "sentinel-check.timer", "moodle-keep.timer", "snap.refresh.timer", "ubuntu-insights-collect.timer"].map(timer),
  drop: { url: "http://fixture/", files: [{ name: "one.txt", bytes: 3, mtime: sec, kind: "text" }], count: 1, bytes: 3 },
};
const item = (name, dir) => ({ name, dir, bytes: dir ? null : 3, mtime: sec, kind: dir ? "folder" : "text", mime: dir ? "" : "text/plain" });
const LS = { path: "", items: [item("T1", true), item("T2", true), item("one.txt", false)], count: 3, bytes: 3 };
let lsFail = false;

const srv = http.createServer((req, res) => {
  const u = req.url.split("?")[0];
  if (u === "/api/ls" && lsFail) { res.writeHead(500, { "Content-Type": "application/json" }); return res.end('{"error":"fixture ls down"}'); }
  if (u.startsWith("/api/")) { res.writeHead(200, { "Content-Type": "application/json" }); return res.end(JSON.stringify(u === "/api/status" ? STATUS : u === "/api/ls" ? LS : u === "/api/agents" ? { agents: [], roster: [] } : {})); }
  const file = u === "/" ? path.join(STATIC, "next", "index.html") : path.join(STATIC, u.replace(/^\/static\//, ""));
  if (!file.startsWith(STATIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
const num = (re, s, what) => { const m = re.exec(s || ""); assert.ok(m, what + ": no match in " + JSON.stringify(s)); return +m[1]; };

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const p = await (await b.newContext({ viewport: { width: 400, height: 860 }, reducedMotion: "reduce" })).newPage();
    await p.goto(base + "/#eye", { waitUntil: "load" });
    await p.waitForSelector(".verdict .owner");
    const ov = await p.evaluate(() => ({ owner: document.querySelector(".verdict .owner").textContent, head: document.querySelector(".verdict b").textContent }));
    assert.ok(!/waiting on you/.test(ov.owner), "owner line no longer says waiting on you: " + ov.owner);
    assert.strictEqual(num(/(\d+) to do/, ov.owner, "owner to do"), STATUS.todo.length, "owner 'to do' = the To do list");
    console.log("ok eye", JSON.stringify(ov.owner), "|", ov.head);

    await p.evaluate(() => (location.hash = "services"));
    await p.waitForSelector("[data-sys]");
    const sv = await p.evaluate(() => { const c = [...document.querySelectorAll(".cell")].find((x) => /^timers/.test(x.querySelector("h2").textContent));
      return { band: document.querySelector(".bsum").textContent, head: c.querySelector("h2 s").textContent, rows: c.querySelectorAll("tbody tr").length, sys: document.querySelector("[data-sys]").textContent }; });
    const mine = num(/(\d+) timers?\b/, sv.band, "band timers"), sys = num(/\+ (\d+) system/, sv.band, "band system");
    assert.strictEqual(mine, sv.rows, "band timers = timers panel rows");
    assert.strictEqual(mine, num(/(\d+) timers?/, sv.head, "panel head"), "band timers = panel head");
    assert.strictEqual(sys, num(/(\d+) system/, sv.sys, "panel system"), "band system = '+ N system'");
    assert.strictEqual(mine + sys, STATUS.timers.length, "mine + system = every timer");
    console.log("ok services", JSON.stringify(sv.band), "| panel", sv.rows, "rows,", sv.sys.trim());

    await p.evaluate(() => (location.hash = "files"));
    await p.waitForFunction(() => /items in the drop/.test((document.querySelector(".bsum") || {}).textContent) && document.getElementById("fcount"));
    const fl = await p.evaluate(() => ({ band: document.querySelector(".bsum").textContent, panel: document.getElementById("fcount").textContent }));
    assert.strictEqual(num(/(\d+) items? in the drop/, fl.band, "files band"), num(/(\d+) items/, fl.panel, "files panel"), "files band = browser count");
    assert.strictEqual(num(/(\d+) items?/, fl.band, "files band"), LS.count, "files band = /api/ls count, not top-level files");
    console.log("ok files", JSON.stringify(fl.band), "| panel", fl.panel);

    const band = () => p.evaluate(() => document.querySelector(".bsum").textContent);
    const tick = () => p.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
    lsFail = true; await tick();
    await p.waitForFunction(() => /as of \d\d:\d\d/.test(document.querySelector(".bsum").textContent));
    const st = await band();
    assert.strictEqual(num(/(\d+) items? in the drop/, st, "stale band"), LS.count, "stale band keeps the last count");
    console.log("ok files stale", JSON.stringify(st));
    lsFail = false; await tick();
    await p.waitForFunction(() => !/as of/.test(document.querySelector(".bsum").textContent));
    console.log("ok files fresh", JSON.stringify(await band()));
    lsFail = true; await p.reload({ waitUntil: "load" });
    await p.waitForFunction(() => /drop unreadable/.test((document.querySelector(".bsum") || {}).textContent));
    console.log("ok files unreadable", JSON.stringify(await band()));
    lsFail = false;
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message); process.exit(1); });
