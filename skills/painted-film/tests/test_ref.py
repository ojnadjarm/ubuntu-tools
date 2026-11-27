"""Tests of the reference pass: Blender renders two small fixture scenes once, the tests read them back."""
import os
import shutil
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))
sys.path.insert(0, os.path.join(HERE, "fixtures"))

from atelier import cli, refio  # noqa: E402
from atelier.scene import ident_code  # noqa: E402
import scenes  # noqa: E402

PASSES = ("lit", "albedo", "depth", "normal", "ident")


def shot(root, name, cls, samples=24):
    """A shot folder whose scene module returns the fixture scene `cls`."""
    d = os.path.join(root, name)
    os.makedirs(d)
    with open(os.path.join(d, "shot.json"), "w") as fh:
        fh.write('{"scene": "fixture", "fps": 24, "ref": {"samples": %d}}' % samples)
    with open(os.path.join(d, "fixture.py"), "w") as fh:
        fh.write("import sys\nsys.path.insert(0, %r)\nimport scenes\n\n\ndef scene():\n    return scenes.%s()\n" % (HERE + "/fixtures", cls))
    return d


@unittest.skipUnless(shutil.which(os.environ.get("FILM_BLENDER", "blender")), "no blender")
class Ref(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        t = cls.tmp.name
        cls.dots_out, cls.room_out = os.path.join(t, "dots"), os.path.join(t, "room")
        assert cli.main(["ref", shot(t, "s_dots", "Dots"), "--out", cls.dots_out, "--frames", "0"]) == 0
        assert cli.main(["ref", shot(t, "s_room", "Room"), "--out", cls.room_out, "--frames", "0", "--seed-pair"]) == 0
        cls.dots = refio.load(os.path.join(cls.dots_out, "f_0000"))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_ref_passes_present(self):
        for p in PASSES:
            self.assertTrue(os.path.getsize(os.path.join(self.dots_out, "f_0000.%s.exr" % p)) > 0, p)
        r, (W, H) = self.dots, scenes.Dots.size
        self.assertEqual(r.lit.shape, (H, W, 3))
        self.assertEqual(r.albedo.shape, (H, W, 3))
        self.assertEqual(r.normal.shape, (H, W, 3))
        self.assertEqual(r.depth.shape, (H, W))
        self.assertEqual(r.ident.shape, (H, W))
        self.assertEqual(r.ident.dtype, np.int32)
        self.assertEqual(r.camera.size, (W, H))
        wall = r.ident == 5
        self.assertGreater(wall.sum(), 1000)
        np.testing.assert_allclose(r.depth[wall], scenes.Dots.WALL, atol=1e-3)  # metres along the view axis
        np.testing.assert_allclose(r.albedo[wall].mean(0), [0.3, 0.3, 0.3], atol=0.01)

    def test_project_matches_blender(self):
        xy, _ = self.dots.camera.project(scenes.Dots.POINTS)
        for k, p in zip(scenes.Dots.IDENTS, xy):
            ys, xs = np.nonzero(self.dots.ident == k)
            self.assertGreater(len(xs), 30, k)
            np.testing.assert_allclose([xs.mean(), ys.mean()], p, atol=0.5, err_msg=str(k))

    def test_ref_background(self):
        r = self.dots
        bg = r.ident == 0
        self.assertGreater(bg.mean(), 0.3)
        self.assertTrue(np.isinf(r.depth[bg]).all())
        self.assertTrue(np.isfinite(r.depth[~bg]).all())
        self.assertTrue((r.normal[bg] == 0).all())
        for a in (r.lit, r.albedo, r.normal):
            self.assertTrue(np.isfinite(a).all())
        np.testing.assert_allclose(r.lit[bg].mean(0), scenes.Dots.world["color"], atol=0.01)  # the world colour

    def test_seed_pair(self):
        a = refio.load(os.path.join(self.room_out, "f_0000"))
        b = refio.load(os.path.join(self.room_out, "seed2", "f_0000"))
        self.assertFalse(np.array_equal(a.lit, b.lit))  # the moved pattern did render
        self.assertLessEqual(refio.seed_diff(a, b, sigma=2.0), 0.010)


class Decode(unittest.TestCase):
    def test_ident_follows_depth_at_blended_edges(self):
        """An anti-aliased edge band takes the ident of the side its (unfiltered) depth belongs to."""
        H, W = 6, 12
        ident = np.where(np.arange(W)[None, :] < 6, 7, 900).repeat(H, 0)
        depth = np.where(ident == 7, 5.0, 9.0)
        code = ident_code(ident.ravel()).reshape(H, W, 4)
        code[:, 5] = 0.6 * code[:, 5] + 0.4 * code[:, 6]
        code[:, 6] = 0.3 * code[:, 5] + 0.7 * code[:, 6]
        got = refio.decode_ident(code, depth)
        np.testing.assert_array_equal(got, ident)


if __name__ == "__main__":
    unittest.main()
