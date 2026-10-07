"""Files browser: path confinement and folder listing on a throwaway fixture."""
import os, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = os.path.join(self.tmp.name, "drop")
        os.makedirs(os.path.join(root, "sub"))
        os.makedirs(os.path.join(root, "empty"))
        open(os.path.join(root, "sub", "n.md"), "w").write("# hi\n")
        open(os.path.join(self.tmp.name, "outside.txt"), "w").write("x")
        os.symlink(os.path.join(self.tmp.name, "outside.txt"), os.path.join(root, "esc"))
        os.symlink(self.tmp.name, os.path.join(root, "escdir"))
        server.DROP = root
        self.root = root

    def tearDown(self):
        self.tmp.cleanup()

    def test_refuses_traversal_and_escapes(self):
        for raw in ("../", "../outside.txt", "sub/../../outside.txt", "/etc/passwd", ".hidden", "esc", "escdir", "escdir/outside.txt", "a\\b"):
            self.assertIsNone(server.fs_path(raw), raw)

    def test_accepts_inside(self):
        self.assertEqual(server.fs_path("sub/n.md"), (os.path.realpath(os.path.join(self.root, "sub", "n.md")), "sub/n.md"))
        self.assertEqual(server.fs_path("")[1], "")

    def test_listing(self):
        code, out = server.ls_dir("")
        self.assertEqual(code, 200)
        self.assertEqual([i["name"] for i in out["items"]], ["empty", "sub"])
        code, out = server.ls_dir("sub")
        self.assertEqual((code, out["count"], out["bytes"], out["items"][0]["kind"]), (200, 1, 5, "markdown"))
        self.assertEqual(server.ls_dir("empty"), (200, {"path": "empty", "items": [], "count": 0, "bytes": 0}))
        self.assertEqual(server.ls_dir("../")[0], 404)
        self.assertEqual(server.ls_dir("escdir")[0], 404)

    def test_ls_route_decodes_once(self):
        os.makedirs(os.path.join(self.root, "a%41b"))
        open(os.path.join(self.root, "a%41b", "x.txt"), "w").write("x")
        out = {}
        h = type("H", (), {"path": "/api/ls?p=a%2541b", "json": lambda s, o, c: out.update(code=c, body=o)})()
        server.ls_route(h, "/api/ls")
        self.assertEqual((out["code"], out["body"].get("path")), (200, "a%41b"))

    def test_unreadable_is_not_empty(self):
        os.chmod(os.path.join(self.root, "empty"), 0)
        try:
            code, out = server.ls_dir("empty")
        finally:
            os.chmod(os.path.join(self.root, "empty"), 0o755)
        self.assertEqual(code, 200)
        self.assertEqual((out["items"], out["error"]), ([], "Permission denied"))

    def test_plan_excerpt_survives_memo_overflow(self):
        from dash.services import files
        files._EXCERPTS.clear()
        for i in range(205):
            self.assertEqual(files.plan_excerpt(os.path.join(self.tmp.name, "nope"), str(i)), ("", []))


if __name__ == "__main__":
    unittest.main()
