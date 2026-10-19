"""Thumbnails: WebP output, disk cache, ETag/304 and path confinement, on a throwaway drop and cache."""
import http.client, os, sys, tempfile, threading, time, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server
from dash.services import thumbs
from PIL import Image


class Thumbs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.saved = server.DROP, thumbs.CACHE
        drop = os.path.join(cls.tmp.name, "drop")
        os.makedirs(os.path.join(drop, "sub"))
        Image.new("RGB", (1600, 1000), (200, 40, 40)).save(os.path.join(drop, "sub", "big.png"))
        Image.new("RGBA", (40, 900), (0, 0, 0, 0)).save(os.path.join(drop, "tall.png"))
        Image.new("RGB", (10, 10)).save(os.path.join(cls.tmp.name, "outside.png"))
        open(os.path.join(drop, "note.txt"), "w").write("x")
        server.DROP = drop
        thumbs.CACHE = os.path.join(cls.tmp.name, "cache")
        cls.srv = server.Server(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        server.DROP, thumbs.CACHE = cls.saved
        cls.tmp.cleanup()

    def get(self, path, **headers):
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=10)
        c.request("GET", path, headers=headers)
        r = c.getresponse()
        body = r.read()
        c.close()
        return r, body

    def test_webp_cropped_to_cell(self):
        r, body = self.get("/thumb/sub/big.png?w=320")
        self.assertEqual((r.status, r.getheader("Content-Type")), (200, "image/webp"))
        self.assertEqual(body[8:12], b"WEBP")
        path = os.path.join(self.tmp.name, "t.webp")
        open(path, "wb").write(body)
        self.assertEqual(Image.open(path).size, (320, 200))
        r, body = self.get("/thumb/tall.png")
        self.assertEqual((r.status, body[8:12]), (200, b"WEBP"))

    def test_cached_and_304(self):
        full = os.path.join(server.DROP, "sub", "big.png")
        t = time.perf_counter()
        first = thumbs.thumb(full, 640)
        cold = time.perf_counter() - t
        t = time.perf_counter()
        again = thumbs.thumb(full, 640)
        warm = time.perf_counter() - t
        self.assertEqual(first, again)
        self.assertLess(cold, 0.15)
        self.assertLess(warm, 0.002)
        r, _ = self.get("/thumb/sub/big.png?w=640")
        etag = r.getheader("ETag")
        r, body = self.get("/thumb/sub/big.png?w=640", **{"If-None-Match": etag})
        self.assertEqual((r.status, body), (304, b""))

    def test_concurrent_cold_generation(self):
        full = os.path.join(server.DROP, "sub", "big.png")
        for run in range(10):
            os.utime(full, ns=(run, run))
            gate, errors = threading.Barrier(4), []

            def go():
                gate.wait()
                try:
                    thumbs.thumb(full, 160)
                except OSError as e:
                    errors.append(e)
            ts = [threading.Thread(target=go) for _ in range(4)]
            for t in ts:
                t.start()
            for t in ts:
                t.join()
            self.assertEqual(errors, [], run)

    def test_stale_thumbs_pruned_on_write(self):
        full = os.path.join(server.DROP, "sub", "big.png")
        thumbs.thumb(full, 320)
        os.makedirs(thumbs.CACHE, exist_ok=True)
        stale = os.path.join(thumbs.CACHE, "stale.webp")
        open(stale, "wb").write(b"x")
        old = time.time() - thumbs.MAX_AGE - 60
        os.utime(stale, (old, old))
        os.utime(full, ns=(time.time_ns(), time.time_ns()))
        thumbs.thumb(full, 320)
        self.assertFalse(os.path.exists(stale))
        self.assertTrue(any(n.endswith(".webp") for n in os.listdir(thumbs.CACHE)))

    def test_refuses_traversal_and_non_images(self):
        for p in ("../outside.png", "sub/../../outside.png", "%2e%2e/outside.png", ".hidden.png", "", "note.txt", "missing.png"):
            self.assertEqual(self.get("/thumb/" + p)[0].status, 404, p)


if __name__ == "__main__":
    unittest.main()
