"""Tests of the oil medium: depth-tested strokes, purity, the oil-paint API it imports, the canvas fixed to the frame."""
import inspect
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
sys.path.insert(0, HERE)

from atelier.medium import oil  # noqa: E402
from atelier.medium.oil import OilMedium, op  # noqa: E402
from atelier.paint import Strokes  # noqa: E402
from test_anchor import cam_at  # noqa: E402
from test_paint import flat_ref, wall_ref  # noqa: E402

SIZE = (320, 180)
with open(os.path.join(HERE, "..", "looks", "oil-tight.json")) as fh:
    LOOK = json.load(fh)
FLAT = dict(LOOK, canvas=dict(LOOK["canvas"], relief=0.0))  # no raking light: a pixel changes only where paint lands
FAR = (10.0, -20, 20, -20, 20, 1, (0.5, 0.5, 0.5))
NEAR = (5.0, -20, 0.0, -20, 20, 2, (0.2, 0.2, 0.2))  # the left half of the picture


def strokes(x, y, z, ang=0.0, length=80.0, width=30.0, colour=(0.8, 0.1, 0.1), ids=None):
    """Hand-made strokes on planes facing the camera."""
    x = np.atleast_1d(np.asarray(x, np.float32))
    k = len(x)
    f = lambda v: np.broadcast_to(np.asarray(v, np.float32), (k,)).copy()
    c = np.broadcast_to(np.asarray(colour, np.float32), (k, 3)).copy()
    ids = np.arange(1, k + 1, dtype=np.uint64) if ids is None else np.asarray(ids, np.uint64)
    return Strokes(f(x), f(y), f(ang), f(length), f(width), (ids % 251).astype(np.uint8), c, c.copy(), f(1.0), f(z),
                   np.zeros(k, np.uint8), ids, np.zeros((k, 2), np.float32))


class Depth(unittest.TestCase):
    def test_depth_test(self):
        """A far stroke across a near thing's outline paints the far side and stops within edge_spill_px of the
        outline; a near stroke across the same outline paints both sides."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR, NEAR])
        near = ref.ident == 2
        self.assertTrue(near[:, :150].all() and not near[:, 170:].any())
        m = OilMedium()
        empty = m.composite(strokes([], [], []), ref, FLAT, SIZE).astype(int)
        far = np.abs(m.composite(strokes(160.0, 90.0, 10.0), ref, FLAT, SIZE).astype(int) - empty).max(2) > 0
        spill = FLAT["edge_spill_px"]
        inside = cv2.distanceTransform((near * 255).astype(np.uint8), cv2.DIST_L2, 5) > spill + 1.0
        self.assertFalse(far[inside].any(), "far paint %d px deep in the near thing" % far[inside].sum())
        self.assertGreater(far[80:100, 166:180].mean(), 0.8)  # bristle sprites have gaps by design
        self.assertTrue(far[80:100, 160 - spill:160].any())  # the spill itself: outlines break up like painted edges
        nearp = np.abs(m.composite(strokes(160.0, 90.0, 5.0), ref, FLAT, SIZE).astype(int) - empty).max(2) > 0
        self.assertGreater(min(nearp[80:100, 135:155].mean(), nearp[80:100, 166:180].mean()), 0.8)


class Face(unittest.TestCase):
    def test_face_cut(self):
        """With the look's "face" a stroke paints only where the reference's normal agrees with its own: it stops at
        a crease within 2 px; a stroke with no normal, or a look with no "face", paints across."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR])
        ref.normal[:, :160] = (1.0, 0.0, 0.0)
        m = OilMedium()
        look = dict(FLAT, face=[0.5, 0.8])
        empty = m.composite(strokes([], [], []), ref, look, SIZE).astype(int)
        st = strokes(160.0, 90.0, 10.0)
        on = lambda s, lk: np.abs(m.composite(s, ref, lk, SIZE).astype(int) - empty).max(2) > 0
        across = on(st, look)
        self.assertGreater(min(across[80:100, 135:155].mean(), across[80:100, 166:180].mean()), 0.8)
        st.n = np.array([[0.0, -1.0, 0.0]], np.float32)
        cut = on(st, look)
        self.assertFalse(cut[:, :158].any())
        self.assertGreater(cut[80:100, 162:180].mean(), 0.8)
        free = on(st, {k: v for k, v in look.items() if k != "face"})
        self.assertGreater(free[80:100, 135:155].mean(), 0.8)

    def test_air_frees_far_strokes(self):
        """With the look's "air" a stroke past its far distance paints across a crease (share "face" 0 keeps the cut);
        a stroke nearer than its near distance is cut as before."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR])
        ref.normal[:, :160] = (1.0, 0.0, 0.0)
        m = OilMedium()
        look = dict(FLAT, face=[0.5, 0.8], air={"z": [6.0, 9.0], "face": 0.0, "body": 0.2, "broken": 0.2})
        empty = m.composite(strokes([], [], []), ref, look, SIZE).astype(int)
        on = lambda s: np.abs(m.composite(s, ref, look, SIZE).astype(int) - empty).max(2) > 0
        far, near = strokes(160.0, 90.0, 10.0), strokes(160.0, 90.0, 5.0)
        far.n = near.n = np.array([[0.0, -1.0, 0.0]], np.float32)
        self.assertGreater(on(far)[80:100, 135:155].mean(), 0.8)
        self.assertFalse(on(near)[:, :158].any())

    def test_thin_face_is_filled(self):
        """A face thinner than the look's "face_min_px" is painted with the face round it; without the key it stays bare."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR])
        ref.normal[:, 170:172] = (1.0, 0.0, 0.0)
        m = OilMedium()
        look = dict(FLAT, face=[0.5, 0.8])
        empty = m.composite(strokes([], [], []), ref, look, SIZE).astype(int)
        st = strokes(170.0, 90.0, 10.0)
        st.n = np.array([[0.0, -1.0, 0.0]], np.float32)
        on = lambda lk: np.abs(m.composite(st, ref, lk, SIZE).astype(int) - empty).max(2) > 0
        self.assertFalse(on(look)[:, 170:172].any())
        self.assertGreater(on(dict(look, face_min_px=2))[85:95, 170:172].mean(), 0.8)


class Pure(unittest.TestCase):
    def test_composite_pure(self):
        """Two calls give equal pictures; a call between them on another frame changes nothing; inputs untouched."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR, NEAR])
        rng = np.random.default_rng(3)
        st = strokes(rng.uniform(0, 320, 300), rng.uniform(0, 180, 300), rng.uniform(4, 12, 300),
                     ang=rng.uniform(0, np.pi, 300), length=rng.uniform(4, 40, 300), width=rng.uniform(2, 12, 300),
                     ids=rng.permutation(1000)[:300] + 1)
        st.c1[:] = rng.uniform(0, 1, (300, 3))
        before = {k: v.copy() for k, v in vars(st).items()}
        m = OilMedium()
        a = m.composite(st, ref, LOOK, SIZE)
        m.composite(strokes([50.0, 200.0], [40.0, 120.0], [6.0, 9.0]), flat_ref(cam_at(1.0, 2.0), [FAR]), LOOK, SIZE)
        OilMedium().composite(st, ref, LOOK, (160, 90))
        b = m.composite(st, ref, LOOK, SIZE)
        self.assertEqual(a.dtype, np.uint8)
        self.assertEqual(a.shape, (SIZE[1], SIZE[0], 3))
        np.testing.assert_array_equal(a, b)
        np.testing.assert_array_equal(a, OilMedium().composite(st, ref, LOOK, SIZE))
        for k, v in before.items():
            np.testing.assert_array_equal(v, getattr(st, k), k)


class Api(unittest.TestCase):
    def test_oilpaint_api(self):
        """The four names the medium takes from oil-paint exist with the arguments it passes."""
        want = {op.BrushBank: ("seed", "per", "length"), op.Linen: ("w", "h", "seed", "period", "ground"),
                op.Frame.finish: ("light", "relief", "gloss", "shine", "exposure", "vignette"),
                op.broken: ("col", "jit", "amount", "shadow_tint", "light_tint", "tints")}
        for fn, args in want.items():
            have = inspect.signature(fn).parameters
            for a in args:
                self.assertIn(a, have, (fn.__qualname__, a))
        self.assertTrue(hasattr(op.BrushBank(seed=1, per=1, length=64), "atlas"))


class Canvas(unittest.TestCase):
    def test_canvas_fixed(self):
        """The linen stays put: where no paint lands, two frames of different views and strokes are equal."""
        m = OilMedium()
        a_ref, b_ref = flat_ref(cam_at(0.0, 0.0), [FAR, NEAR]), flat_ref(cam_at(2.0, 3.0), [FAR])
        np.testing.assert_array_equal(m.composite(strokes([], [], []), a_ref, LOOK, SIZE),
                                      m.composite(strokes([], [], []), b_ref, LOOK, SIZE))
        a = m.composite(strokes(60.0, 50.0, 4.0, length=30.0, width=10.0), a_ref, LOOK, SIZE)
        b = m.composite(strokes(250.0, 130.0, 4.0, length=30.0, width=10.0), b_ref, LOOK, SIZE)
        away = np.ones(SIZE[::-1], bool)
        away[25:76, 30:91] = away[105:156, 220:281] = False
        self.assertFalse((a == b).all())
        np.testing.assert_array_equal(a[away], b[away])
        self.assertGreater(a[away].std(), 0.5)  # the weave is there, not a flat fill


class Thin(unittest.TestCase):
    def test_thin_stroke_steady(self):
        """A stroke under 1.5 px lays the same ink wherever it sits on the pixel grid, and its ink falls smoothly with
        its width, never cut (T2043, rules 5 and 9)."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR])
        m = OilMedium()
        empty = m.composite(strokes([], [], []), ref, FLAT, SIZE).astype(float)
        ink = lambda y, w: np.abs(m.composite(strokes(160.0, y, 10.0, length=40.0, width=w, colour=(0.9, 0.9, 0.9)),  # noqa: E731
                                              ref, FLAT, SIZE).astype(float) - empty).sum()
        by_place = np.array([ink(90.0 + d, 1.0) for d in np.arange(0.0, 1.0, 0.125)])
        by_width = np.array([ink(90.25, w) for w in np.arange(0.3, 1.6, 0.1)])
        self.assertLessEqual(by_place.std() / by_place.mean(), 0.1)
        self.assertGreater(by_width[0], 0.0)
        self.assertLessEqual(np.abs(np.diff(by_width / by_width.max())).max(), 0.2)


class Level(unittest.TestCase):
    def test_sprite_level_ramp(self):
        """A stroke growing 1 % a frame changes the picture by about as much every frame: its sprite's level is a
        ramp, never a jump (T2043, rule 5)."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR])
        m = OilMedium()
        pics = [m.composite(strokes(160.0, 90.0, 10.0, length=L, width=L / 2.3, colour=(0.9, 0.7, 0.4)), ref, FLAT,
                            SIZE).astype(float) for L in 30.0 * 1.01 ** np.arange(80)]
        d = np.array([np.abs(b - a).mean() for a, b in zip(pics, pics[1:])])
        self.assertLessEqual(d.max(), 3.0 * np.median(d))



class Steady(unittest.TestCase):
    def test_cuts_follow_outline(self):
        """A near wall's outline slides 0.3 px a frame; a stroke on the near wall hanging over it (overhang cut) and
        one on the far wall behind it (spill cut) ride their walls: the ink each lays changes smoothly (second
        difference under 0.5 % of it), the cuts following the outline's coverage, not its pixel steps (T2047)."""
        m = OilMedium()
        for z, dx in ((10.0, -10.0), (12.0, 4.0)):
            ink = []
            for f in range(12):
                ref = wall_ref(cam_at(0.3 * f * 10.0 / 320.0, 0.0))
                st = strokes(159.5 - 0.3 * f * 10.0 / z + dx, 90.0, z, colour=(0.9, 0.9, 0.9))
                st.n[:] = (0.0, -1.0, 0.0)  # cut to its own face
                empty = m.composite(strokes([], [], []), ref, FLAT, SIZE).astype(float)
                ink.append(np.abs(m.composite(st, ref, FLAT, SIZE).astype(float) - empty).sum())
            self.assertLessEqual(np.abs(np.diff(ink, 2)).max(), 0.005 * np.mean(ink), z)


class BankCache(unittest.TestCase):
    def test_brush_bank_read_back(self):
        """With a cache folder the brush bank is made once: a new process (here: the in-memory banks dropped) reads it
        back without making a brush, and paints the same picture byte for byte."""
        ref = flat_ref(cam_at(0.0, 0.0), [FAR, NEAR])
        st = strokes([60.0, 160.0, 250.0], [50.0, 90.0, 130.0], [6.0, 10.0, 10.0], ang=0.4)
        kept = dict(oil._BUILT)
        try:
            with tempfile.TemporaryDirectory() as d:
                oil._BUILT.clear()
                a = OilMedium(d).composite(st, ref, LOOK, SIZE)
                oil._BUILT.clear()
                with mock.patch.object(op.BrushBank, "_make", side_effect=AssertionError("brush made again")):
                    b = OilMedium(d).composite(st, ref, LOOK, SIZE)
                np.testing.assert_array_equal(a, b)
                np.testing.assert_array_equal(a, OilMedium().composite(st, ref, LOOK, SIZE))
        finally:
            oil._BUILT.clear()
            oil._BUILT.update(kept)


if __name__ == "__main__":
    unittest.main()
