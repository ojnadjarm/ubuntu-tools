"""Files browser: path confinement, folder listing and drop file serving on a throwaway fixture."""
import contextlib, http.client, io, os, socket, struct, sys, tempfile, threading, unittest
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

    def test_text_preview_is_capped(self):
        from dash.services import files
        open(os.path.join(self.root, "big.log"), "w").write("a" * (6 << 20))
        out = {}
        h = type("H", (), {"send": lambda s, c, b, t: out.update(code=c, body=b)})()
        files.drop_file(h, "big.log", "md=1")
        self.assertEqual(out["code"], 200)
        self.assertLess(len(out["body"]), 3 << 20)
        self.assertIn(b"/files/big.log?dl=1", out["body"])


class Serve(unittest.TestCase):
    """GET, Range, HEAD and a client hang-up against a real fixture server on a free loopback port."""
    SIZE = 12 << 20

    def setUp(self):
        from dash import http as H
        self.tmp = tempfile.TemporaryDirectory()
        server.DROP = self.tmp.name
        self.data = os.urandom(self.SIZE)
        open(os.path.join(self.tmp.name, "v.mp4"), "wb").write(self.data)
        self.srv = type("S", (H.Server,), {"daemon_threads": False, "block_on_close": True})(("127.0.0.1", 0), H.Handler)
        threading.Thread(target=self.srv.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()
        self.port = self.srv.server_address[1]

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        self.tmp.cleanup()

    def get(self, method="GET", path="/files/v.mp4", **headers):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request(method, path, headers=headers)
        r = c.getresponse()
        body = r.read()
        c.close()
        return r, body

    def test_full_get(self):
        r, body = self.get(path="/files/v.mp4?dl=1")
        self.assertEqual((r.status, r.getheader("Content-Length"), r.getheader("Accept-Ranges")), (200, str(self.SIZE), "bytes"))
        self.assertTrue(r.getheader("ETag"))
        self.assertIn('filename="v.mp4"', r.getheader("Content-Disposition"))
        self.assertEqual(body, self.data)

    def test_range_get(self):
        r, body = self.get(Range="bytes=1000-1999")
        self.assertEqual((r.status, r.getheader("Content-Range"), body), (206, "bytes 1000-1999/%d" % self.SIZE, self.data[1000:2000]))
        r, body = self.get(Range="bytes=-10")
        self.assertEqual((r.status, body), (206, self.data[-10:]))
        r, body = self.get(Range="bytes=%d-" % (self.SIZE + 5))
        self.assertEqual(r.status, 416)

    def test_head(self):
        r, body = self.get("HEAD")
        self.assertEqual((r.status, r.getheader("Content-Length"), body), (200, str(self.SIZE), b""))

    def test_disconnect_is_quiet(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            s = socket.create_connection(("127.0.0.1", self.port))
            s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
            s.sendall(b"GET /files/v.mp4 HTTP/1.1\r\nHost: x\r\n\r\n")
            self.assertTrue(s.recv(1 << 16))
            s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            s.close()
            self.srv.shutdown()
            self.srv.server_close()
        self.assertNotIn("Traceback", err.getvalue())


if __name__ == "__main__":
    unittest.main()
