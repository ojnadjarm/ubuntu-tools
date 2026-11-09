"""Badge keys of push, fail and agent needs carry their onset, so a recurrence re-badges; seen.json drops need keys after 30 days."""
import json, os, subprocess, sys, tempfile, unittest
from datetime import datetime, timedelta
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services import state, system

JS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "static", "next", "js")


def keys(needs):
    js = "import('./verdict.js').then((m) => console.log(JSON.stringify(m.verdict(JSON.parse(process.argv[1])).keys)))"
    out = subprocess.run(["node", "--input-type=module", "-e", js, json.dumps({"verdict": {"needs": needs}})],
                         cwd=JS, capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def needs(st, ag, ev):
    with mock.patch.object(system, "resolved", return_value=set()):
        return system.verdict(st, ag, ev)["needs"]


class NeedKeys(unittest.TestCase):
    def test_recurring_push_fail_and_agent_needs_get_new_keys(self):
        st = {"sections": {"host": {"failed_units": {"state": "FAIL"}}}}
        push = lambda t: {"kind": "push", "t": t, "prio": "high", "text": "agent toolsmith failed (exit 143)"}
        agent = lambda end: [{"name": "code-review", "last": {"end": end, "exit": "1"}}]
        with mock.patch.object(system, "datetime", wraps=datetime) as dt:
            dt.now.return_value = datetime(2026, 10, 22, 4, 0)
            first = keys(needs(st, agent("2026-10-22T04:00:00+02:00"), [push("2026-10-22T04:00:01+02:00")]))
            dt.now.return_value = datetime(2026, 11, 1, 4, 3)
            again = keys(needs(st, agent("2026-11-01T04:03:00+02:00"), [push("2026-10-22T05:02:56+02:00")]))
        self.assertEqual(len(first), 3)
        self.assertEqual([k for k in again if k in first], [], "a recurrence has no key already seen")
        self.assertTrue(all(k.startswith("need:") for k in again))

    def test_same_occurrence_keeps_its_key(self):
        st = {"sections": {"host": {"failed_units": {"state": "FAIL"}}}}
        ag = [{"name": "code-review", "last": {"end": "2026-10-22T04:00:00+02:00", "exit": "1"}}]
        self.assertEqual(keys(needs(st, ag, [])), keys(needs(st, ag, [])))

    def test_seen_add_prunes_need_keys_older_than_30_days(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "seen.json")
            old = (datetime.now() - timedelta(days=31)).strftime("%Y-%m-%d")
            json.dump({"need:a@x": old, "need:b@y": datetime.now().strftime("%Y-%m-%d"), "file:z": old, "need:legacy": 1}, open(f, "w"))
            with mock.patch.object(state, "SEEN_FILE", f):
                got = state.seen_add(["need:c@z"])
        self.assertNotIn("need:a@x", got)
        self.assertEqual(set(got), {"need:b@y", "file:z", "need:legacy", "need:c@z"})
        self.assertTrue(all(got.values()), "every seen value stays truthy for router.js")


if __name__ == "__main__":
    unittest.main()
