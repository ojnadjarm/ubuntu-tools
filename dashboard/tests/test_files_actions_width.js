// Files action column: after the Voice screens load voice.css, every td.go still fits its buttons on one line and the table spans .tw; fixture API.
// Run: node tests/test_files_actions_width.js   (PWC = path to playwright-core, defaults to the Playwright MCP copy under `npm root -g` of this node)
"use strict";
const fs = require("fs"), path = require("path"), http = require("http"), assert = require("assert");
const pwc = () => {
  const root = require("child_process").execFileSync("npm", ["root", "-g"], { encoding: "utf8", env: { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + process.env.PATH } }).trim();
  return [path.join(root, "@playwright/mcp/node_modules/playwright-core"), path.join(root, "playwright-core")].find((d) => fs.existsSync(d));
};
const { chromium } = require(process.env.PWC || pwc());
const STATIC = path.join(__dirname, "..", "static");
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml" };
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [] }, needs: [] };
const LS = { path: "", items: ["atlas-tutorias", "cv", "mirasges327", "mirasmant5"].map((n, i) => ({ name: n, dir: true, bytes: 0, mtime: 1792394211 - i * 86400, kind: "folder" })).concat([{ name: "notes.md", dir: false, bytes: 2048, mtime: 1792394211, kind: "markdown", mime: "text/markdown" }]), count: 5, bytes: 2048 };

const srv = http.createServer((req, res) => {
  const u = req.url.split("?")[0];
  if (u.startsWith("/api/")) { res.writeHead(200, { "Content-Type": "application/json" }); return res.end(JSON.stringify(u === "/api/status" ? STATUS : u === "/api/ls" ? LS : u === "/api/agents" ? { agents: [], roster: [] } : {})); }
  const file = u === "/" ? path.join(STATIC, "next", "index.html") : path.join(STATIC, u.replace(/^\/static\//, ""));
  if (!file.startsWith(STATIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});

const measure = (p) => p.evaluate(() => {
  const tw = document.querySelector(".fsel .tw");
  const rows = [...tw.querySelectorAll("tbody td.go")].map((td) => {
    const kids = [...td.children], r0 = kids[0].getBoundingClientRect();
    return { w: td.clientWidth, sw: td.scrollWidth, lines: 1 + kids.filter((k) => k.getBoundingClientRect().top >= r0.bottom).length, clipped: kids.filter((k) => k.scrollWidth > k.clientWidth + 1).length };
  });
  return { rows, gap: Math.round(tw.getBoundingClientRect().right - Math.max(...[...tw.querySelectorAll("td.go")].map((td) => td.getBoundingClientRect().right))), hscroll: tw.scrollWidth - tw.clientWidth };
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    for (const width of [1366, 2000]) {
      const p = await b.newPage({ viewport: { width, height: 1100 }, reducedMotion: "reduce" });
      await p.goto(base + "/#pronunciation", { waitUntil: "load" });
      await p.waitForFunction(() => [...document.styleSheets].some((s) => /voice\.css$/.test(s.href || "")), null, { timeout: 10000 });
      await p.evaluate(() => { location.hash = "#files"; });
      await p.waitForSelector(".fsel .tw tbody td.go", { timeout: 10000 });
      await p.waitForTimeout(600);
      const m = await measure(p);
      console.log(width + " px after Voice: td.go " + m.rows.map((r) => r.w + "/" + r.sw).join(" ") + ", lines " + Math.max(...m.rows.map((r) => r.lines)) + ", gap " + m.gap + " px, hscroll " + m.hscroll + " px");
      m.rows.forEach((r, i) => {
        assert.ok(r.w >= r.sw, width + " px row " + i + ": td.go " + r.w + " px < its buttons' scrollWidth " + r.sw + " px");
        assert.strictEqual(r.lines, 1, width + " px row " + i + ": actions wrap onto " + r.lines + " lines");
        assert.strictEqual(r.clipped, 0, width + " px row " + i + ": " + r.clipped + " clipped action labels");
      });
      assert.ok(Math.abs(m.gap) <= 1, width + " px: table stops " + m.gap + " px short of .tw");
      await p.close();
    }
    console.log("ok");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message || e); process.exit(1); });
