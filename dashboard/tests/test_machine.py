"""The machine map page: served through the confined static handler, no secrets, no scratch paths."""
import os, re, sys, unittest
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server

PAGE = os.path.join(HERE, "static", "machine.html")


class Machine(unittest.TestCase):
    def setUp(self):
        self.html = open(PAGE, encoding="utf-8").read()

    def test_no_secrets_or_scratch_paths(self):
        for bad in ("/tmp/", "POSTGRES_PASSWORD", "Admin1234", "ntfy.sh/", "secrets/", "BEGIN OPENSSH"):
            self.assertNotIn(bad, self.html, bad)
        self.assertIsNone(re.search(r"m@0dl3\w+", self.html))

    def test_sections_and_numbering(self):
        for sid in ("map", "moodle", "eye", "fleet", "phone", "plumbing", "verdicts", "drift", "cheat"):
            self.assertIn('id="%s"' % sid, self.html)
        nums = [int(n) for n in re.findall(r"<em>(\d\d)</em>", self.html)]
        self.assertEqual(nums, list(range(1, len(nums) + 1)))
        self.assertIn("%d things" % len(nums), self.html)

    def test_static_route_is_confined(self):
        rel = "static/machine.html"
        full = os.path.realpath(os.path.join(HERE, rel))
        base = os.path.join(HERE, rel.split("/")[0])
        self.assertTrue(full.startswith(base + os.sep) and os.path.isfile(full))
        self.assertIn(".html", server.MIME)

    def test_panel_links_to_it(self):
        idx = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
        self.assertEqual(idx.count('data-go="machine"'), 2)


if __name__ == "__main__":
    unittest.main()
