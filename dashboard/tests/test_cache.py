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


class SwrBlockTtl(unittest.TestCase):
    def setUp(self):
        self.saved = dict(cache._cache)
        cache._cache.clear()

    def tearDown(self):
        cache._cache.clear()
        cache._cache.update(self.saved)

    def test_ttl_300_block_not_refreshed_at_31s(self):
        clock, calls = [1000.0], []
        blocks = {"slow": (lambda: calls.append(1) or len(calls), 0, 300), "fast": (lambda: calls.append(2) or 0, 0)}
        with mock.patch.object(cache.time, "time", lambda: clock[0]):
            cache.swr(blocks)
            clock[0] += 31
            cache.swr(blocks)
            while cache._refreshing:
                time.sleep(0.01)
        self.assertEqual(sorted(calls), [1, 2, 2])

    def test_one_long_ttl_block_per_call_most_overdue_first(self):
        clock, calls = [1000.0], []
        blocks = {"a": (lambda: calls.append("a"), 0, 60), "b": (lambda: calls.append("b"), 0, 120), "c": (lambda: calls.append("c"), 0)}
        with mock.patch.object(cache.time, "time", lambda: clock[0]):
            cache.swr(blocks)
            calls.clear()
            for step in (130, 30):
                clock[0] += step
                cache.swr(blocks)
                while cache._refreshing:
                    time.sleep(0.01)
        self.assertEqual(sorted(calls[:2]), ["a", "c"])
        self.assertEqual(sorted(calls[2:]), ["b", "c"])

    def test_ttl_300_block_stale_only_after_600s(self):
        clock = [1000.0]
        blocks = {"slow": (lambda: 1, 0, 300)}
        with mock.patch.object(cache.time, "time", lambda: clock[0]):
            cache.cached("slow", 0, *blocks["slow"][:2])
            clock[0] += 599
            self.assertEqual(cache.cache_meta(blocks)[0], [])
            clock[0] += 1
            self.assertEqual(cache.cache_meta(blocks)[0], ["slow"])

if __name__ == "__main__":
    unittest.main()
