"""GET /api/memory and /api/memory/page on a synthetic fixture store: the index, one page without ^ids, PRIVATE by name only, 400 for anything outside the page list, 403 off the tailnet."""
import os, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash import cache
from dash.services import memory

REAL = os.path.realpath(os.path.expanduser("~/memory"))
PAGES = {
    "core/CORE.md": "# Core card\n- Reports are three lines. (26-01-05) ^k01\n- Charts use <b>teal</b> & amber. (26-01-06) ^k02\n",
    "core/ledger.md": "# Core ledger\n- 2026-01-05 · Reports are three lines\n",
    "domains/garden/DOMAIN.md": "# Garden: the seed catalogue\n- Seed photos are 800 px wide. (26-02-01) → photos ^gd01\n",
    "domains/garden/photos.md": "# Photos\n- Crop to the seed head. (26-02-03) ^gd03\n",
    "domains/vault/DOMAIN.md": "PRIVATE: orchestrator\n# Vault\n- The invented balance is 12 beans. (26-03-01) ^vt01\n",
    "domains/garden/.draft.md": "# hidden draft\n",
    "archive/old.md": "# archived original\n",
}


class Api(unittest.TestCase):
    """The two routes over a fixture MEMORY_HOME; never the real store."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "store")
        for rel, text in PAGES.items():
            os.makedirs(os.path.dirname(os.path.join(self.root, rel)), exist_ok=True)
            with open(os.path.join(self.root, rel), "w", encoding="utf-8") as f:
                f.write(text)
        with open(os.path.join(self.tmp.name, "outside.md"), "w") as f:
            f.write("# outside the store\n")
        os.symlink(os.path.join(self.tmp.name, "outside.md"), os.path.join(self.root, "domains/garden/link.md"))
        self.saved = os.environ.get("MEMORY_HOME")
        os.environ["MEMORY_HOME"] = self.root

    def tearDown(self):
        cache.forget(*[k for k in list(cache._cache) if k.startswith("memory")])
        if self.saved is None:
            os.environ.pop("MEMORY_HOME", None)
        else:
            os.environ["MEMORY_HOME"] = self.saved
        self.tmp.cleanup()

    def call(self, fn, url, ip="127.0.0.1", fwd=None):
        out = []
        h = type("H", (), {"path": url, "client_address": (ip, 0), "headers": {"X-Forwarded-For": fwd} if fwd else {},
                           "json": lambda self, obj, code=200: out.append((code, obj))})()
        fn(h, url.partition("?")[0])
        return out[-1]

    def page(self, p, **kw):
        return self.call(memory.page_route, "/api/memory/page?p=" + p, **kw)

    def test_00_selftest_fixture_not_real_store(self):
        self.assertEqual(memory.store().root, self.root)
        self.assertNotEqual(os.path.realpath(memory.store().root), REAL)

    def test_index_lists_pages_with_bytes_and_change(self):
        code, body = self.call(memory.index_route, "/api/memory")
        self.assertEqual(code, 200)
        names = [r["page"] for r in body["pages"]]
        self.assertEqual(names, ["core/CORE.md", "core/ledger.md", "domains/garden/DOMAIN.md",
                                 "domains/garden/photos.md", "domains/vault/DOMAIN.md"])
        core = body["pages"][0]
        self.assertEqual(core["bytes"], len(PAGES["core/CORE.md"].encode()))
        self.assertGreater(core["mtime"], 0)
        self.assertEqual((body["count"], body["private"]), (5, 1))

    def test_private_page_listed_by_name_only(self):
        rows = {r["page"]: r for r in self.call(memory.index_route, "/api/memory")[1]["pages"]}
        self.assertEqual(rows["domains/vault/DOMAIN.md"], {"page": "domains/vault/DOMAIN.md", "private": True})
        code, body = self.page("domains/vault/DOMAIN.md")
        self.assertEqual(code, 403)
        self.assertNotIn("beans", repr(body))

    def test_page_lines_without_ids(self):
        code, body = self.page("core/CORE.md")
        self.assertEqual(code, 200)
        self.assertEqual(body["lines"][1], "- Reports are three lines. (26-01-05)")
        self.assertEqual(body["lines"][2], "- Charts use <b>teal</b> & amber. (26-01-06)")
        self.assertFalse(any("^k0" in l for l in body["lines"]))
        self.assertEqual(self.page("domains/garden/DOMAIN.md")[1]["lines"][1],
                         "- Seed photos are 800 px wide. (26-02-01) → photos")

    def test_refused_paths_are_400(self):
        for p in ("../outside.md", "core/../../outside.md", "%2e%2e/outside.md", "/etc/passwd", "domains/garden/.draft.md",
                  ".git/config", "archive/old.md", "domains/garden/link.md", "domains/garden/missing.md", "", "core"):
            code, body = self.page(p)
            self.assertEqual(code, 400, p)
            self.assertNotIn("lines", body, p)

    def test_lan_is_403(self):
        self.assertEqual(self.call(memory.index_route, "/api/memory", ip="192.0.2.10")[0], 403)
        self.assertEqual(self.page("core/CORE.md", fwd="192.0.2.10")[0], 403)

    def test_no_post_route(self):
        from dash import routes
        self.assertFalse([k for k in routes.EXACT if k[1].startswith("/api/memory") and k[0] != "GET"])
        self.assertFalse([p for m, p, _ in routes.PREFIX if p.startswith("/api/memory")])


if __name__ == "__main__":
    unittest.main()
