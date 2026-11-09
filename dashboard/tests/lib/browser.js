// Shared by the dashboard Playwright tests: the playwright-core locator and a fixture server for ../../static.
"use strict";
const fs = require("fs"), path = require("path"), http = require("http");
const STATIC = path.join(__dirname, "..", "..", "static");
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml" };
const pwc = () => {
  const root = require("child_process").execFileSync("npm", ["root", "-g"], { encoding: "utf8", env: { ...process.env, PATH: path.dirname(process.execPath) + path.delimiter + process.env.PATH } }).trim();
  return [path.join(root, "@playwright/mcp/node_modules/playwright-core"), path.join(root, "playwright-core")].find((d) => fs.existsSync(d));
};
/** Serves /api/* as JSON from api(path, res) (undefined: the default; a written res: as is) and static files with extra headers. */
const serveStatic = (api, headers = {}) => http.createServer((req, res) => {
  const u = req.url.split("?")[0];
  if (u.startsWith("/api/")) {
    const body = api(u, res);
    if (res.headersSent) return;
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify(body !== undefined ? body : u === "/api/agents" ? { agents: [], roster: [] } : {}));
  }
  const file = u === "/" ? path.join(STATIC, "next", "index.html") : path.join(STATIC, u.replace(/^\/static\//, ""));
  if (!file.startsWith(STATIC) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream", ...headers });
  fs.createReadStream(file).pipe(res);
});
module.exports = { serveStatic, get chromium() { return require(process.env.PWC || pwc()).chromium; } };
