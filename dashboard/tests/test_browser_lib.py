"""The Playwright tests share tests/lib/browser.js: one playwright-core locator and one fixture static server."""
import glob, json, os, subprocess, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "lib", "browser.js")
PROBE = r"""
const { serveStatic } = require(process.argv[1]);
const srv = serveStatic((u, res) => u === "/api/status" ? { host: "fixture" } : u === "/api/down" ? (res.writeHead(500), res.end("down")) : undefined, { "Cache-Control": "max-age=600" });
srv.listen(0, "127.0.0.1", async () => {
  const base = "http://127.0.0.1:" + srv.address().port, out = {};
  for (const u of ["/api/status", "/api/agents", "/api/other", "/api/down", "/", "/static/next/next.css", "/nope.js"]) {
    const r = await fetch(base + u);
    out[u] = [r.status, r.headers.get("content-type"), r.headers.get("cache-control"), u.startsWith("/api/") ? await r.text() : ""];
  }
  srv.close();
  console.log(JSON.stringify(out));
});
"""


class BrowserLib(unittest.TestCase):
    def test_no_test_keeps_its_own_copy(self):
        for f in glob.glob(os.path.join(HERE, "*.js")):
            src = open(f).read()
            self.assertNotIn("const pwc = ", src, f)
            self.assertNotIn("http.createServer", src, f)

    def test_serve_static_answers_api_and_files(self):
        out = json.loads(subprocess.run(["node", "-e", PROBE, LIB], capture_output=True, text=True, timeout=30, check=True).stdout)
        self.assertEqual(out["/api/status"][:2], [200, "application/json"])
        self.assertEqual(json.loads(out["/api/status"][3]), {"host": "fixture"})
        self.assertEqual(json.loads(out["/api/agents"][3]), {"agents": [], "roster": []})
        self.assertEqual(json.loads(out["/api/other"][3]), {})
        self.assertEqual(out["/api/down"][0], 500)
        self.assertEqual(out["/"][:3], [200, "text/html", "max-age=600"])
        self.assertEqual(out["/static/next/next.css"][:2], [200, "text/css"])
        self.assertEqual(out["/nope.js"][0], 404)


if __name__ == "__main__":
    unittest.main()
