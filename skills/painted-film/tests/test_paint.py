"""Tests of the stroke solver: soft visibility, colour from an area, direction, fixed order, purity, size limit."""
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
sys.path.insert(0, HERE)

from atelier.anchor import SeedBank  # noqa: E402
from atelier.paint import solve  # noqa: E402
from atelier.refio import Ref  # noqa: E402
from atelier.scene import Camera, Seeds  # noqa: E402
from test_anchor import bank, cam_at  # noqa: E402

SIZE = (320, 180)
LOOK = {"max_px": 64, "size": 1.4, "aspect": 2.5}


def flat_ref(cam, rects, bg=(0.1, 0.2, 0.3)):
    """A reference of rectangles facing -y, ray cast: rects are (y, x0, x1, z0, z1, ident, colour or colour(x, z))."""
    W, H = cam.size
    f = cam.lens_mm / cam.sensor_mm * W
    u, v = np.meshgrid(np.arange(W, dtype=float), np.arange(H, dtype=float))
    d = np.stack([(u - (W / 2 - 0.5)) / f, -(v - (H / 2 - 0.5)) / f, -np.ones_like(u)], -1) @ cam.R.T
    depth, ident = np.full((H, W), np.inf, np.float32), np.zeros((H, W), np.int32)
    lit = np.empty((H, W, 3), np.float32)
    lit[:] = bg
    normal = np.zeros((H, W, 3), np.float32)
    for y, x0, x1, z0, z1, k, col in rects:
        with np.errstate(divide="ignore", invalid="ignore"):
            s = (y - cam.pos[1]) / d[..., 1]
        x, z = cam.pos[0] + s * d[..., 0], cam.pos[2] + s * d[..., 2]
        hit = (s > 0) & (s < depth) & (x >= x0) & (x < x1) & (z >= z0) & (z < z1)
        depth[hit], ident[hit], normal[hit] = s[hit], k, (0.0, -1.0, 0.0)
        lit[hit] = col(x[hit], z[hit]) if callable(col) else col
    return Ref(lit, lit.copy(), depth, normal, ident, cam, 1.0, {})


def hand_seeds(P, T, ids, N=(0.0, -1.0, 0.0), px=10.0, ident=1, octave=0):
    k = len(P)
    rep = lambda a, dt: np.repeat(np.asarray(a, dt)[None], k, 0) if np.ndim(a) == 1 else np.asarray(a, dt)
    return Seeds(np.asarray(ids, np.uint64), np.asarray(P, float), rep(N, float), rep(T, float),
                 np.full(k, octave, np.uint8), np.zeros(k, np.int16), np.full(k, ident, np.int32), np.zeros(k, np.uint8),
                 np.zeros(k, np.float32), np.zeros(k, np.float32), np.zeros(k, np.uint8), np.ones(k, np.float32),
                 np.full(k, px, np.float32))


def fields(s):
    return {k: v for k, v in vars(s).items() if isinstance(v, np.ndarray)}


class Visibility(unittest.TestCase):
    def test_visibility_soft_at_outline(self):
        """A seed on a far wall that a near edge sweeps over dims over several frames, never blinks."""
        far = (10.0, -20, 20, -20, 20, 1, (0.5, 0.5, 0.5))
        near = (5.0, -20, 0.0, -20, 20, 2, (0.2, 0.2, 0.2))
        seeds = hand_seeds([[0.3, 10.0, 0.0]], [1.0, 0.0, 0.0], [42])
        ops = []
        for c in np.arange(0.0, 0.6, 0.01):
            cam = cam_at(-c, 0.0)
            st = solve(flat_ref(cam, [far, near]), seeds, LOOK, SIZE)
            ops.append(float(st.opacity[0]) if len(st.order) else 0.0)
        ops = np.array(ops)
        self.assertGreater(ops[0], 0.99)
        self.assertLess(ops[-1], 0.01)
        self.assertLessEqual(np.abs(np.diff(ops)).max(), 0.35)
        self.assertGreaterEqual(((ops > 0.05) & (ops < 0.95)).sum(), 3)


class Colour(unittest.TestCase):
    def test_colour_from_area(self):
        """On a 2 px checkerboard a 0.5 px move changes the stroke's colour by <= 2 %."""
        cam = cam_at(0.0, 0.0)  # 32 px a metre at 10 m: 2 px cells are 1/16 m
        check = lambda x, z: np.where(((np.floor(x * 16) + np.floor(z * 16)) % 2)[:, None] > 0, 1.0, 0.0) * np.ones(3)
        ref = flat_ref(cam, [(10.0, -20, 20, -20, 20, 1, check)])
        P = np.array([[0.01 + i / 64.0, 10.0, 0.013] for i in range(9)])
        st = solve(ref, hand_seeds(P, [1.0, 0.0, 0.0], np.arange(9) + 1), LOOK, SIZE)
        c = st.c1[np.argsort(st.order)]
        self.assertEqual(len(c), 9)
        self.assertLessEqual(np.abs(np.diff(c, axis=0)).max(), 0.02)


class Direction(unittest.TestCase):
    def test_direction_no_flip(self):
        """A tangent swinging through the view axis: the angle never jumps while the stroke is long; at the axis a dab."""
        cam = cam_at(0.0, 0.0)
        ref = flat_ref(cam, [])
        th = np.linspace(0.0, np.pi, 181)
        T = np.column_stack([np.cos(th), np.sin(th), np.full_like(th, 0.04)])
        P = np.repeat([[0.0, 10.0, 0.0]], len(th), 0)
        st = solve(ref, hand_seeds(P, T / np.linalg.norm(T, axis=1)[:, None], np.arange(len(th)) + 1, N=[0.0, 0.0, 1.0]),
                   LOOK, SIZE)
        i = np.argsort(st.order)
        ang, el = st.ang[i], st.length[i] / st.width[i] - 1.0
        self.assertTrue(((ang >= 0) & (ang < np.pi)).all())
        jump = np.abs((np.diff(ang) + np.pi / 2) % np.pi - np.pi / 2)
        long_ = np.minimum(el[:-1], el[1:]) > 0.2
        self.assertTrue(long_.any())
        self.assertLessEqual(jump[long_].max(), 0.1)
        self.assertLessEqual(el[90], 0.05)
        self.assertGreater(el[0], 1.0)


class Order(unittest.TestCase):
    def test_order_fixed(self):
        """Strokes come coarse to fine and by id inside a layer, so two views draw shared ids in the same order."""
        b, V = bank()
        wall = (10.0, -4, 4, -4, 4, 7, (0.5, 0.4, 0.3))
        runs = []
        for cam in (cam_at(0.0, 2.0), cam_at(0.8, 4.0, 0.3)):
            st = solve(flat_ref(cam, [wall]), b.place(V, cam, 8.0), LOOK, SIZE)
            key = np.lexsort((st.order, st.layer))
            np.testing.assert_array_equal(key, np.arange(len(key)))
            runs.append(st.order)
        common = np.intersect1d(*runs)
        self.assertGreater(len(common), 100)
        a, c = [r[np.isin(r, common)] for r in runs]
        np.testing.assert_array_equal(a, c)


class Pure(unittest.TestCase):
    def test_solve_pure(self):
        """Two calls give equal arrays; another call between them changes nothing; the inputs are not touched."""
        b, V = bank()
        cam = cam_at(0.3, 3.0)
        ref = flat_ref(cam, [(10.0, -4, 4, -4, 4, 7, (0.5, 0.4, 0.3))])
        seeds = b.place(V, cam, 8.0)
        before = {k: v.copy() for k, v in fields(seeds).items()}
        a = solve(ref, seeds, LOOK, SIZE)
        solve(flat_ref(cam_at(1.0, 1.0), [(10.0, -4, 4, -4, 4, 7, (0.1, 0.1, 0.1))]), b.place(V, cam_at(1.0, 1.0), 6.0), LOOK, SIZE)
        c = solve(ref, seeds, LOOK, SIZE)
        self.assertGreater(len(a.order), 100)
        for k, v in fields(a).items():
            np.testing.assert_array_equal(v, getattr(c, k), k)
        for k, v in before.items():
            np.testing.assert_array_equal(v, getattr(seeds, k), k)


class Lod(unittest.TestCase):
    def test_lod_near_limit(self):
        """A camera nearer than the finest octave, or inside a wall: strokes grow, stay finite and within max_px."""
        lo, hi = np.array([-4, 10.0, -4]), np.array([4, 10.3, 4])
        V = np.array([[x, y, z] for z in (0, 1) for y in (0, 1) for x in (0, 1)], float) * (hi - lo) + lo
        F = np.array([[0, 2, 1], [1, 2, 3], [4, 5, 6], [5, 7, 6], [0, 1, 4], [1, 5, 4],
                      [2, 6, 3], [3, 6, 7], [0, 4, 2], [2, 4, 6], [1, 3, 5], [3, 7, 5]])
        b = SeedBank(V, F, 0, 7, "course", 0.5, 5, octaves=6)
        for y, face in ((9.85, 10.0), (10.15, 10.3)):  # 0.15 m: the near clip is 0.1 m
            cam = cam_at(0.0, y)
            st = solve(flat_ref(cam, [(face, -4, 4, -4, 4, 7, (0.5, 0.4, 0.3))]), b.place(V, cam, 8.0), LOOK, SIZE)
            self.assertGreaterEqual(len(st.order), 4, y)  # few, grown strokes
            for k, v in fields(st).items():
                self.assertTrue(np.isfinite(v.astype(float)).all(), (y, k))
            self.assertLessEqual(st.width.max(), LOOK["max_px"], y)
            self.assertLessEqual(st.length.max(), LOOK["max_px"], y)
            self.assertGreater(st.width.max(), 0.9 * LOOK["max_px"], y)


class Marks(unittest.TestCase):
    def test_mark_strokes(self):
        """Marks are thin strokes along their edge, drawn after the fill; a lit-edge mark is lighter than the light
        side, a joint mark darker than the dark side; a mark far thinner than a pixel fades out."""
        cam = cam_at(0.0, 0.0)
        side = lambda x, z: np.where(x[:, None] < 0, 0.1, 0.5) * np.ones(3)
        ref = flat_ref(cam, [(10.0, -20, 20, -20, 20, 1, side)])
        s = hand_seeds([[0.0, 10.0, 0.0]] * 4 + [[1.0, 10.0, 0.5]], [0.0, 0.0, 1.0], [1, 2, 3, 4, 5])
        s.kind[:] = 1, 2, 1, 2, 0
        s.width_m[:] = 0.06, 0.06, 0.06, 0.001, 0.0  # 32 px a metre: 1.9 px, and 0.03 px
        s.length_m[:] = 2.0, 2.0, 0.25, 2.0, 0.0
        look = dict(LOOK, mark={"width": 2.0, "aspect": 2.5, "reach": 3.0, "light": 0.5, "dark": 0.5, "fade": [0.15, 0.6]})
        st = solve(ref, s, look, SIZE)
        np.testing.assert_array_equal(st.order, [5, 1, 2, 3])
        self.assertTrue((st.layer[1:] > st.layer[0]).all())
        self.assertTrue((st.width[1:] <= 3.0).all())
        np.testing.assert_allclose(st.ang[1:], np.pi / 2, atol=1e-3)
        self.assertGreater(st.length[1], 3 * st.width[1])
        self.assertLessEqual(st.length[3], 1.5 * 0.25 * 32 + 1e-3)  # no longer than its edge allows
        self.assertGreater(st.c1[1].min(), 0.55)
        self.assertLess(st.c1[2].max(), 0.08)
        np.testing.assert_allclose(st.opacity[1:], 1.0, atol=1e-3)


class Form(unittest.TestCase):
    def test_form_light(self):
        """The look's form light makes a face turned to it lighter than one turned away (no key: untouched); a
        stroke carries its seed's normal turned to the viewer."""
        cam = cam_at(0.0, 0.0)
        ref = flat_ref(cam, [(10.0, -20, 20, -20, 20, 1, (0.3, 0.3, 0.3))])
        s = hand_seeds([[0.0, 10.0, 0.0]], [1.0, 0.0, 0.0], [1], N=(0.0, 1.0, 0.0))
        plain = solve(ref, s, LOOK, SIZE)
        to = solve(ref, s, dict(LOOK, form={"light": [0.0, -1.0, 0.0], "gain": 0.5}), SIZE)
        away = solve(ref, s, dict(LOOK, form={"light": [0.0, 1.0, 0.0], "gain": 0.5}), SIZE)
        np.testing.assert_allclose(plain.c1[0], 0.3, atol=1e-3)
        self.assertGreater(to.c1[0].min(), 1.3 * plain.c1[0].max())
        self.assertLess(away.c1[0].max(), 0.7 * plain.c1[0].min())
        np.testing.assert_allclose(plain.n[0], [0.0, -1.0, 0.0], atol=1e-6)

    def test_glaze_air_over_form(self):
        """With "glaze" and an air pass the form light shapes the surface's share only and the air is added unshaped;
        without form the colour is the same as unglazed."""
        cam = cam_at(0.0, 0.0)
        ref = flat_ref(cam, [(10.0, -20, 20, -20, 20, 1, (0.5, 0.5, 0.5))])
        ref.air = np.full_like(ref.lit, 0.2)
        s = hand_seeds([[0.0, 10.0, 0.0]], [1.0, 0.0, 0.0], [1], N=(0.0, 1.0, 0.0))
        form = dict(LOOK, form={"light": [0.0, -1.0, 0.0], "gain": 0.5})
        np.testing.assert_allclose(solve(ref, s, dict(LOOK, glaze=1), SIZE).c1[0], 0.5, atol=1e-3)
        np.testing.assert_allclose(solve(ref, s, form, SIZE).c1[0], 0.5 * 1.5, atol=1e-3)
        np.testing.assert_allclose(solve(ref, s, dict(form, glaze=1), SIZE).c1[0], 0.3 * 1.5 + 0.2, atol=1e-3)


class Hug(unittest.TestCase):
    def test_hug_steady_as_it_hides(self):
        """A hugging stroke on a part beside a coplanar neighbour, which a near wall slides over, changes its size and
        place in small steps (T2043, rule 5): its own share is an area, never a ratio of point tests."""
        own = (10.0, -20, 0.45, -20, 20, 1, (0.5, 0.5, 0.5))
        nb = (10.0, 0.45, 20, -20, 20, 3, (0.5, 0.5, 0.5))
        near = (5.0, -20, 0.0, -20, 20, 2, (0.2, 0.2, 0.2))
        seeds = hand_seeds([[0.3, 10.0, 0.0]], [1.0, 0.0, 0.0], [42], px=12.0)
        w, x = [], []
        for c in np.arange(0.0, 0.6, 0.005):
            cam = cam_at(-c, 0.0)
            st = solve(flat_ref(cam, [own, nb, near]), seeds, dict(LOOK, hug=1.2), SIZE)
            p, _ = cam.project(seeds.P)
            w.append(float(st.width[0]) if len(st.order) else np.nan)
            x.append(float(st.x[0] - p[0, 0]) if len(st.order) else np.nan)
        dw, dx = np.nan_to_num(np.abs(np.diff(w))), np.nan_to_num(np.abs(np.diff(x)))  # steps while it is drawn
        self.assertGreater(w[0], 10.0)
        self.assertLessEqual(dw.max(), 2.0)
        self.assertLessEqual(dx.max(), 2.0)

    def test_mark_colour_steady_on_grain(self):
        """A lit-edge mark on a fine grain that moves with it keeps its colour within 7 % as the view slides 0.13 px
        a step (T2043, rule 7): each of its taps reads the area it stands for, never one pixel."""
        grain = lambda x, z: (np.where(x < 0, 0.1, 0.5 + 0.2 * np.sign(np.sin(2 * np.pi * x * 32 / 1.3)  # noqa: E731
                                                                         * np.sin(2 * np.pi * z * 32 / 1.3))))[:, None] * np.ones(3)
        s = hand_seeds([[0.0, 10.0, 0.0]], [0.0, 0.0, 1.0], [1])
        s.kind[:], s.width_m[:], s.length_m[:] = 1, 0.06, 2.0
        look = dict(LOOK, mark={"width": 2.0, "aspect": 2.5, "reach": 3.0, "light": 0.5, "dark": 0.5, "fade": [0.15, 0.6]})
        c = np.array([solve(flat_ref(cam_at(d, 0.0), [(10.0, -20, 20, -20, 20, 1, grain)]), s, look, SIZE).c1[0].mean()
                      for d in np.arange(0.0, 0.1, 0.004)])
        self.assertLessEqual((c.max() - c.min()) / c.mean(), 0.07)


def wall_ref(cam):
    """A near wall (10 m, x < 0, ident 1, lit 0.5) over a far one (12 m, ident 2, lit 0.1), its outline anti-aliased
    exactly in lit and in the ident's coverage (as EEVEE's AOV gives it); depth, normal, ident point-sampled."""
    r = flat_ref(cam, [(10.0, -20, 0.0, -20, 20, 1, (0.5,) * 3), (12.0, -20, 20, -20, 20, 2, (0.1,) * 3)])
    W, H = cam.size
    xe = W / 2 - 0.5 + cam.lens_mm / cam.sensor_mm * W * (0.0 - cam.pos[0]) / 10.0
    j = np.arange(W, dtype=float)
    a = np.clip(xe - (j - 0.5), 0.0, 1.0)  # each column's share on the near wall
    r.lit[:] = (0.1 + 0.4 * a)[None, :, None].astype(np.float32)
    near = r.ident == 1
    r.cover = np.where(near, a[None, :], 1.0 - a[None, :]).astype(np.float32)
    r.other = np.arange(H)[:, None] * W + np.where(r.cover < 1, np.clip(np.where(near, j + 1, j - 1), 0, W - 1), j).astype(np.int64)
    return r


class Steady(unittest.TestCase):
    def test_outline_steady_subpixel(self):
        """Fill strokes hugging a near wall's outline, the view sliding 0.3 px a frame: each stroke's width, length,
        place and colour are smooth in time (second difference under 0.1 px, the length 2.5 times that, the colour
        0.5 of 255), as the outline's coverage moves smoothly; the point-sampled ident and depth step (T2047)."""
        k = np.arange(30)
        P = np.column_stack([-0.05 - 0.4 * (k % 6) / 5, np.full(30, 10.0), -0.8 + 1.6 * (k // 6) / 4])
        seeds = hand_seeds(P, [0.0, 0.0, 1.0], k + 1, px=7.0)
        look = dict(LOOK, colour_levels=0.0, size=1.0, hug=1.2)
        runs = [solve(wall_ref(cam_at(0.3 * f * 10.0 / 320.0, 0.0)), seeds, look, SIZE) for f in range(9)]
        for st in runs:
            np.testing.assert_array_equal(st.order, runs[0].order)
        d2 = lambda a: np.abs(np.diff(np.stack(a).astype(float), 2, axis=0)).max()  # noqa: E731
        self.assertGreater(np.ptp(runs[0].width), 1.0)  # the hug does narrow the strokes at the outline
        for name, top in (("width", 0.1), ("length", 0.25), ("x", 0.1), ("y", 0.1)):
            self.assertLessEqual(d2([getattr(st, name) for st in runs]), top, name)
        self.assertLessEqual(d2([255 * st.c1.mean(1) for st in runs]), 0.5)


if __name__ == "__main__":
    unittest.main()
