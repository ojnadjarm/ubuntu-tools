"""Tests of film qa (Q1): the golden pair, a window painted alone, the wedge sheet, the strip's seconds."""
import contextlib
import io
import os
import re
import sys
import tempfile
import unittest

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
sys.path.insert(0, HERE)

from atelier import paint, qa  # noqa: E402
from test_cli import LOOK, Plane, ref_at  # noqa: E402

SIZE = (320, 180)
FAST = dict(LOOK, px_per_stroke=20.0)


def render(scene, x=None):
    """film qa's render for a test scene: jobs (frame, look, size, window) -> RGB pictures."""
    return lambda jobs: [paint.paint_frame(scene, ref_at(f, x), lk, size, w) for f, lk, size, w in jobs]


class Pair(unittest.TestCase):
    def test_pair_no_change(self):
        """The same engine painting the golden frames twice: every share is 0, no box is marked."""
        with tempfile.TemporaryDirectory() as d:
            gold, out = os.path.join(d, "golden"), os.path.join(d, "out")
            frames, loupes = [2, 5], {"edge": (5, (40, 30, 120, 68))}
            first = qa.pair(render(Plane()), gold, frames, loupes, FAST, FAST, SIZE, SIZE, out)
            self.assertTrue(os.path.exists(os.path.join(gold, "f_0002.png")))
            self.assertTrue(os.path.exists(os.path.join(gold, "loupe_edge.png")))
            rows = qa.pair(render(Plane()), gold, frames, loupes, FAST, FAST, SIZE, SIZE, out)
            self.assertEqual([r["name"] for r in rows], ["f_0002", "f_0005", "edge"])
            for r in first + rows:
                self.assertEqual(r["share"], 0.0, r["name"])
                self.assertIsNone(r["box"], r["name"])
            self.assertTrue(os.path.exists(os.path.join(out, "pair.jpg")))

    def test_pair_sees_change(self):
        """One look key changed (the broken colour): share > 0, and the marked box holds the change: the wall fills
        the left of the picture only, the box stays there and every changed pixel is in it."""
        scene = render(Plane(), x=6.0)  # the wall (x -4..4 at 7 m) covers about the left 70 px
        a = scene([(3, FAST, SIZE, None)])[0]
        b = scene([(3, dict(FAST, broken=0.0), SIZE, None)])[0]
        dmap, share = qa.diff(a, b)
        self.assertGreater(share, 0.0)
        x0, y0, x1, y1 = qa.box(dmap)
        self.assertLess(x1, 160)
        changed = dmap > qa.TOL
        inside = np.zeros_like(changed)
        inside[y0:y1 + 1, x0:x1 + 1] = True
        self.assertFalse((changed & ~inside).any())
        self.assertEqual(qa.diff(a, a)[1], 0.0)


class Keys(unittest.TestCase):
    def test_qa_block_not_in_keys(self):
        """shot.json's qa block chooses what to look at, not what is painted: editing it keeps every cache key."""
        from atelier import cli
        with tempfile.TemporaryDirectory() as d:
            shot, ref = os.path.join(d, "shot"), os.path.join(d, "ref")
            os.makedirs(shot)
            os.makedirs(ref)
            look = os.path.join(d, "look.json")
            for p, text in ((os.path.join(shot, "s.py"), "def scene(): pass\n"), (look, "{}")):
                with open(p, "w") as fh:
                    fh.write(text)
            keys = []
            for qa_block in ('', ', "qa": {"golden": [1]}', ', "qa": {"golden": [2]}'):
                with open(os.path.join(shot, "shot.json"), "w") as fh:
                    fh.write('{"scene": "s", "fps": 24%s}' % qa_block)
                keys.append((cli.ref_key(shot, 3, {}), cli.paint_key(shot, look, 3, SIZE, ref)))
            self.assertEqual(keys[0], keys[1])
            self.assertEqual(keys[0], keys[2])


class Crop(unittest.TestCase):
    def test_crop_equals_full(self):
        """A window painted alone equals that region of the full frame: 99 % of pixels within 1/255, the window's
        16 px border left out; it places fewer seeds than the full frame."""
        scene, look = Plane(), dict(LOOK, px_per_stroke=8.0)
        win = (150, 60, 120, 68)
        full = paint.paint_frame(scene, ref_at(4), look, SIZE)
        part = paint.paint_frame(scene, ref_at(4), look, SIZE, win)
        x, y, w, h = win
        self.assertEqual(part.shape, (h, w, 3))
        b = qa.BORDER
        d = np.abs(part.astype(int) - full[y:y + h, x:x + w].astype(int))[b:-b, b:-b].max(2)
        self.assertGreaterEqual((d <= 1).mean(), 0.99)
        cam = ref_at(4).camera
        lk = paint.scaled(look, SIZE[0])
        n_full = len(scene.seeds(0.0, cam, lk["px_per_stroke"]).id)
        from atelier.scene import Camera
        n_win = len(scene.seeds(0.0, Camera(cam.pos, cam.R, cam.lens_mm, cam.sensor_mm, cam.size, win), lk["px_per_stroke"]).id)
        self.assertLess(n_win, 0.8 * n_full)


class Wedge(unittest.TestCase):
    def test_wedge_grid(self):
        """Nine values of one look key: nine cells, each labelled with its value, on one 3 by 3 sheet."""
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "wedge.jpg")
            values = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
            cells, labels = qa.wedge(render(Plane()), 3, (40, 30, 120, 68), FAST, SIZE, "broken", values, path)
            self.assertEqual(len(cells), 9)
            self.assertEqual(labels, ["broken=%r" % v for v in values])
            img = cv2.imread(path)
            self.assertIsNotNone(img)
            ch, cw = cells[0].shape[:2]
            self.assertEqual(img.shape[1], 3 * cw)
            self.assertEqual(img.shape[0], 3 * (ch + qa.BAND))
            self.assertFalse(np.array_equal(cells[0], cells[-1]))
            look = qa.with_key(dict(LOOK), "mark.width", 9.0)
            self.assertEqual(look["mark"]["width"], 9.0)
            self.assertEqual(LOOK["mark"]["width"], 2.6)


class Strip(unittest.TestCase):
    def test_strip_prints_seconds(self):
        """The strip paints consecutive frames of one window, makes its flicker map and prints QA strip <s> s."""
        with tempfile.TemporaryDirectory() as d:
            win, frames = (40, 30, 120, 68), list(range(6))
            flow = [cv2.cvtColor(render(Plane())([(f, FAST, SIZE, win)])[0], cv2.COLOR_RGB2BGR) for f in frames]
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                pics, fmap = qa.strip(render(Plane()), frames, win, FAST, SIZE, flow, d)
            self.assertRegex(buf.getvalue(), re.compile(r"^QA strip \d+\.\d s$", re.M))
            self.assertEqual(len(pics), 6)
            self.assertEqual(fmap.shape, (68, 120, 3))
            self.assertTrue(os.path.exists(os.path.join(d, "strip.jpg")))


if __name__ == "__main__":
    unittest.main()
