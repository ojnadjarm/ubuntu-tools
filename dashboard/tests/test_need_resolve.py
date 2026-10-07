"""A resolved push leaves the `needs` list; an unresolved or reopened one, or a new push with the same text, stays."""
import json, os, sys, tempfile, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services import system

A = {"t": "2026-10-06T01:01:05+02:00", "kind": "push", "prio": "high", "text": "ailearning daily ci failed at ci (rc 1)"}
B = {"t": "2026-10-06T09:00:00+02:00", "kind": "push", "prio": "high", "text": "disk full"}


class NeedResolve(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.home, "agents/log"))
        self.p = mock.patch.object(system, "HOME", self.home)
        self.p.start()

    def tearDown(self):
        self.p.stop()

    def mark(self, e, state):
        with open(os.path.join(self.home, system.RESOLVED), "a") as f:
            f.write(json.dumps({"ts": "x", "key": system.push_key(e), "state": state}) + "\n")

    def texts(self, ev):
        return [n["text"] for n in system.verdict({}, [], ev)["needs"]]

    def test_without_ledger_every_high_push_needs_you(self):
        self.assertEqual(self.texts([A, B]), [A["text"], B["text"]])

    def test_resolved_push_is_skipped(self):
        self.mark(A, "resolved")
        self.assertEqual(self.texts([A, B]), [B["text"]])

    def test_reopened_push_shows_again(self):
        self.mark(A, "resolved")
        self.mark(A, "open")
        self.assertEqual(self.texts([A, B]), [A["text"], B["text"]])

    def test_new_push_with_same_text_shows_again(self):
        self.mark(A, "resolved")
        again = dict(A, t="2026-10-06T12:00:00+02:00")
        self.assertEqual(self.texts([A, again]), [A["text"]])

    def test_need_carries_its_id(self):
        self.assertEqual(system.verdict({}, [], [A])["needs"][0]["id"], system.push_key(A))
