"""swr survives a forget() that drops a block while missing blocks are still being computed."""
import os, sys, threading, time, unittest
from unittest import mock
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


class SwrTick(unittest.TestCase):
    def setUp(self):
        self.saved = dict(cache._cache)
        cache._cache.clear()

    def tearDown(self):
        cache._cache.clear()
        cache._cache.update(self.saved)

    def test_slow_block_refreshes_on_every_ttl_tick(self):
        clock = [1000.0]

        def slow():
            clock[0] += 0.3
            return clock[0]

        blocks = {"slow": (slow, 0)}
        with mock.patch.object(cache.time, "time", lambda: clock[0]):
            computes = []
            for tick in range(6):
                clock[0] = 1000.0 + tick * cache.TTL
                before = cache._cache.get("slow", {}).get("tried")
                cache.swr(blocks)
                while cache._refreshing:
                    time.sleep(0.01)
                computes.append(cache._cache["slow"]["tried"] != before)
        self.assertEqual(computes, [True] * 6)

if __name__ == "__main__":
    unittest.main()
