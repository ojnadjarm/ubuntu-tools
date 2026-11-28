"""Tests of the film stages (A6): cache keys, frames in any order, the draft size, single-thread workers, the boil."""
import ctypes
import dataclasses
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
sys.path.insert(0, HERE)

from atelier import cli, paint  # noqa: E402
from atelier.four import Scene4D  # noqa: E402
from atelier.four import slicer as S  # noqa: E402
from test_anchor import bank, cam_at, wall  # noqa: E402
from test_paint import flat_ref  # noqa: E402

SIZE = (320, 180)
with open(os.path.join(HERE, "..", "looks", "oil-tight.json")) as fh:
    LOOK = json.load(fh)
QUICK = dict(LOOK, px_per_stroke=40.0)  # few strokes: these tests check the stages, not the paint


class Plane:
    """A Scene with one wall of seeds (test_anchor's)."""
    fps = 24

    def __init__(self):
        self.b, self.V = bank()

    def seeds(self, t, cam, px_per_stroke):
        return self.b.place(self.V, cam, px_per_stroke)


def ref_at(f, x=None):
    """The reference of frame f: the camera slides along the wall, or stands at x."""
    r = flat_ref(cam_at(0.3 + 0.05 * f if x is None else x, 3.0), [(10.0, -4, 4, -4, 4, 7, (0.5, 0.4, 0.3))])
    return dataclasses.replace(r, meta={"t": f / 24.0})


def write(path, text):
    with open(path, "w") as fh:
        fh.write(text)


def _probe(_):
    """In a worker: the BLAS library's own thread count and OpenCV's."""
    import cv2
    lib = next(ln.split()[-1] for ln in open("/proc/self/maps") if "openblas" in ln)
    so = ctypes.CDLL(lib)
    get = next(getattr(so, n) for n in ("scipy_openblas_get_num_threads64_", "openblas_get_num_threads64_",
                                        "openblas_get_num_threads") if hasattr(so, n))
    return get(), cv2.getNumThreads()


class Cache(unittest.TestCase):
    def test_cache_keys(self):
        """An unchanged frame is skipped; a changed shot, look, engine or reference file repaints it; the command
        line and the metrics are not the paint: an edit to them repaints nothing."""
        with tempfile.TemporaryDirectory() as d:
            shot, eng, out, ref = (os.path.join(d, n) for n in ("shot", "engine", "out", "ref"))
            for p in (shot, eng, out, ref):
                os.makedirs(p)
            write(os.path.join(shot, "shot.json"), '{"scene": "s", "fps": 24}')
            write(os.path.join(shot, "s.py"), "def scene(): pass\n")
            look = os.path.join(d, "look.json")
            write(look, '{"name": "x"}')
            write(os.path.join(eng, "paint.py"), "A = 1\n")
            write(os.path.join(eng, "cli.py"), "B = 1\n")
            os.makedirs(os.path.join(eng, "metrics"))
            write(os.path.join(eng, "metrics", "flick.py"), "C = 1\n")
            frames = [3, 4, 5]
            for f in frames:
                write(os.path.join(ref, "f_%04d.key" % f), "r%d" % f)
            keys = lambda: {f: cli.paint_key(shot, look, f, SIZE, ref, eng) for f in frames}  # noqa: E731

            def make():
                todo = cli.stale(out, keys())
                for f in todo:
                    write(os.path.join(out, "f_%04d.png" % f), "png")
                    cli.done(out, f, keys()[f])
                return todo

            self.assertEqual(make(), frames)
            self.assertEqual(make(), [])
            for path, text in ((os.path.join(shot, "s.py"), "def scene(): return 1\n"),
                               (os.path.join(shot, "shot.json"), '{"scene": "s", "fps": 25}'),
                               (look, '{"name": "y"}'), (os.path.join(eng, "paint.py"), "A = 2\n")):
                write(path, text)
                self.assertEqual(make(), frames, path)
                self.assertEqual(make(), [])
            for path, text in ((os.path.join(eng, "cli.py"), "B = 2\n"), (os.path.join(eng, "metrics", "flick.py"), "C = 2\n")):
                write(path, text)
                self.assertEqual(make(), [], path)
            self.assertNotEqual(cli.paint_key(shot, look, 3, (960, 540), ref, eng), keys()[3])
            write(os.path.join(ref, "f_0004.key"), "new reference")
            self.assertEqual(make(), [4])
            os.remove(os.path.join(out, "f_0005.png"))
            self.assertEqual(make(), [5])


class Order(unittest.TestCase):
    def test_any_order(self):
        """Frames made in reverse equal frames made in order, byte for byte, with the boil on."""
        frames, scene = [0, 1, 2, 3, 4], Plane()
        fwd = {f: paint.paint_frame(scene, ref_at(f), QUICK, SIZE) for f in frames}
        back = {f: paint.paint_frame(scene, ref_at(f), QUICK, SIZE) for f in reversed(frames)}
        self.assertGreater(len(np.unique(fwd[0].reshape(-1, 3), axis=0)), 50)
        for f in frames:
            np.testing.assert_array_equal(fwd[f], back[f], "frame %d" % f)


class Draft(unittest.TestCase):
    def test_draft_flag(self):
        """--draft paints 960x540 whatever the shot's size, with the look's pixel sizes halved."""
        cfg = {"size": [1920, 1080]}
        self.assertEqual(cli.frame_size(cfg, False), (1920, 1080))
        self.assertEqual(cli.frame_size(cfg, True), (960, 540))
        self.assertTrue(cli.parser().parse_args(["paint", "SHOT", "--draft"]).draft)
        lk = paint.scaled(LOOK, 960)
        self.assertEqual(lk["px_per_stroke"], LOOK["px_per_stroke"] / 2)
        self.assertEqual(lk["mark"]["width"], LOOK["mark"]["width"] / 2)
        self.assertEqual(lk["boil"]["amount"], LOOK["boil"]["amount"] / 2)
        img = paint.paint_frame(Plane(), ref_at(0), dict(QUICK, px_per_stroke=80.0), (960, 540))
        self.assertEqual(img.shape, (540, 960, 3))


class Workers(unittest.TestCase):
    def test_workers_single_thread(self):
        """Each worker runs with one BLAS and one OpenCV thread; the pool size comes from the memory available,
        at most 4, fewer under 12 GB."""
        self.assertEqual(cli.pool_size(8, 30000), 4)
        self.assertEqual(cli.pool_size(2, 30000), 2)
        self.assertEqual(cli.pool_size(8, 12000), 4)
        self.assertLess(cli.pool_size(8, 11999), 4)
        self.assertEqual(cli.pool_size(8, 500), 1)
        self.assertGreaterEqual(cli.pool_size(8), 1)
        old = os.environ.get("OPENBLAS_NUM_THREADS")
        os.environ["OPENBLAS_NUM_THREADS"] = "8"
        try:
            with cli.pool(2) as p:
                got = p.map(_probe, range(2))
        finally:
            if old is None:
                os.environ.pop("OPENBLAS_NUM_THREADS", None)
            else:
                os.environ["OPENBLAS_NUM_THREADS"] = old
        self.assertEqual(got, [(1, 1), (1, 1)])


class Boil(unittest.TestCase):
    def test_boil_alive_and_pure(self):
        """The boil is on in the look; with a still camera it changes the picture at every frame (a drift, never a
        hold then a jump); off, the picture holds; it moves fill strokes only."""
        b = LOOK["boil"]
        self.assertGreater(b["amount"], 0)
        scene = Plane()
        frame = lambda f, lk: paint.paint_frame(scene, ref_at(f, x=0.3), lk, SIZE)  # noqa: E731
        a0, a1, a2 = frame(0, QUICK), frame(1, QUICK), frame(2, QUICK)
        self.assertFalse(np.array_equal(a0, a1))
        self.assertFalse(np.array_equal(a1, a2))
        off = dict(QUICK, boil=dict(b, amount=0.0))
        np.testing.assert_array_equal(frame(0, off), frame(2, off))

    def test_boil_smooth_in_time(self):
        """Rule 5: each fill stroke drifts as a smooth function of t, within the amount: no step at any t, a
        frame-to-frame move far under the amount, a second difference (what the flicker measure sees) near 0."""
        a = 0.5
        look = {"boil": dict(LOOK["boil"], amount=a)}
        n = 400
        st = paint.Strokes(*(np.zeros(n, np.float32),) * 5, np.zeros(n, np.uint8), np.zeros((n, 3), np.float32),
                           np.zeros((n, 3), np.float32), np.ones(n, np.float32), np.ones(n, np.float32),
                           np.where(np.arange(n) < n - 50, 0, paint.MARK_LAYER).astype(np.uint8),
                           np.arange(n, dtype=np.uint64) * np.uint64(7919), np.zeros((n, 2), np.float32))
        st = dataclasses.replace(st, length=np.full(n, 20.0, np.float32))
        ts = np.arange(0, 4 * 24 + 1) / 24.0
        x = np.array([paint.boil(st, look, t).x for t in ts])
        y = np.array([paint.boil(st, look, t).y for t in ts])
        ang = np.array([paint.boil(st, look, t).ang for t in ts])
        fill = np.arange(n) < n - 50
        np.testing.assert_array_equal(x[:, ~fill], 0)
        self.assertLessEqual(np.abs(x).max(), a + 1e-6)
        self.assertGreater(np.abs(x[:, fill]).max(), 0.5 * a)  # alive: the drift spans its amount
        step = np.hypot(np.diff(x, axis=0), np.diff(y, axis=0))[:, fill]
        self.assertGreater(step.min(), 0.0)  # it moves at every frame
        self.assertLess(step.max(), 0.25 * a)  # never a jump
        d2 = np.abs(x[2:] - 2 * x[1:-1] + x[:-2])[:, fill]
        self.assertLess(d2.max(), 0.02 * a)
        tip = 10.0 * np.abs((np.diff(ang, axis=0) + np.pi / 2) % np.pi - np.pi / 2)[:, fill]
        self.assertLess(tip.max(), 0.25 * a)
        eps = np.array([paint.boil(st, look, t).x for t in (1.0, 1.0 + 1e-4)])
        self.assertLess(np.abs(eps[1] - eps[0]).max(), 1e-3)  # continuous at any t, not only on frames


class Speed(unittest.TestCase):
    def test_frame_unchanged_by_speedups(self):
        """The speed-ups change no picture: a 4D wall far wider than the view and a cube turning through w, painted
        from cached banks with off-picture strokes culled, equal the plain build within 1/255 on 99.9 % of pixels."""
        V, F = wall(half=20.0)
        Vc, Fc = S.box([-0.6, -0.6, -0.6], [0.6, 0.6, 0.6])
        turn = lambda w: Vc @ np.array([[np.cos(w), -np.sin(w), 0], [np.sin(w), np.cos(w), 0], [0, 0, 1]]).T + [0.4, 7.0, 0.2]  # noqa: E731
        bodies = {"stone": S.loft([V, V], [-5.0, 5.0], F), "iron": S.loft([turn(w) for w in (-1, 0, 1)], [-1.0, 0.0, 1.0], Fc)}
        cam = cam_at(0.5, 3.0)
        ref = dataclasses.replace(flat_ref(cam, [(10.0, -20, 20, -20, 20, 1, lambda x, z: np.stack([0.3 + 0.01 * x, 0.4 + 0.01 * z, 0.5 + 0 * x], -1))]),
                                  meta={"t": 0.5})

        def scene(cache):
            sc = Scene4D(bodies, lambda t: S.Slice(0.3 * t), None)
            sc.rho0, sc.log, sc.cache_dir = 4.0, False, cache
            return sc

        drawn, solve = [], paint.solve
        with mock.patch.object(paint, "solve", lambda *a: drawn.append(solve(*a)) or drawn[-1]):
            with mock.patch.object(paint, "CULL_PAD", np.inf):
                plain = paint.paint_frame(scene(None), ref, QUICK, SIZE).astype(int)
            with tempfile.TemporaryDirectory() as d:
                scene(d).seeds(0.0, cam, 1.0)
                fast = paint.paint_frame(scene(d), ref, QUICK, SIZE).astype(int)
        self.assertLess(len(drawn[1].order), 0.95 * len(drawn[0].order))  # the cull bites
        self.assertGreater(len(np.unique(plain.reshape(-1, 3), axis=0)), 50)
        self.assertGreaterEqual((np.abs(plain - fast).max(2) <= 1).mean(), 0.999)


if __name__ == "__main__":
    unittest.main()
