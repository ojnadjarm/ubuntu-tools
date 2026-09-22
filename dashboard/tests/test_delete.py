"""Delete from Files and Docs: gio trash into a fixture HOME, confinement, hard links, index entry removal."""
import http.client, json, os, sys, tempfile, threading, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server


class Delete(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = server.Server(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.env = {k: os.environ.get(k) for k in ("HOME", "XDG_DATA_HOME")}
        os.environ["HOME"], os.environ["XDG_DATA_HOME"] = t, os.path.join(t, "data")
        self.trash = os.path.join(t, "data", "Trash", "files")
        self.drop, self.plans, self.orig = os.path.join(t, "drop"), os.path.join(t, "plans"), os.path.join(t, "orig.txt")
        os.makedirs(os.path.join(self.drop, "sub"))
        open(os.path.join(self.drop, "sub", "n.md"), "w").write("# hi\n")
        open(os.path.join(self.drop, ".hidden"), "w").write("x")
        open(self.orig, "w").write("original")
        os.link(self.orig, os.path.join(self.drop, "linked.txt"))
        for slug in ("a-doc", "b-doc"):
            os.makedirs(os.path.join(self.plans, slug))
            open(os.path.join(self.plans, slug, "index.html"), "w").write("<p>page</p>")
        json.dump([{"slug": s, "title": s, "url": "/plans/%s/" % s, "updated": "2026-09-22"} for s in ("a-doc", "b-doc")],
                  open(os.path.join(self.plans, "index.json"), "w"))
        self.saved = server.DROP, server.PLANS
        server.DROP, server.PLANS = self.drop, self.plans
        self.assertTrue(server.DROP.startswith(t) and server.PLANS.startswith(t))

    def tearDown(self):
        server.DROP, server.PLANS = self.saved
        for k, v in self.env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def post(self, path, body):
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=10)
        c.request("POST", path, body=json.dumps(body))
        r = c.getresponse()
        out = (r.status, json.loads(r.read()))
        c.close()
        return out

    def test_file_goes_to_fixture_trash(self):
        code, out = self.post("/api/files/delete", {"path": "sub/n.md"})
        self.assertEqual((code, out["trashed"]), (200, "sub/n.md"))
        self.assertFalse(os.path.exists(os.path.join(self.drop, "sub", "n.md")))
        self.assertTrue(os.path.isfile(os.path.join(self.trash, "n.md")))

    def test_folder(self):
        self.assertEqual(self.post("/api/files/delete", {"path": "sub"})[0], 200)
        self.assertEqual([i["name"] for i in server.ls_dir("")[1]["items"]], ["linked.txt"])
        self.assertTrue(os.path.isfile(os.path.join(self.trash, "sub", "n.md")))

    def test_hard_link_original_survives(self):
        self.assertEqual(self.post("/api/files/delete", {"path": "linked.txt"})[0], 200)
        self.assertEqual(open(self.orig).read(), "original")
        self.assertEqual(os.stat(self.orig).st_nlink, 2)
        self.assertTrue(os.path.samefile(self.orig, os.path.join(self.trash, "linked.txt")))

    def test_refused(self):
        for p in ("../orig.txt", "sub/../../orig.txt", "/etc/passwd", ".hidden", "sub/.x", "", "missing.txt", "a\\b", None, 3):
            self.assertEqual(self.post("/api/files/delete", {"path": p})[0], 400, p)
        self.assertEqual(self.post("/api/files/delete", ["sub"])[0], 400)
        self.assertTrue(os.path.exists(os.path.join(self.drop, ".hidden")) and os.path.exists(self.orig))
        self.assertFalse(os.path.exists(self.trash))

    def test_drop_cache_forgotten(self):
        server.cached("drop", 3600, server.drop)
        self.post("/api/files/delete", {"path": "linked.txt"})
        self.assertEqual(server.cached("drop", 3600, server.drop)["count"], 0)

    def test_doc(self):
        server.cached("plans", 3600, server.plans)
        code, out = self.post("/api/docs/delete", {"slug": "a-doc"})
        self.assertEqual((code, out["trashed"]), (200, "a-doc"))
        self.assertEqual([e["slug"] for e in json.load(open(os.path.join(self.plans, "index.json")))], ["b-doc"])
        self.assertEqual([e["slug"] for e in server.cached("plans", 3600, server.plans)], ["b-doc"])
        self.assertFalse(os.path.exists(os.path.join(self.plans, "a-doc")))
        self.assertTrue(os.path.isfile(os.path.join(self.trash, "a-doc", "index.html")))
        self.assertFalse(os.path.exists(os.path.join(self.plans, "index.json.tmp")))

    def test_doc_refused(self):
        os.makedirs(os.path.join(self.plans, "stray"))
        for s in ("missing", "stray", "../plans", "a-doc/index.html", ".", "", None, ["a-doc"]):
            self.assertEqual(self.post("/api/docs/delete", {"slug": s})[0], 400, s)
        self.assertEqual(len(json.load(open(os.path.join(self.plans, "index.json")))), 2)
        self.assertTrue(os.path.isdir(os.path.join(self.plans, "a-doc")) and os.path.isdir(os.path.join(self.plans, "stray")))

    def test_doc_without_folder_drops_entry(self):
        os.rename(os.path.join(self.plans, "b-doc"), os.path.join(self.tmp.name, "b-moved"))
        self.assertEqual(self.post("/api/docs/delete", {"slug": "b-doc"})[0], 200)
        self.assertEqual([e["slug"] for e in json.load(open(os.path.join(self.plans, "index.json")))], ["a-doc"])


if __name__ == "__main__":
    unittest.main()
