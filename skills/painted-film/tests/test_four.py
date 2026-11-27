"""Tests of the 4D provider: seeds on lines through 4D bodies, placed where the slice cuts them; the cut cache."""
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
sys.path.insert(0, HERE)

from atelier.anchor import SeedBank  # noqa: E402
from atelier.four import Scene4D, SeedBank4D  # noqa: E402
from atelier.four import slicer as S  # noqa: E402
from atelier.paint import solve  # noqa: E402
from atelier.scene import Camera  # noqa: E402
from disc_medium import DiscMedium  # noqa: E402
from test_paint import LOOK, SIZE, flat_ref  # noqa: E402

CAM = Camera.aim([0.6, -7.0, 1.2], [0.0, 0.0, 0.0], 0.0, 30.0, SIZE)


def tesseract():
    V, F = S.box([-1, -1, -1], [1, 1, 1])
    return S.loft([V, V], [-1, 1], F, caps=True)


def tread(a=2.0, b=1.0, c=0.5, h=3.0):
    V, F = S.box([0, 0, 0], [a, b, c])
    thin = V * [0, 1, 1] + [a / 2, 0, 0]
    return S.loft([thin, V, thin], [-h, 0, h], F)


def twisted(rate=0.4):
    """A cube turned about z as w runs: keys every 0.5 in w."""
    V, F = S.box([-1, -1, -1], [1, 1, 1])
    ws = np.linspace(-2, 2, 9)
    keys = [V @ np.array([[np.cos(rate * w), -np.sin(rate * w), 0], [np.sin(rate * w), np.cos(rate * w), 0], [0, 0, 1]]).T for w in ws]
    return S.loft(keys, ws, F)


def cone():
    """A box closing to its centre at w = 3."""
    V, F = S.box([0, 0, 0], [2.0, 1.0, 0.5])
    return S.loft([V, V, V * 0 + [1.0, 0.5, 0.25]], [-3.0, 0.0, 3.0], F)


def straight_tube():
    sv, sf = S.icosphere(2)
    path = np.column_stack([np.zeros((9, 3)), np.linspace(-2, 2, 9)])
    return S.tube(path, np.full(9, 1.2), sv, sf)


def bent_tube():
    sv, sf = S.icosphere(2)
    s = np.linspace(0, np.pi, 41)
    path = np.column_stack([1.6 * np.cos(s), 0 * s, 0 * s, 1.6 * np.sin(s)])
    return S.tube(path, np.full(41, 0.4), sv, sf)


def place(body, sl, px=6.0, rho0=4.0, cam=CAM):
    return SeedBank4D(body, 2, 5, "course", rho0, 9).place(sl, cam, px)


def on_cut(P, N, V, F):
    """Distance of each point to the mesh, and the best agreement of its normal with a triangle within 1e-4 m."""
    A, B, C = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    n = np.cross(B - A, C - A)
    n /= np.linalg.norm(n, axis=1, keepdims=True)
    dist, agree = np.full(len(P), np.inf), np.full(len(P), -1.0)
    for i, p in enumerate(P):
        d = _tri_dist(p, A, B, C)
        dist[i] = d.min()
        near = d < 1e-4
        if near.any():
            agree[i] = (n[near] @ N[i]).max()
    return dist, agree


def _tri_dist(p, A, B, C):
    """Distance from p to each triangle (A, B, C), by its plane or its edges."""
    e0, e1, v = B - A, C - A, p - A
    d00, d01, d11 = (e0 * e0).sum(1), (e0 * e1).sum(1), (e1 * e1).sum(1)
    d20, d21 = (v * e0).sum(1), (v * e1).sum(1)
    den = np.maximum(d00 * d11 - d01 * d01, 1e-30)
    b1, b2 = (d11 * d20 - d01 * d21) / den, (d00 * d21 - d01 * d20) / den
    inside = (b1 >= 0) & (b2 >= 0) & (b1 + b2 <= 1)
    plane = np.linalg.norm(v - b1[:, None] * e0 - b2[:, None] * e1, axis=1)

    def seg(a, b):
        ab = b - a
        t = np.clip(((p - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-30), 0, 1)
        return np.linalg.norm(p - a - t[:, None] * ab, axis=1)
    return np.where(inside, plane, np.minimum(np.minimum(seg(A, B), seg(B, C)), seg(C, A)))


def finite(s):
    return all(np.isfinite(getattr(s, k)).all() for k in ("P", "N", "T", "opacity", "px"))


class Place(unittest.TestCase):
    def test_seed_on_cut(self):
        """Every placed seed lies on the cut mesh within 1e-4 m, its normal that of the cut triangle it lies on."""
        for body, sl in ((tread(), S.Slice(1.5)), (twisted(), S.Slice(0.37)), (straight_tube(), S.Slice(0.3)),
                         (tread(), S.Slice(0.7, 0.2)), (twisted(), S.Slice(-0.6, 0.3, axis=1))):
            s = place(body, sl)
            V, F, _ = S.cut(body, sl)
            self.assertGreater(len(s.id), 50)
            self.assertEqual(len(np.unique(s.id)), len(s.id))
            dist, agree = on_cut(s.P, s.N, V, F)
            self.assertLess(dist.max(), 1e-4)
            self.assertGreater(agree.min(), 0.999)

    def test_seed_follows_slide(self):
        """A tesseract sliding in w: its seeds stay put; a cube turning with w: each seed's 3D place is continuous."""
        a = place(tesseract(), S.Slice(-0.5))
        for w in np.linspace(-0.49, 0.5, 12):
            b = place(tesseract(), S.Slice(w))
            np.testing.assert_array_equal(a.id, b.id)
            np.testing.assert_allclose(a.P, b.P, atol=1e-12)
        prev = place(twisted(), S.Slice(0.2))
        for w in np.arange(0.201, 0.21, 0.001):
            cur = place(twisted(), S.Slice(w))
            common, ia, ib = np.intersect1d(prev.id, cur.id, return_indices=True)
            self.assertGreater(len(common), 0.95 * len(prev.id))
            self.assertLess(np.linalg.norm(cur.P[ib] - prev.P[ia], axis=1).max(), 0.002)  # 0.4 rad/w at r <= 1.74
            prev = cur

    def test_grazing_slice(self):
        """A box closing to a point, a tread closing to a card, a body left behind, a slice touching one corner: no
        NaN, nothing left behind, the octaves fade as the cut closes."""
        for w in (2.999, 3.0, 3.0 + 1e-9):
            s = place(tread(), S.Slice(w))
            self.assertTrue(finite(s), w)
            self.assertEqual(len(s.id) == 0, w > 3.0, w)
        cover = []
        for w in (0.0, 2.0, 2.9, 2.99, 2.999, 3.0 - 1e-12, 3.0, 3.0 + 1e-9, 3.2):
            s = place(cone(), S.Slice(w))
            self.assertTrue(finite(s), w)
            cover.append(float((s.opacity * s.px ** 2).sum()))
            if w > 3.0:
                self.assertEqual(len(s.id), 0, w)
        self.assertTrue(all(b <= a * 1.05 for a, b in zip(cover[1:6], cover[2:7])), cover)
        self.assertLess(cover[4], 0.05 * cover[0])
        self.assertEqual(len(place(tesseract(), S.Slice(1.01)).id), 0)
        corner = S.Slice(0.0)
        corner.n, corner.o = np.ones(4) / 2, np.ones(4)
        q, _ = np.linalg.qr(np.column_stack([corner.n, np.eye(4)[:, :3]]))
        corner.E, corner.pivot = q[:, 1:].T, np.zeros(3)
        s = place(tesseract(), corner)
        self.assertTrue(finite(s))
        self.assertLess(len(s.id), 5)

    def test_two_crossings(self):
        """A tube bent through w and back: the slice cuts it twice, each seed line gives two strokes with their own
        ids, and each keeps to its own piece as the slice moves."""
        a, b = place(bent_tube(), S.Slice(1.0)), place(bent_tube(), S.Slice(1.002))
        V, F, _ = S.cut(bent_tube(), S.Slice(1.0))
        for s in (a, b):
            self.assertEqual(len(np.unique(s.id)), len(s.id))
            self.assertGreater((s.P[:, 0] > 0).sum(), 0.3 * len(s.id))
            self.assertGreater((s.P[:, 0] < 0).sum(), 0.3 * len(s.id))
        self.assertLess(on_cut(a.P, a.N, V, F)[0].max(), 1e-4)
        common, ia, ib = np.intersect1d(a.id, b.id, return_indices=True)
        self.assertGreater(len(common), 0.9 * len(a.id))
        np.testing.assert_array_equal(np.sign(a.P[ia, 0]), np.sign(b.P[ib, 0]))
        self.assertLess(np.linalg.norm(a.P[ia] - b.P[ib], axis=1).max(), 0.05)

    def test_fade_smooth_across_facets(self):
        """A slanted tube sliding in w: its seeds cross from facet to facet of the 4D surface, yet their octave fade and
        stroke direction turn smoothly (a small step in w moves neither by much)."""
        sv, sf = S.icosphere(1)
        s = np.linspace(0, 1, 7)
        body = S.tube(np.column_stack([3 * s - 1.5, 0 * s, 0 * s, 2 * s - 1]), 0.6 + 0.3 * s, sv, sf)
        cam = Camera.aim([0.0, -4.0, 0.5], [0.0, 0.0, 0.0], 0.0, 30.0, SIZE)
        worst_op, worst_t = 0.0, 0.0
        for w in np.linspace(-0.4, 0.4, 9):
            a, b = place(body, S.Slice(w), 4.0, 1.0, cam), place(body, S.Slice(w + 1e-3), 4.0, 1.0, cam)
            common, ia, ib = np.intersect1d(a.id, b.id, return_indices=True)
            self.assertGreater(len(common), 100)
            worst_op = max(worst_op, np.abs(a.opacity[ia] - b.opacity[ib]).max())
            worst_t = max(worst_t, np.degrees(np.arccos(np.clip(np.abs((a.T[ia] * b.T[ib]).sum(1)), 0, 1))).max())
        self.assertLess(worst_op, 0.05)
        self.assertLess(worst_t, 2.0)

    def test_new_crossings_fade_in(self):
        """A slice coming down onto the top of a bend: where a seed's line first touches the slice its two crossings
        are born together, faint, and grow in as the slice moves on (no stroke appears at full strength)."""
        cam = Camera.aim([0.0, -6.0, 0.5], [0.0, 0.0, 0.0], 0.0, 30.0, SIZE)
        prev, born = place(bent_tube(), S.Slice(2.0), 6.0, 4.0, cam), 0
        for w in np.arange(1.99, 1.5, -0.01):
            cur = place(bent_tube(), S.Slice(w), 6.0, 4.0, cam)
            new = ~np.isin(cur.id, prev.id)
            born += new.sum()
            if new.any():
                self.assertLess(cur.opacity[new].max(), 0.2, w)
            prev = cur
        self.assertGreater(born, 100)

    def test_turned_slice(self):
        """A turned slice: seeds on its cut, and they move little when the slice turns a little."""
        body = tesseract()
        a, b = place(body, S.Slice(0.0, 0.3)), place(body, S.Slice(0.0, 0.301))
        V, F, _ = S.cut(body, S.Slice(0.0, 0.3))
        dist, agree = on_cut(a.P, a.N, V, F)
        self.assertLess(dist.max(), 1e-4)
        self.assertGreater(agree.min(), 0.999)
        common, ia, ib = np.intersect1d(a.id, b.id, return_indices=True)
        self.assertGreater(len(common), 0.95 * len(a.id))
        self.assertLess(np.linalg.norm(a.P[ia] - b.P[ib], axis=1).max(), 0.01)

    def test_w_constant_equals_3d(self):
        """A body that does not change along w gives the 3D seed bank's fill seeds on its mesh, and the same picture."""
        V = np.array([[-4, 10, -4], [4, 10, -4], [4, 10, 4], [-4, 10, 4], [0, 10, 0]], float)
        F = np.array([[0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]])
        cam = Camera.aim([0.0, 2.0, 0.0], [0.0, 3.0, 0.0], 0.0, 36.0, SIZE)
        three = SeedBank(V, F, 3, 7, "course", 0.5, 11).place(V, cam, 8.0)
        three = type(three)(*(getattr(three, k)[three.kind == 0] for k in three.__dataclass_fields__))  # marks: B2
        four = SeedBank4D(S.loft([V, V], [-5.0, 5.0], F), 3, 7, "course", 0.5, 11).place(S.Slice(0.3), cam, 8.0)
        self.assertGreater(len(three.id), 500)
        np.testing.assert_array_equal(three.id, four.id)
        for k in ("octave", "material", "ident", "kind"):
            np.testing.assert_array_equal(getattr(three, k), getattr(four, k), k)
        for k in ("P", "N", "T", "opacity", "px"):
            np.testing.assert_allclose(getattr(three, k), getattr(four, k), atol=1e-9, err_msg=k)
        ref = flat_ref(cam, [(10.0, -4, 4, -4, 4, 7, lambda x, z: np.stack([0.3 + 0.05 * x, 0.4 + 0.04 * z, 0.5 + 0 * x], -1))])
        pics = [DiscMedium().composite(solve(ref, s, LOOK, SIZE), ref, LOOK, SIZE).astype(int) for s in (three, four)]
        self.assertLessEqual(np.abs(pics[0] - pics[1]).max(), 1)


class Cache(unittest.TestCase):
    def test_cut_cache_equal(self):
        """A body whose cut cannot change between two slices is not cut again, and the cached cut equals a fresh one."""
        Vb, Fb = S.box([-1, -1, -1], [1, 1, 1])
        still = S.merge([S.loft([Vb, Vb], [-60.0, 60.0], Fb, {"tone": np.ones((8, 1))}),
                         S.loft([Vb + 3, Vb + 3, (Vb + 3) * 0.5], [-60.0, 0.0, 1.0], Fb, {"tone": np.ones((8, 1))})])
        moving = S.loft([Vb, Vb * 1.5], [-1.0, 1.0], Fb, {"tone": np.ones((8, 1))})
        ws = [-0.5, -0.5, -0.2, 0.0, 0.0, 0.3, 0.6, 0.6, 1.2, 1.2]
        sc = Scene4D({"stone": still, "flesh": moving}, lambda t: S.Slice(ws[int(t)]), None)
        sc.materials = {"stone": {}, "flesh": {"rule": 2}}
        sc.log = False
        cached = []
        for t in range(len(ws)):
            ms = {m.name: m for m in sc.meshes(float(t))}
            for name, body in (("stone", still), ("flesh", moving)):
                V, F, A = S.cut(body, S.Slice(ws[t]))
                self.assertEqual(ms[name].V.tobytes(), V.astype(np.float32).tobytes())
                self.assertEqual(ms[name].F.tobytes(), F.astype(np.int32).tobytes())
                self.assertEqual(ms[name].attrs["tone"].tobytes(), A["tone"][:, 0].astype(np.float32).tobytes())
                self.assertEqual(ms[name].material, name)
            cached.append(sc.cut_stats[1])
        self.assertEqual(cached, [0, 2, 0, 0, 2, 0, 0, 2, 0, 2])  # the same slice again; flesh left behind past w 1


if __name__ == "__main__":
    unittest.main()
