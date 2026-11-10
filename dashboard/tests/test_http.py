"""Transport: gzip, ETag/304, Range and the keep-alive stall, on a throwaway server and drop fixture."""
import email.message, gzip, http.client, io, json, os, re, socket, subprocess, sys, tempfile, threading, time, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server
from dash.http import STATIC_CACHE

BUDGET = os.path.expanduser("~/agents/bin/tests/lib/budget.sh")


IMPORT = re.compile(r'^\s*(?:import|export)\s[^;]*?from\s*["\']([^"\']+)["\']|^\s*import\s*["\']([^"\']+)["\']', re.M)


def static_imports(root, url, seen):
    """Add url and every module it statically imports (not import()) to seen."""
    if url in seen:
        return
    seen.add(url)
    for m in IMPORT.finditer(open(os.path.join(root, url.lstrip("/"))).read()):
        spec = m.group(1) or m.group(2)
        static_imports(root, spec if spec.startswith("/") else os.path.normpath(os.path.join(os.path.dirname(url), spec)), seen)


class Http(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.drop = server.DROP
        server.DROP = cls.tmp.name
        open(os.path.join(cls.tmp.name, "blob.bin"), "wb").write(bytes(range(256)) * 4)
        open(os.path.join(cls.tmp.name, "empty.bin"), "wb").close()
        for i in range(40):
            open(os.path.join(cls.tmp.name, "note-%02d.txt" % i), "w").write("x")
        open(os.path.join(cls.tmp.name, "café—notes.txt"), "w").write("x")
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
            cache = STATIC_CACHE if path.startswith("/static/") else "no-cache"
            self.assertEqual(r.getheader("Cache-Control"), cache, path)
            r, body = self.get(path, **{"Accept-Encoding": enc, "If-None-Match": tag})
            self.assertEqual((r.status, body, r.getheader("Cache-Control")), (304, b"", cache), path)
            r, _ = self.get(path, **{"Accept-Encoding": enc, "If-None-Match": '"stale"'})
            self.assertEqual(r.status, 200, path)

    def test_pages_revalidate_every_load(self):
        for path in ("/", "/static/next/index.html", "/static/machine.html"):
            r, _ = self.get(path)
            self.assertEqual((r.status, r.getheader("Cache-Control")), (200, "no-cache"), path)

    def test_first_screen_modules_preloaded(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        page = open(os.path.join(root, "static/next/index.html")).read()
        preload = set(re.findall(r'<link rel="modulepreload" href="([^"]+)">', page))
        first = re.search(r'load: "\./([^"]+)"', open(os.path.join(root, "static/next/js/screens.js")).read()).group(1)
        need = set()
        for entry in ("/static/next/js/app.js", "/static/next/js/" + first):
            static_imports(root, entry, need)
        self.assertEqual(sorted(need - preload), [], "first-screen modules missing from modulepreload in index.html")

    def test_boot_api_preloaded(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        page = open(os.path.join(root, "static/next/index.html")).read()
        preload = set(re.findall(r'<link rel="preload" href="([^"]+)" as="fetch" crossorigin>', page))
        self.assertEqual(preload, {"/api/status", "/api/agents", "/api/seen"})

    def test_static_cache_has_no_stale_window(self):
        self.assertNotIn("stale-while-revalidate", STATIC_CACHE, "a stale window outlives max-age, so a deploy can miss the minute")

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
        r, _ = self.get("/files/blob.bin", Range="bytes=2000-")
        self.assertEqual((r.status, r.getheader("Content-Range")), (416, "bytes */1024"))

    def test_range_on_empty_file(self):
        r, body = self.get("/files/empty.bin", Range="bytes=0-")
        self.assertEqual((r.status, body, r.getheader("Content-Range")), (200, b"", None))

    def test_download_non_latin1_name(self):
        r, body = self.get("/files/caf%C3%A9%E2%80%94notes.txt?dl=1")
        self.assertEqual((r.status, body), (200, b"x"))
        self.assertEqual(r.getheader("Content-Disposition"),
                         "attachment; filename=\"caf_notes.txt\"; filename*=UTF-8''caf%C3%A9%E2%80%94notes.txt")

    def test_post_is_no_store(self):
        r, _ = self.get("/api/nothing", method="POST")
        self.assertEqual((r.status, r.getheader("Cache-Control"), r.getheader("ETag")), (404, "no-store", None))

    def test_foreign_host_get_refused(self):
        r, body = self.get("/api/ls", Host="evil.example:19998")
        self.assertEqual((r.status, json.loads(body)), (403, {"error": "unknown host"}))

    def test_foreign_host_post_refused(self):
        r, body = self.get("/api/nothing", method="POST", Host="evil.example")
        self.assertEqual((r.status, json.loads(body)), (403, {"error": "unknown host"}))

    def test_foreign_host_ip_literal_passes(self):
        for host in ("127.0.0.1:19998", "[::1]:19998", "100.64.0.1"):
            r, _ = self.get("/api/ls", Host=host)
            self.assertEqual(r.status, 200, host)

    def test_foreign_host_own_names_pass(self):
        from dash.env import HOST, PUBLIC_HOST
        for host in (PUBLIC_HOST + ":8498", PUBLIC_HOST.split(".")[0], HOST + ".local:19998", "localhost:19998", socket.gethostname()):
            r, _ = self.get("/api/ls", Host=host)
            self.assertEqual(r.status, 200, host)

    def test_head_has_no_body(self):
        r, body = self.get("/static/eye.css", method="HEAD", **{"Accept-Encoding": "gzip"})
        self.assertEqual((r.status, body), (200, b""))
        self.assertGreater(int(r.getheader("Content-Length")), 0)
        r, body = self.get("/api/ls")
        self.assertEqual(json.loads(body)["path"], "")

    def test_head_file_has_no_body(self):
        s = socket.create_connection(self.srv.server_address, timeout=0.5)
        s.sendall(b"HEAD /files/blob.bin HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        data = b""
        try:
            while chunk := s.recv(65536):
                data += chunk
        except socket.timeout:
            pass
        s.close()
        head, _, rest = data.partition(b"\r\n\r\n")
        self.assertIn(b"Content-Length: 1024", head)
        self.assertEqual(rest, b"")

    def test_keep_alive_no_stall(self):
        worst = 0
        for _ in range(5):
            t = time.perf_counter()
            self.get("/api/ls")
            worst = max(worst, time.perf_counter() - t)
        budget = float(subprocess.check_output([BUDGET, "0.02"], text=True))
        print("keep-alive worst %.4f s, budget %.3f s" % (worst, budget))
        self.assertLess(worst, budget, "keep-alive worst %.4f s over budget %.3f s" % (worst, budget))

    def test_unread_post_body_leaves_the_connection_usable(self):
        big = b'{"id": "%s"}' % (b"a" * 5000)
        for path, body, headers in (("/nope", b"x" * 50, {}), ("/api/voice/delete", big, {"Content-Type": "application/json"}),
                                    ("/api/voice/delete", b'{"id": 1}', {"Content-Type": "application/json", "Origin": "http://other"}),
                                    ("/api/voice/delete", b'{"id": 1}', {"Content-Type": "text/plain"})):
            self.conn.request("POST", path, body, headers)
            self.conn.getresponse().read()
            r, _ = self.get("/api/ls")
            self.assertEqual(r.status, 200, (path, headers))

    def test_bad_content_length_is_a_400(self):
        for path, ctype in (("/api/voice/clip", "audio/webm"), ("/api/voice/delete", "application/json")):
            for length in ("abc", "-1"):
                conn = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=3)
                conn.putrequest("POST", path)
                conn.putheader("Content-Type", ctype)
                conn.putheader("Content-Length", length)
                conn.endheaders()
                self.assertEqual(conn.getresponse().status, 400, (path, length))
                conn.close()

    def test_non_object_body_is_a_400_not_a_dropped_connection(self):
        tmp = tempfile.TemporaryDirectory()
        own = {"Content-Type": "application/json", "Tailscale-User-Login": "owner@example.com"}
        with tmp, mock.patch.dict(os.environ, HARNESS_HOME=tmp.name, CHAT_OWNER_LOGIN="owner@example.com"):
            for path, body in (("/api/chat/seen", b"[]"), ("/api/chat/seen", b'"x"'), ("/api/chat/post", b"[]"), ("/api/chat/post", b"7")):
                conn = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=3)
                conn.request("POST", path, body, own)
                r = conn.getresponse()
                self.assertIn(r.status, (400, 422), (path, body))
                self.assertIn("error" if r.status == 400 else "held", json.loads(r.read()), (path, body))
                conn.close()

    def test_non_object_body_returns_empty_of_the_callers_type(self):
        from dash.http import Handler
        for raw, empty, want in ((b"[]", {}, {}), (b'"x"', {}, {}), (b"null", {}, {}), (b'{"a": 1}', [], []),
                                 (b'{"a": 1}', {}, {"a": 1}), (b'["k"]', [], ["k"])):
            h = Handler.__new__(Handler)
            h.headers = email.message.Message()
            h.headers["Content-Type"], h.headers["Content-Length"] = "application/json", str(len(raw))
            h.rfile = io.BytesIO(raw)
            self.assertEqual(h.body_json(4096, empty), want, raw)

    def test_idle_connection_is_closed_after_the_timeout(self):
        from dash.http import Handler
        self.assertEqual(Handler.timeout, 30)
        with mock.patch.object(Handler, "timeout", 0.3):
            s = socket.create_connection(self.srv.server_address, timeout=5)
            s.sendall(b"GET /api/ls HT")
            t = time.perf_counter()
            self.assertEqual(s.recv(1024), b"")
            s.close()
        self.assertLess(time.perf_counter() - t, 3)

    def test_brand_in_page_titles(self):
        from dash import http as dh
        was = dh.BRAND
        try:
            for brand, want in (("", b"<title>What runs on this machine</title>"), ("A & B", b"<title>What runs on this machine \xc2\xb7 A &amp; B</title>")):
                dh.BRAND = brand
                dh._assets.clear()
                r, body = self.get("/static/machine.html")
                self.assertIn(want, body)
            r, body = self.get("/")
            self.assertIn(b" \xc2\xb7 A &amp; B</title>", body)
        finally:
            dh.BRAND = was
            dh._assets.clear()


class MainIdle(unittest.TestCase):
    def test_main_serves_without_poll_timer(self):
        """main() blocks in select on every bind instead of waking every 0.5 s."""
        from dash import http as dh
        calls, done = [], threading.Event()

        def fake(srv, poll_interval=0.5):
            calls.append(poll_interval)
            srv.server_close()
            if len(calls) == 2:
                done.set()

        was = (dh.BINDS, dh.PORT, dh.Server.serve_forever)
        dh.BINDS, dh.PORT, dh.Server.serve_forever = ["127.0.0.1", "::1"], 0, fake
        try:
            dh.main()
            self.assertTrue(done.wait(5))
        finally:
            dh.BINDS, dh.PORT, dh.Server.serve_forever = was
        self.assertEqual(calls, [None, None])


if __name__ == "__main__":
    unittest.main()
