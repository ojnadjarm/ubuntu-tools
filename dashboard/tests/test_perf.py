"""tools/perf.py times real GET routes, never a redirect, and covers the costly endpoints."""
import importlib.util, inspect, os, unittest
import server
from dash import routes

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("perf", os.path.join(HERE, "tools", "perf.py"))
perf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(perf)


class Perf(unittest.TestCase):
    def test_paths_are_routes_that_do_not_redirect(self):
        for path in perf.PATHS:
            fn = routes.find("GET", path.split("?")[0])
            self.assertIsNotNone(fn, path)
            self.assertNotIn("h.redirect(", inspect.getsource(fn), path)

    def test_costly_endpoints_are_timed(self):
        for path in ("/api/agents", "/classic"):
            self.assertIn(path, perf.PATHS)
