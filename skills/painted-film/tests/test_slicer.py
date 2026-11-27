"""Slicer tests (copied from fourd/film, T2015): known 4D solids cut at known slices give the known 3D solids."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))

from atelier.four import slicer as S  # noqa: E402


def tesseract():
    V, F = S.box([-1, -1, -1], [1, 1, 1])
    return S.loft([V, V], [-1, 1], F, caps=True)


def tread(a=2.0, b=1.0, c=0.5, h=3.0):
    """A stair tread pointed in w: full width a at w 0, a line at w = +-h."""
    V, F = S.box([0, 0, 0], [a, b, c])
    thin = V * [0, 1, 1] + [a / 2, 0, 0]
    return S.loft([thin, V, thin], [-h, 0, h], F)


class Tesseract(unittest.TestCase):
    def test_straight_cut_is_the_cube(self):
        for w in (-0.9, 0.0, 0.37):
            V, F, _ = S.cut(tesseract(), S.Slice(w))
            self.assertAlmostEqual(S.volume(V, F), 8.0, places=9)
            self.assertTrue(S.closed(V, F))
            self.assertAlmostEqual(np.abs(V).max(), 1.0, places=12)
            self.assertEqual(int((np.abs(np.abs(V) - 1).max(1) < 1e-12).sum()), 8)

    def test_outside_is_empty(self):
        V, F, _ = S.cut(tesseract(), S.Slice(1.5))
        self.assertEqual(len(F), 0)

    def test_turned_cut_is_the_known_prism(self):
        # turned by a in x-w about the centre: x runs to 1/cos(a) while it stays inside |w| <= 1
        a = 0.3
        V, F, _ = S.cut(tesseract(), S.Slice(0.0, a))
        self.assertTrue(S.closed(V, F))
        self.assertAlmostEqual(S.volume(V, F), 8.0 / np.cos(a), places=9)
        self.assertAlmostEqual(V[:, 0].max(), 1 / np.cos(a), places=9)

    def test_diagonal_cut_is_the_octahedron(self):
        sl = S.Slice(0.0)
        n = np.ones(4) / 2
        q, _ = np.linalg.qr(np.column_stack([n, np.eye(4)[:, :3]]))
        sl.n, sl.E, sl.o, sl.pivot = n, q[:, 1:].T, np.zeros(4), np.zeros(3)
        V, F, _ = S.cut(tesseract(), sl)
        self.assertTrue(S.closed(V, F))
        self.assertAlmostEqual(abs(S.volume(V, F)), 32.0 / 3.0, places=9)
        corners = np.unique(np.round(V, 6), axis=0)
        r = np.linalg.norm(corners, axis=1)
        self.assertEqual(int((np.abs(r - 2.0) < 1e-6).sum()), 6)
        self.assertLessEqual(r.max(), 2.0 + 1e-6)


class StairCell(unittest.TestCase):
    def test_tread_narrows_to_a_line(self):
        for w, width in ((0.0, 2.0), (1.5, 1.0), (-2.25, 0.5), (2.999, 2.0 / 3000)):
            V, F, _ = S.cut(tread(), S.Slice(w))
            self.assertTrue(S.closed(V, F))
            self.assertAlmostEqual(S.volume(V, F), width * 1.0 * 0.5, places=9)
            self.assertAlmostEqual(np.ptp(V[:, 0]), width, places=9)
            self.assertAlmostEqual(np.ptp(V[:, 1]), 1.0, places=9)
            self.assertAlmostEqual(np.ptp(V[:, 2]), 0.5, places=9)

    def test_gone_past_its_point(self):
        self.assertEqual(len(S.cut(tread(), S.Slice(3.2))[1]), 0)

    def test_attrs_ride_the_surface(self):
        V0, F = S.box([0, 0, 0], [2, 1, 0.5])
        b = tread()
        b.attrs["anchor"] = np.tile(V0, (3, 1))
        V, _, A = S.cut(b, S.Slice(1.5))
        np.testing.assert_allclose(A["anchor"][:, 1:], V[:, 1:], atol=1e-12)
        self.assertAlmostEqual(np.ptp(A["anchor"][:, 0]), 2.0, places=9)


class Tube(unittest.TestCase):
    def test_tube_along_w_cuts_to_a_ball(self):
        sv, sf = S.icosphere(3)
        path = np.column_stack([np.zeros((9, 3)), np.linspace(-2, 2, 9)])
        V, F, _ = S.cut(S.tube(path, np.full(9, 1.5), sv, sf), S.Slice(0.3))
        self.assertTrue(S.closed(V, F))
        r = np.linalg.norm(V, axis=1)  # points on a prism's diagonal lie on a chord
        self.assertAlmostEqual(r.max(), 1.5, places=9)
        self.assertGreater(r.min(), 1.49)

    def test_bent_tube_cuts_to_two_pieces(self):
        sv, sf = S.icosphere(2)
        s = np.linspace(0, np.pi, 41)
        path = np.column_stack([4 * np.cos(s), 0 * s, 0 * s, 4 * np.sin(s)])
        V, F, _ = S.cut(S.tube(path, np.full(41, 0.5), sv, sf), S.Slice(1.0))
        self.assertTrue(S.closed(V, F))
        self.assertEqual(pieces(F, len(V)), 2)


class Deterministic(unittest.TestCase):
    def test_same_cut_twice_is_byte_equal(self):
        out = [S.cut(tread(), S.Slice(0.7, 0.2)) for _ in range(2)]
        self.assertEqual(out[0][0].tobytes(), out[1][0].tobytes())
        self.assertEqual(out[0][1].tobytes(), out[1][1].tobytes())


def pieces(F, n):
    p = np.arange(n)
    def find(i):
        while p[i] != i:
            p[i] = p[p[i]]
            i = p[i]
        return i
    for a, b, c in F:
        p[find(a)] = find(b)
        p[find(c)] = find(b)
    return len({find(i) for i in np.unique(F)})


if __name__ == "__main__":
    unittest.main()
