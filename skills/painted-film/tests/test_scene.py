"""Tests of the scene types: camera projection and the ident code."""
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))

from atelier.scene import Camera, RULE_EMITTER, ident_code, ident_decode, ident_of, rule_of  # noqa: E402


class Project(unittest.TestCase):
    def setUp(self):
        self.cam = Camera.aim([1.0, 2.0, 3.0], [1.0, 12.0, 3.0], 0.0, 36.0, (200, 100))

    def test_project_axis_at_centre(self):
        xy, z = self.cam.project(np.array([[1.0, 7.0, 3.0]]))
        np.testing.assert_allclose(xy[0], [99.5, 49.5], atol=1e-9)
        self.assertAlmostEqual(z[0], 5.0)

    def test_project_offset(self):
        xy, z = self.cam.project(np.array([[2.0, 7.0, 3.5]]))  # lens = sensor: f = W px
        np.testing.assert_allclose(xy[0], [99.5 + 200 * 1 / 5, 49.5 - 200 * 0.5 / 5], atol=1e-9)

    def test_camera_json(self):
        c = Camera.from_json(self.cam.to_json())
        np.testing.assert_array_equal(c.R, self.cam.R)
        self.assertEqual(c.size, (200, 100))


class Ident(unittest.TestCase):
    def test_rule_roundtrip(self):
        i = ident_of(RULE_EMITTER, 12345)
        self.assertEqual(int(rule_of(i)), RULE_EMITTER)
        self.assertEqual(int(i) & 0xFFFFF, 12345)

    def test_code_roundtrip(self):
        ids = np.array([0, 1, 4095, 4096, int(ident_of(2, 77)), (1 << 24) - 1])
        got, clean = ident_decode(ident_code(ids))
        np.testing.assert_array_equal(got, ids)
        self.assertTrue(clean.all())

    def test_blend_not_clean(self):
        a, b = ident_code(np.array([int(ident_of(0, 300))]))[0], ident_code(np.array([int(ident_of(1, 9))]))[0]
        for w in np.linspace(0.05, 0.95, 37):
            _, clean = ident_decode(w * a + (1 - w) * b)
            self.assertFalse(bool(clean), w)
        _, clean = ident_decode(0.4 * a)  # against the background
        self.assertFalse(bool(clean))


if __name__ == "__main__":
    unittest.main()
