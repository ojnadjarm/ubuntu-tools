"""Tests of the anchors: seeds tied to surface points, stable ids, octaves that fade in."""
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))

from atelier.anchor import SeedBank  # noqa: E402
from atelier.scene import Camera  # noqa: E402

SIZE = (320, 180)


def wall(y=10.0, half=4.0):
    """A square wall facing -y (toward a camera at the origin), two triangles."""
    V = np.array([[-half, y, -half], [half, y, -half], [half, y, half], [-half, y, half]], np.float32)
    return V, np.array([[0, 2, 1], [0, 3, 2]], np.int32)


def bank(octaves=8, **kw):
    V, F = wall(**kw)
    return SeedBank(V, F, 3, 7, "course", 0.5, 11, octaves=octaves), V


def cam_at(x, y, z=0.0):
    return Camera.aim([x, y, z], [x, y + 1.0, z], 0.0, 36.0, SIZE)


class Ids(unittest.TestCase):
    def test_ids_stable(self):
        """A seed keeps its id, place, normal and octave whatever camera asks for it."""
        b, V = bank()
        a, c = b.place(V, cam_at(0.0, 2.0), 8.0), b.place(V, cam_at(1.5, 6.0, 0.7), 8.0)
        for s in (a, c):
            self.assertEqual(len(np.unique(s.id)), len(s.id))
        common, ia, ic = np.intersect1d(a.id, c.id, return_indices=True)
        self.assertGreater(len(common), 200)
        np.testing.assert_allclose(a.P[ia], c.P[ic], atol=1e-6)
        np.testing.assert_allclose(a.N[ia], c.N[ic], atol=1e-6)
        np.testing.assert_array_equal(a.octave[ia], c.octave[ic])
        again = b.place(V, cam_at(0.0, 2.0), 8.0)
        np.testing.assert_array_equal(a.id, again.id)

    def test_seeds_ride_the_surface(self):
        """Moved vertices carry the seeds: same ids, places moved with the surface."""
        b, V = bank()
        cam = cam_at(0.0, 2.0)
        a = b.place(V, cam, 8.0)
        moved = b.place(V + np.float32([0.0, 0.0, 0.01]), cam, 8.0)
        common, ia, im = np.intersect1d(a.id, moved.id, return_indices=True)
        self.assertGreater(len(common), 0.9 * len(a.id))
        np.testing.assert_allclose(moved.P[im] - a.P[ia], [[0.0, 0.0, 0.01]] * len(common), atol=1e-5)


class Octaves(unittest.TestCase):
    def test_octave_fade(self):
        """Halving the distance adds strokes, each fading in from 0; none jumps or leaves the middle of the view."""
        b, V = bank()
        ys = np.linspace(2.0, 6.0, 49)  # wall distance 8 m -> 4 m
        prev, added, top = {}, 0, []
        for y in ys:
            s = b.place(V, cam_at(0.0, y), 8.0)
            xy, _ = cam_at(0.0, y).project(s.P)
            mid = (np.abs(xy[:, 0] - SIZE[0] / 2) < SIZE[0] / 4) & (np.abs(xy[:, 1] - SIZE[1] / 2) < SIZE[1] / 4)
            now = dict(zip(s.id[mid].tolist(), s.opacity[mid].tolist()))
            top.append(int(s.octave.max()))
            for k, op in now.items():
                if k in prev:
                    self.assertLessEqual(abs(op - prev[k]), 0.15, (y, k))
                elif prev:
                    added += 1
                    self.assertLessEqual(op, 0.15, (y, k))
            if prev:
                inner = set(s.id.tolist())
                for k, op in prev.items():
                    if k not in inner:
                        self.assertLessEqual(op, 0.15, (y, k))
            prev = now
        self.assertGreater(added, 100)
        self.assertEqual(top[-1], top[0] + 1)  # half the distance: one octave more
        self.assertTrue(((s.opacity >= 0) & (s.opacity <= 1)).all())
        self.assertTrue((s.opacity[s.octave == 0] == 1).all())


if __name__ == "__main__":
    unittest.main()
