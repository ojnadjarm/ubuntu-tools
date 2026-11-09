"""CLAUDE.md layout matches the tree: every service module listed, perf.py --cold described as it runs."""
import os, re, unittest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class ClaudeMd(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(HERE, "CLAUDE.md")) as f:
            self.lines = f.read().splitlines()

    def line(self, prefix):
        return next(l for l in self.lines if l.startswith(prefix))

    def test_every_service_module_is_listed(self):
        listed = set(re.findall(r"\w+", self.line("dash/services/").split(None, 1)[1]))
        mods = {f[:-3] for f in os.listdir(os.path.join(HERE, "dash", "services")) if f.endswith(".py") and f != "__init__.py"}
        self.assertEqual(mods - listed, set())

    def test_perf_cold_is_not_a_wait(self):
        perf = self.line("tools/perf.py")
        self.assertNotIn("waits", perf)
        self.assertIn("without the cache", perf)
