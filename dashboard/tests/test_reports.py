"""/report/agents/<path>: allowlist, confinement, tailnet gate and rendering on a throwaway ~/agents fixture."""
import http.client, os, sys, tempfile, threading, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server
from dash.services import reports


class Fixture(unittest.TestCase):
    """A temp ~/agents tree with allowed, denied and escaping entries."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = os.path.join(self.tmp.name, "agents")
        for d in ("state/ci-fix", "log", "sentinel/logs", "sentinel-digest", "secrets", "backups", ".hid"):
            os.makedirs(os.path.join(root, d))
        for f, text in (("state/ci-fix/2026-10-21.md", "# red\n\n- `a.test.sh`\n"), ("log/ci.log", "".join("line %d\n" % i for i in range(1000))),
                        ("sentinel/logs/r.log", "<b>x</b>\n"), ("sentinel-digest/REPORT.md", "ok\n"), ("secrets/REPORT.md", "token\n"),
                        ("backups/REPORT.md", "dump\n"), (".hid/REPORT.md", "h\n"), ("state/other.md", "n\n"), ("log/m.md", "n\n")):
            open(os.path.join(root, f), "w").write(text)
        open(os.path.join(self.tmp.name, "outside.md"), "w").write("out\n")
        os.symlink(os.path.join(self.tmp.name, "outside.md"), os.path.join(root, "state", "ci-fix", "esc.md"))
        os.symlink(os.path.join(root, "secrets", "REPORT.md"), os.path.join(root, "log", "sec.log"))
        os.symlink(os.path.join(root, "secrets"), os.path.join(root, "link"))
        server.REPORT_ROOT = root
        self.root = root

    def tearDown(self):
        self.tmp.cleanup()


class Paths(Fixture):
    def test_allowlist(self):
        for rel in ("state/ci-fix/2026-10-21.md", "log/ci.log", "sentinel/logs/r.log", "sentinel-digest/REPORT.md"):
            self.assertEqual(reports.report_path(rel), os.path.realpath(os.path.join(self.root, rel)), rel)

    def test_refused(self):
        for rel in ("secrets/REPORT.md", "backups/REPORT.md", ".hid/REPORT.md", "state/other.md", "log/m.md", "secrets/x",
                    "log/../secrets/REPORT.md", "state/ci-fix/../../secrets/REPORT.md", "%2e%2e/outside.md", "state/ci-fix/esc.md",
                    "log/sec.log", "link/REPORT.md", "log//ci.log", "log/missing.log", "/etc/passwd", "log/a\\b.log"):
            self.assertIsNone(reports.report_path(rel), rel)

    def test_render(self):
        md = reports.render(reports.report_path("state/ci-fix/2026-10-21.md"), "state/ci-fix/2026-10-21.md").decode()
        self.assertIn("<h1>red</h1>", md)
        self.assertIn('href="/static/eye.css"', md)
        log = reports.render(reports.report_path("log/ci.log"), "log/ci.log").decode()
        self.assertEqual((log.count("line "), "line 599\n" in log, "line 600\n" in log, "line 999" in log), (400, False, True, True))
        self.assertIn("&lt;b&gt;x&lt;/b&gt;", reports.render(reports.report_path("sentinel/logs/r.log"), "sentinel/logs/r.log").decode())


class Serve(Fixture):
    """Status codes from a real fixture server on a free loopback port, and the LAN gate on a stub handler."""

    def setUp(self):
        super().setUp()
        from dash import http as H
        self.srv = type("S", (H.Server,), {"daemon_threads": False, "block_on_close": True})(("127.0.0.1", 0), H.Handler)
        threading.Thread(target=self.srv.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        super().tearDown()

    def get(self, path):
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=10)
        c.request("GET", path)
        r = c.getresponse()
        body = r.read()
        c.close()
        return r, body

    def test_codes(self):
        r, body = self.get("/report/agents/state/ci-fix/2026-10-21.md")
        self.assertEqual((r.status, r.getheader("Cache-Control"), r.getheader("Content-Type")), (200, "no-store", "text/html; charset=utf-8"))
        self.assertIn(b"<h1>red</h1>", body)
        for p in ("/report/agents/secrets/x", "/report/agents/secrets/REPORT.md", "/report/agents/log/..%2fsecrets/REPORT.md",
                  "/report/agents/../agents/log/ci.log", "/report/state/ci-fix/2026-10-21.md", "/report/"):
            self.assertEqual(self.get(p)[0].status, 404, p)

    def test_lan_is_403(self):
        sent = []
        for ip, code in (("192.0.2.10", 403), ("::ffff:10.0.0.4", 403), ("100.101.102.103", 200), ("::1", 200)):
            h = type("H", (), {"client_address": (ip, 0), "send": lambda self, c, *a, **k: sent.append(c)})()
            reports.report_route(h, "/report/agents/log/ci.log")
            self.assertEqual(sent[-1], code, ip)


if __name__ == "__main__":
    unittest.main()
