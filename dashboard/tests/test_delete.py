"""Delete from Files and Docs: gio trash into a fixture HOME, confinement, hard links, index entry removal."""
import contextlib, http.client, io, json, os, shutil, subprocess, sys, tempfile, threading, unittest
from unittest import mock
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
        self.saved = server.DROP, server.PLANS, server.PROTECTED
        server.DROP, server.PLANS, server.PROTECTED = self.drop, self.plans, [os.path.join(t, "owner")]
        self.assertTrue(server.DROP.startswith(t) and server.PLANS.startswith(t))

    def tearDown(self):
        server.DROP, server.PLANS, server.PROTECTED = self.saved
        for k, v in self.env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def post(self, path, body, **headers):
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=10)
        c.request("POST", path, body=json.dumps(body), headers=dict({"Content-Type": "application/json"}, **headers))
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

    def test_cross_site_posts_refused_and_file_kept(self):
        me = "http://127.0.0.1:%d" % self.srv.server_address[1]
        for h in ({"Sec-Fetch-Site": "cross-site"}, {"Sec-Fetch-Site": "same-site"}, {"Origin": "https://evil.example"},
                  {"Origin": me + "1"}, {"Origin": "null"}):
            self.assertEqual(self.post("/api/files/delete", {"path": "linked.txt"}, **h)[0], 403, h)
        for ctype in ("text/plain", "application/x-www-form-urlencoded", "multipart/form-data; boundary=x"):
            self.assertEqual(self.post("/api/files/delete", {"path": "linked.txt"}, **{"Content-Type": ctype})[0], 400, ctype)
        self.assertTrue(os.path.exists(os.path.join(self.drop, "linked.txt")))
        self.assertFalse(os.path.exists(self.trash))

    def test_same_origin_post_passes(self):
        me = "http://127.0.0.1:%d" % self.srv.server_address[1]
        code, out = self.post("/api/files/delete", {"path": "linked.txt"}, Origin=me, **{"Sec-Fetch-Site": "same-origin",
                              "Content-Type": "application/json; charset=utf-8"})
        self.assertEqual((code, out["trashed"]), (200, "linked.txt"))

    def many(self, *names):
        for n in names:
            open(os.path.join(self.drop, n), "w").write(n * 10)

    def test_many_trash_then_restore(self):
        self.many("a.txt", "b.txt")
        code, out = self.post("/api/files/delete-many", {"paths": ["a.txt", "sub", "sub/n.md", "b.txt/"]})
        self.assertEqual((code, sorted(out["trashed"])), (200, ["a.txt", "b.txt", "sub"]))
        self.assertEqual([i["name"] for i in server.ls_dir("")[1]["items"]], ["linked.txt"])
        self.assertTrue(os.path.isfile(os.path.join(self.trash, "sub", "n.md")))
        code, out = self.post("/api/files/restore", {"paths": out["trashed"]})
        self.assertEqual((code, sorted(out["restored"]), out["failed"]), (200, ["a.txt", "b.txt", "sub"], []))
        self.assertEqual(open(os.path.join(self.drop, "sub", "n.md")).read(), "# hi\n")
        self.assertEqual(os.listdir(os.path.join(self.trash, "..", "info")), [])

    def test_many_dry_counts_and_moves_nothing(self):
        self.many("a.txt")
        code, out = self.post("/api/files/delete-many", {"paths": ["a.txt", "sub"], "dry": True})
        self.assertEqual((code, out), (200, {"count": 2, "bytes": 50 + 5}))
        self.assertTrue(os.path.exists(os.path.join(self.drop, "a.txt")))
        self.assertFalse(os.path.exists(self.trash))

    def test_many_all_or_nothing(self):
        self.many("a.txt")
        os.makedirs(os.path.join(self.tmp.name, "owner"))
        os.symlink(self.orig, os.path.join(self.drop, "out"))
        os.symlink(os.path.join(self.tmp.name, "owner"), os.path.join(self.drop, "own"))
        os.symlink(os.path.join(self.drop, "sub"), os.path.join(self.drop, "inner"))
        server.PROTECTED = [os.path.join(self.tmp.name, "owner"), os.path.join(self.drop, "sub")]
        for bad, why in (("../orig.txt", "outside"), (".hidden", "hidden"), ("missing.txt", "missing"), ("out", "symlink out"),
                         ("own", "symlink out"), ("sub/n.md", "owner data"), ("inner", "owner data"), ("/etc/passwd", "outside"),
                         ("a\\b", "outside"), (3, "outside")):
            code, out = self.post("/api/files/delete-many", {"paths": ["a.txt", bad]})
            self.assertEqual(code, 400, bad)
            self.assertIn(why, out["error"], bad)
            self.assertEqual(out["path"], bad)
        for body in ({"paths": []}, {"paths": "a.txt"}, {}, ["a.txt"]):
            self.assertEqual(self.post("/api/files/delete-many", body)[0], 400, body)
        self.assertTrue(os.path.exists(os.path.join(self.drop, "a.txt")) and os.path.exists(self.orig))
        self.assertFalse(os.path.exists(self.trash))

    def test_restore_newest_and_refusals(self):
        for text in ("old", "new"):
            open(os.path.join(self.drop, "a.txt"), "w").write(text)
            self.assertEqual(self.post("/api/files/delete-many", {"paths": ["a.txt"]})[0], 200)
        self.assertEqual(self.post("/api/files/restore", {"paths": ["a.txt"]})[0], 200)
        self.assertEqual(open(os.path.join(self.drop, "a.txt")).read(), "new")
        code, out = self.post("/api/files/restore", {"paths": ["a.txt"]})
        self.assertEqual((code, out["failed"]), (409, ["a.txt"]))
        for bad in ("../orig.txt", ".hidden", "", None):
            self.assertEqual(self.post("/api/files/restore", {"paths": [bad]})[0], 400, bad)
        self.assertEqual(self.post("/api/files/restore", {"paths": []})[0], 400)

    def test_partial_failure_keeps_undo_for_what_went(self):
        names = ["p%d.txt" % i for i in range(1, 6)]
        self.many(*names)
        bin_dir = os.path.join(self.tmp.name, "bin")
        os.makedirs(bin_dir)
        with open(os.path.join(bin_dir, "gio"), "w") as f:
            f.write('#!/bin/sh\nshift 2\ni=0\nfor p; do i=$((i+1))\n'
                    '  if [ $i -eq 3 ]; then echo "gio: $p: refused" >&2; exit 1; fi\n  %s trash -- "$p"\ndone\n'
                    % shutil.which("gio"))
        os.chmod(os.path.join(bin_dir, "gio"), 0o755)
        with mock.patch.dict(os.environ, {"PATH": bin_dir + os.pathsep + os.environ["PATH"]}):
            code, out = self.post("/api/files/delete-many", {"paths": names})
        self.assertEqual((code, out["trashed"], out["failed"]), (207, names[:2], names[2:]))
        code, out = self.post("/api/files/restore", {"paths": out["trashed"]})
        self.assertEqual((code, out["restored"], out["failed"]), (200, names[:2], []))
        self.assertTrue(all(os.path.isfile(os.path.join(self.drop, n)) for n in names))

    def test_timeout_capped_and_big_batch_refused_with_count(self):
        names = ["t%d" % i for i in range(2000)]
        self.many(*names)
        seen = []

        def slow(cmd, **kw):
            seen.append(kw["timeout"])
            raise subprocess.TimeoutExpired(cmd, kw["timeout"])
        with mock.patch("subprocess.run", slow):
            code, out = self.post("/api/files/delete-many", {"paths": names})
        self.assertEqual(seen, [server.TRASH_CAP])
        self.assertLessEqual(seen[0], 120)
        self.assertEqual((code, len(out["failed"]), out["trashed"]), (500, 2000, []))
        self.assertIn("timed out after 120 s", out["error"])
        code, out = self.post("/api/files/delete-many", {"paths": names + ["a.txt"]})
        self.assertEqual((code, out["count"]), (400, 2001))
        self.assertIn("2001", out["error"])

    def logged(self, path, body, **headers):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code, out = self.post(path, body, **headers)
        return code, out, [l for l in err.getvalue().splitlines() if l.startswith("files ")]

    def test_delete_many_and_restore_journal_who(self):
        self.many("a.txt", "b.txt", "c.txt", "d.txt")
        who = {"X-Forwarded-For": "100.64.0.7, 127.0.0.1", "User-Agent": "Phone/" + "x" * 200,
               "Tailscale-User-Login": "owner@example.test"}
        names = ["a.txt", "b.txt", "c.txt", "d.txt"]
        code, out, lines = self.logged("/api/files/delete-many", {"paths": names}, **who)
        self.assertEqual((code, len(lines)), (200, 1))
        self.assertIn('files delete-many n=4 trashed=4 first=["a.txt", "b.txt", "c.txt"] ip="100.64.0.7"', lines[0])
        self.assertIn('ua="Phone/%s"' % ("x" * 74), lines[0])
        self.assertIn('ts-user="owner@example.test"', lines[0])
        code, out, lines = self.logged("/api/files/restore", {"paths": names}, **who)
        self.assertEqual((code, len(lines)), (200, 1))
        self.assertTrue(lines[0].startswith('files restore n=4 restored=4 first=["a.txt", "b.txt", "c.txt"] ip="100.64.0.7"'))
        code, out, lines = self.logged("/api/files/delete-many", {"paths": ["a.txt"], "dry": True}, **who)
        self.assertEqual((code, lines), (200, []))

    def test_single_delete_journal_peer_ip(self):
        code, out, lines = self.logged("/api/files/delete", {"path": "linked.txt"})
        self.assertEqual((code, len(lines)), (200, 1))
        self.assertIn('files delete n=1 trashed=1 first=["linked.txt"] ip="127.0.0.1"', lines[0])
        self.assertIn('ts-user="-"', lines[0])

    def test_restore_limit_is_max_batch(self):
        self.many("a.txt", "b.txt", "c.txt")
        saved = server.MAX_BATCH
        server.MAX_BATCH = 2
        try:
            self.assertEqual(self.post("/api/files/restore", {"paths": ["a.txt", "b.txt", "c.txt"]})[0], 400)
            self.assertEqual(self.post("/api/files/delete-many", {"paths": ["a.txt", "b.txt", "c.txt"]})[0], 400)
        finally:
            server.MAX_BATCH = saved

    def test_restore_over_limit_names_count_and_limit(self):
        saved = server.MAX_BATCH
        server.MAX_BATCH = 2
        try:
            code, out = self.post("/api/files/restore", {"paths": ["a.txt", "b.txt", "c.txt"]})
        finally:
            server.MAX_BATCH = saved
        self.assertEqual((code, out["count"], out["error"]), (400, 3, "too many: 3 items, at most 2 per request"))

    def test_refused_single_delete_journals_nothing(self):
        for body in ({}, {"path": 7}, []):
            code, out, lines = self.logged("/api/files/delete", body)
            self.assertEqual((code, lines), (400, []))

    def test_trash_rc0_with_survivor_is_207(self):
        names = ["s1.txt", "s2.txt", "s3.txt"]
        self.many(*names)
        bin_dir = os.path.join(self.tmp.name, "bin")
        os.makedirs(bin_dir)
        with open(os.path.join(bin_dir, "gio"), "w") as f:
            f.write('#!/bin/sh\nshift 2\n%s trash -- "$1"\nexit 0\n' % shutil.which("gio"))
        os.chmod(os.path.join(bin_dir, "gio"), 0o755)
        with mock.patch.dict(os.environ, {"PATH": bin_dir + os.pathsep + os.environ["PATH"]}):
            code, out = self.post("/api/files/delete-many", {"paths": names})
        self.assertEqual((code, out["trashed"], out["failed"]), (207, names[:1], names[1:]))
        self.assertIn("left 2 of 3", out["error"])


if __name__ == "__main__":
    unittest.main()
