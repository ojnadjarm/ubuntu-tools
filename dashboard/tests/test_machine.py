"""The machine map page: served through the confined static handler, no secrets, no scratch paths."""
import json, os, re, sys, unittest
from unittest import mock
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import server
from dash import cache
from dash.services import system

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
        js = open(os.path.join(HERE, "static", "js", "screens", "machine.js"), encoding="utf-8").read()
        self.assertIn('href="/static/machine.html"', js)


FIX = os.path.join(HERE, "tests", "fixtures", "pc-failures.json")


class Failures(unittest.TestCase):
    """The Vitals failures table: `pc failures --json` flattened to rows, read at most once a minute."""

    def setUp(self):
        cache.forget("pc-failures")
        self.addCleanup(cache.forget, "pc-failures")
        self.raw = open(FIX).read()

    def test_rows_from_fixture(self):
        rows = system.failure_rows(json.loads(self.raw))
        self.assertEqual([r["source"] for r in rows], ["unit"] * 4 + ["agent", "ci", "crash", "need", "check", "audit", "error"])
        self.assertTrue(all(set(r) == {"source", "what", "n", "last", "note", "ours", "dim"} for r in rows))
        self.assertEqual(rows[0], {"source": "unit", "what": "apport-autoreport.service", "n": 5, "last": 1792399198, "note": "exit-code", "ours": True, "dim": False})
        self.assertEqual([r["what"] for r in rows if r["dim"]], ["moodle45-cron.service", "run-p337466-i4293799.scope", "gone: 2 one-off units"])
        self.assertEqual(rows[1]["note"], "exit-code · failed now")
        self.assertEqual(rows[2]["note"], "test oom")
        self.assertEqual((rows[3]["n"], rows[3]["last"]), (34, 1792401155))
        need = rows[7]
        self.assertEqual((need["what"], need["last"]), ("Pick a theme", 1792396800))
        self.assertEqual((rows[8]["what"], rows[8]["n"], rows[8]["note"]), ("T473", 2, "rc 1"))
        self.assertEqual((rows[9]["n"], rows[9]["last"], rows[9]["note"]), (104, None, "1.8% of 5908"))

    def test_clean_audit_has_no_row(self):
        d = json.loads(self.raw)
        d.update(units=[], agents=[], ci=[], crashes=[], needs=[], checks=[], errors={}, audit={"calls": 9, "failed": 0, "rate": 0.0})
        self.assertEqual(system.failure_rows(d), [])

    def test_one_run_per_minute_however_many_polls(self):
        calls = []
        with mock.patch.object(system, "run", side_effect=lambda cmd, t=25: calls.append(cmd) or self.raw):
            for _ in range(20):
                self.assertEqual(len(system.failures()), 11)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1:], ["--since", "24h", "--json"])

    def test_no_json_is_an_error_not_an_empty_table(self):
        with mock.patch.object(system, "run", return_value=""):
            self.assertRaises(RuntimeError, system.failures)

    def test_status_block_and_vitals_table(self):
        self.assertIn("failures", system.BLOCKS)
        js = open(os.path.join(HERE, "static", "next", "js", "screens", "vitals.js"), encoding="utf-8").read()
        self.assertIn("fails(D.failures)", js)
        self.assertIn('class="dim"', js)


if __name__ == "__main__":
    unittest.main()
