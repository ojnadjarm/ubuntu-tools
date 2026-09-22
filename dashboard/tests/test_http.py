"""Transport: gzip, ETag/304, Range and the keep-alive stall, on a throwaway server and drop fixture."""
import gzip, http.client, json, os, sys, tempfile, threading, time, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server


class Http(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.drop = server.DROP
        server.DROP = cls.tmp.name
        open(os.path.join(cls.tmp.name, "blob.bin"), "wb").write(bytes(range(256)) * 4)
        for i in range(40):
            open(os.path.join(cls.tmp.name, "note-%02d.txt" % i), "w").write("x")
        cls.srv = server.Server(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        server.DROP = cls.drop
        cls.tmp.cleanup()

    def setUp(self):
        self.conn = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=10)

    def tearDown(self):
        self.conn.close()

    def get(self, path, method="GET", **headers):
        self.conn.request(method, path, headers=headers)
        r = self.conn.getresponse()
        return r, r.read()

    def test_gzip_static_and_api(self):
        for path in ("/static/eye.css", "/api/ls"):
            r, body = self.get(path, **{"Accept-Encoding": "gzip"})
            self.assertEqual(r.getheader("Content-Encoding"), "gzip", path)
            plain, raw = self.get(path)
            self.assertIsNone(plain.getheader("Content-Encoding"), path)
            self.assertEqual(gzip.decompress(body), raw, path)
            self.assertLess(len(body), len(raw), path)

    def test_small_body_not_gzipped(self):
        r, body = self.get("/files/blob.bin?x", **{"Accept-Encoding": "gzip"})
        self.assertIsNone(r.getheader("Content-Encoding"))
        r, body = self.get("/nope", **{"Accept-Encoding": "gzip"})
        self.assertEqual((r.status, r.getheader("Content-Encoding")), (404, None))

    def test_etag_304(self):
        for path, enc in (("/static/eye.css", "gzip"), ("/api/ls", "gzip"), ("/api/ls", ""), ("/files/blob.bin", "")):
            r, _ = self.get(path, **{"Accept-Encoding": enc})
            tag = r.getheader("ETag")
            self.assertTrue(tag, path)
            self.assertEqual(r.getheader("Cache-Control"), "no-cache")
            r, body = self.get(path, **{"Accept-Encoding": enc, "If-None-Match": tag})
            self.assertEqual((r.status, body), (304, b""), path)
            r, _ = self.get(path, **{"Accept-Encoding": enc, "If-None-Match": '"stale"'})
            self.assertEqual(r.status, 200, path)

    def test_gzip_and_identity_tags_differ(self):
        a, _ = self.get("/api/ls", **{"Accept-Encoding": "gzip"})
        b, _ = self.get("/api/ls")
        self.assertNotEqual(a.getheader("ETag"), b.getheader("ETag"))

    def test_range(self):
        r, body = self.get("/files/blob.bin", Range="bytes=0-99")
        self.assertEqual((r.status, len(body), r.getheader("Content-Range")), (206, 100, "bytes 0-99/1024"))
        self.assertEqual(body, bytes(range(100)))
        r, body = self.get("/files/blob.bin", Range="bytes=-24")
        self.assertEqual((r.status, body), (206, bytes(range(232, 256))))

    def test_post_is_no_store(self):
        r, _ = self.get("/api/nothing", method="POST")
        self.assertEqual((r.status, r.getheader("Cache-Control"), r.getheader("ETag")), (404, "no-store", None))

    def test_head_has_no_body(self):
        r, body = self.get("/static/eye.css", method="HEAD", **{"Accept-Encoding": "gzip"})
        self.assertEqual((r.status, body), (200, b""))
        self.assertGreater(int(r.getheader("Content-Length")), 0)
        r, body = self.get("/api/ls")
        self.assertEqual(json.loads(body)["path"], "")

    def test_keep_alive_no_stall(self):
        worst = 0
        for _ in range(5):
            t = time.perf_counter()
            self.get("/api/ls")
            worst = max(worst, time.perf_counter() - t)
        self.assertLess(worst, 0.02)

    def test_brand_in_page_titles(self):
        from dash import http as dh
        was = dh.BRAND
        try:
            for brand, want in (("", b"<title>Voice training</title>"), ("A & B", b"<title>Voice training \xc2\xb7 A &amp; B</title>")):
                dh.BRAND = brand
                dh._assets.clear()
                for path in ("/voice", "/static/voice.html"):
                    r, body = self.get(path)
                    self.assertIn(want, body, path)
            r, body = self.get("/")
            self.assertIn(b" \xc2\xb7 A &amp; B</title>", body)
        finally:
            dh.BRAND = was
            dh._assets.clear()


if __name__ == "__main__":
    unittest.main()
