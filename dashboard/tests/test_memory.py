"""RSS stays flat over long polling: 200 rounds of /api/status (fixture blocks, refreshed every call) plus static, /thumb/ and /files/ on a throwaway drop."""
import gc, http.client, os, sys, tempfile, threading, tracemalloc, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server
from dash import cache
from dash.services import files, system, thumbs
from PIL import Image

PATHS = ["/api/status", "/", "/static/eye.css", "/api/ls?p=sub", "/files/notes.md?md=1", "/files/clip.bin"] + \
        ["/thumb/sub/im%d.png?w=%d" % (i, w) for i in range(3) for w in (160, 320, 640)]


def rows(n):
    """A fixture block: n unit-like rows, built fresh on every refresh like the real blocks."""
    return lambda: [{"unit": "u%d.service" % i, "what": "fixture unit %d" % i, "active": "active", "since": str(i)} for i in range(n)]


def rss_mb():
    with open("/proc/self/status") as f:
        return next(int(l.split()[1]) for l in f if l.startswith("VmRSS")) / 1024


class Harness:
    """In-process server on a throwaway drop and thumb cache, with every /api/status block refreshed per call."""

    def __enter__(self):
        self.tmp = tempfile.TemporaryDirectory()
        drop = os.path.join(self.tmp.name, "drop")
        os.makedirs(os.path.join(drop, "sub"))
        for i in range(3):
            Image.new("RGB", (2400, 1600), (60 * i, 90, 160)).save(os.path.join(drop, "sub", "im%d.png" % i))
        with open(os.path.join(drop, "notes.md"), "w") as f:
            f.write("# Notes\n\n" + "A paragraph with *some* `code` and a [link](x).\n\n" * 400)
        with open(os.path.join(drop, "clip.bin"), "wb") as f:
            f.write(os.urandom(1 << 20))
        self.saved = files.DROP, thumbs.CACHE, system.BLOCKS
        files.DROP, thumbs.CACHE = drop, os.path.join(self.tmp.name, "thumbs")
        system.BLOCKS = {k: (rows(150) if isinstance(v[1], list) and k not in ("agents", "events") else (lambda d=v[1]: d), v[1], 0)
                         for k, v in self.saved[2].items()}
        self.srv = server.Server(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        return self

    def __exit__(self, *exc):
        self.srv.shutdown()
        self.srv.server_close()
        files.DROP, thumbs.CACHE, system.BLOCKS = self.saved
        cache.forget(*self.saved[2])
        self.tmp.cleanup()

    def rounds(self, n):
        """n page loads, each on a fresh connection (a new handler thread, as browsers reconnect)."""
        for _ in range(n):
            c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=30)
            for p in PATHS:
                c.request("GET", p, headers={"Accept-Encoding": "gzip"})
                r = c.getresponse()
                r.read()
                assert r.status == 200, (p, r.status)
            c.close()


def trace(out):
    """Write the top 10 tracemalloc growth sites over 200 rounds (after 20 warm-up rounds) and the RSS curve to out."""
    with Harness() as h:
        h.rounds(20)
        gc.collect()
        tracemalloc.start(12)
        a, r0 = tracemalloc.take_snapshot(), rss_mb()
        h.rounds(100)
        r1 = rss_mb()
        h.rounds(100)
        gc.collect()
        b, r2 = tracemalloc.take_snapshot(), rss_mb()
        tracemalloc.stop()
    diff = b.compare_to(a, "traceback")
    lines = ["rss MB: start %.1f, +100 rounds %.1f, +200 rounds %.1f" % (r0, r1, r2),
             "traced python heap growth: %.1f KiB in %d sites" % (sum(s.size_diff for s in diff) / 1024, len(diff)), ""]
    for s in diff[:10]:
        lines.append("%+.1f KiB %+d blocks" % (s.size_diff / 1024, s.count_diff))
        lines += ["    " + l for l in s.traceback.format()[-6:]]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


class Memory(unittest.TestCase):
    def test_second_hundred_rounds_grow_rss_under_5_mb(self):
        with Harness() as h:
            h.rounds(100)
            before = rss_mb()
            h.rounds(100)
            grew = rss_mb() - before
        self.assertLess(grew, 5, "RSS grew %.1f MB over the second 100 rounds" % grew)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--trace"]:
        trace(sys.argv[2])
    else:
        unittest.main()
