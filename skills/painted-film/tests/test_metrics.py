"""Tests of the harness: each measure must catch what it is built to catch and pass a clean clip."""
import os
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
sys.path.insert(0, os.path.join(HERE, "fixtures"))

import clips  # noqa: E402
from atelier.metrics import DEFAULT_GATES, flick, gate, lookdist, purity, subframe  # noqa: E402


class Flick(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        t = cls.tmp.name
        cls.clean = clips.moving(os.path.join(t, "clean"))
        cls.screen = clips.moving(os.path.join(t, "screen"), grain="screen")
        cls.fresh = clips.moving(os.path.join(t, "fresh"), grain="fresh")
        cls.wobble = clips.wobble(os.path.join(t, "wobble"))
        cls.last = clips.N - 1

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_flick_floor(self):
        r = flick(self.clean, 0, self.last)
        self.assertLess(r["excess"], 0.003, r)
        self.assertGreater(r["floor"], 0.0, r)

    def test_flick_catches_screen_grain(self):
        r = flick(self.screen, 0, self.last, flow_dir=self.clean)
        self.assertIn("excess", gate(r, DEFAULT_GATES), r)

    def test_flick_catches_fresh_grain(self):
        r = flick(self.fresh, 0, self.last, flow_dir=self.clean)
        self.assertIn("excess", gate(r, DEFAULT_GATES), r)

    def test_tile_catches_wobble(self):
        r = flick(self.wobble, 0, self.last)
        self.assertIn("tile", gate(r, DEFAULT_GATES), r)
        self.assertNotIn("tile", gate(flick(self.clean, 0, self.last), DEFAULT_GATES))


class Look(unittest.TestCase):
    def test_lookdist_self(self):
        t = clips.look_target()
        self.assertEqual(lookdist(t, t)["palette_dist"], 0.0)

    def test_lookdist_t2015_fails(self):
        r = lookdist(clips.look_bad(), clips.look_target())
        failed = gate(r, DEFAULT_GATES)
        for name in ("palette_dist", "warm", "cool"):
            self.assertIn(name, failed, r)


class Gates(unittest.TestCase):
    def test_gate_names_failures(self):
        gates = {"excess": ["<=", 0.015], "cool": [">=", 20], "purity": ["==", True], "pop": ["<=", 0.01]}
        self.assertEqual(gate({"excess": 0.02, "cool": 25, "purity": False}, gates), ["excess", "purity"])
        self.assertEqual(gate({"excess": 0.01, "cool": 19.0, "purity": True}, gates), ["cool"])


class Render(unittest.TestCase):
    def test_purity_catches_counter(self):
        n = [0]

        def counting(t):
            n[0] += 1
            return np.full((8, 8, 3), n[0], np.uint8)

        self.assertFalse(purity(counting, 1.0))
        self.assertTrue(purity(lambda t: np.full((8, 8, 3), int(t * 10), np.uint8), 1.0))

    def test_subframe_catches_step(self):
        x = np.arange(64, dtype=np.float32)[None, :, None]

        def pan(t):
            return np.repeat(np.clip(128 + 60 * np.sin((x + 30 * t) / 5), 0, 255), 16, 0).astype(np.uint8)

        def step(t):
            return np.full((16, 64, 3), 200 if t >= 0.5 else 50, np.uint8) + pan(t) // 8

        self.assertLessEqual(subframe(pan, 0.3, 24), 0.2)
        self.assertGreater(subframe(step, 0.5 - 1 / 480, 24), 0.2)


if __name__ == "__main__":
    unittest.main()
