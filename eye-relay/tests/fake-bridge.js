// Fixture bridge: the body's own queue.js behind GET /bridge/listen, plus POST /push for the driver.
const http = require("http");
const { create } = require(`${process.env.HOME}/the-dark-eye/body/src/queue.js`);

const [port, secret] = [Number(process.argv[2]), process.argv[3]];
const buses = new Map();
const bus = (name) => buses.get(name) ?? buses.set(name, create()).get(name);

http
  .createServer((req, res) => {
    const u = new URL(req.url, "http://x");
    const reply = (code, obj) => res.writeHead(code, { "Content-Type": "application/json" }).end(JSON.stringify(obj));
    if (req.headers["x-dark-eye-key"] !== secret) return reply(401, { error: "key" });
    const brain = u.searchParams.get("brain") || "main";
    if (req.method === "GET" && u.pathname === "/bridge/listen") {
      const ms = Math.min(Number(u.searchParams.get("timeoutMs")) || 50000, 55000);
      return bus(brain).take(ms).then((t) => reply(200, t ? { transcript: t.text, source: t.source ?? "local" } : { transcript: null, source: "local" }));
    }
    if (req.method === "POST" && u.pathname === "/push") {
      let b = "";
      req.on("data", (c) => (b += c));
      return req.on("end", () => {
        bus(brain).push(JSON.parse(b));
        reply(200, { ok: true });
      });
    }
    reply(404, {});
  })
  .listen(port, "127.0.0.1");
