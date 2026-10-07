"""swr survives a forget() that drops a block while missing blocks are still being computed."""
import os, sys, threading, time, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash import cache


class SwrForget(unittest.TestCase):
    def setUp(self):
        self.saved = dict(cache._cache)
        cache._cache.clear()

    def tearDown(self):
        cache._cache.clear()
        cache._cache.update(self.saved)

    def test_forget_mid_fill_returns_empty_value(self):
        blocks = {"slow": (lambda: time.sleep(0.3) or "s", ""), "drop": (lambda: {"a": 1}, {})}
        cache.cached("drop", 0, *blocks["drop"])
        timer = threading.Timer(0.1, cache.forget, ("drop",))
        timer.start()
        out = cache.swr(blocks)
        timer.join()
        self.assertEqual(out, {"slow": "s", "drop": {}})


if __name__ == "__main__":
    unittest.main()
