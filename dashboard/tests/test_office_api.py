"""GET /api/office: compose() on fixture payloads, unit members read through runners, the route on a fake HARNESS_HOME and its tailnet gate."""
import json, os, sys, tempfile, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash import cache
from dash.services import office, runners, system

SEATS = [
    {"id": "owner", "name": "You", "role": "owner", "parent": None, "wake": None, "match": None, "rank": "Owner"},
    {"id": "orchestrator", "name": "Boss", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~", "rank": "CEO"},
    {"id": "fx", "name": "Fennel", "role": "po", "parent": "orchestrator", "wake": "po-inbox", "match": "~/agents/po-fx",
     "rank": "Product Owner", "area": "Fx", "about": "fx things"},
    {"id": "acme", "name": "Acme", "role": "po", "parent": "orchestrator", "wake": "pull", "match": "~/acme", "rank": "Product Owner"},
]
ORG = {"seats": SEATS, "hidden": 0, "sessions": [
    {"seat": "acme", "state": "working", "since": 1794261588},
    {"seat": "fx", "state": "idle", "since": 1794261500, "pid": 42, "cwd": "~/agents/po-fx", "name": "fx", "started_by": "owner"}]}
ROSTER = [{"name": "po-fx", "kind": "on-demand", "state": "off", "report": "po line"},
          {"name": "maintenance", "kind": "timer-agent", "state": "idle", "report": "swept"},
          {"name": "hello", "state": "off"}, {"name": "newbie", "state": "idle"}]
AGENTS = {"orchestrator": {"name": "Boss", "role": "ceo", "rank": "CEO", "session": "abcd1234", "state": "idle"},
          "subagents": [{"id": "a1", "label": "T1 x", "state": "working"}], "orbiters": [], "roster": ROSTER, "claims": ["T1 · a.py"]}
STAFF = {"teams": [{"id": "operations", "name": "Operations", "members": [
    {"id": "maintenance", "name": "Briar", "rank": "Caretaker"},
    {"id": "fleet-backup", "name": "Yarrow", "rank": "Archivist", "unit": "fleet-backup.timer"}]}], "hidden": ["hello"]}


class Compose(unittest.TestCase):
    """compose() is pure: seats without the owner, a po seat's runner, protected sessions as given, staff teams, error."""

    def test_no_owner_seat_and_no_match(self):
        out = office.compose(ORG, AGENTS, STAFF)
        self.assertEqual([s["id"] for s in out["seats"]], ["orchestrator", "fx", "acme"])
        self.assertTrue(all("match" not in s for s in out["seats"]))

    def test_po_seat_gets_its_runner(self):
        seats = {s["id"]: s for s in office.compose(ORG, AGENTS, STAFF)["seats"]}
        self.assertEqual(seats["fx"]["runner"]["report"], "po line")
        self.assertEqual((seats["fx"]["area"], seats["fx"]["about"]), ("Fx", "fx things"))
        self.assertNotIn("runner", seats["acme"])
        self.assertNotIn("runner", seats["orchestrator"])

    def test_protected_session_keeps_three_keys(self):
        out = office.compose(ORG, AGENTS, STAFF)
        self.assertEqual(sorted(out["sessions"][0]), ["seat", "since", "state"])

    def test_staff_teams_and_unassigned(self):
        out = office.compose(ORG, AGENTS, STAFF)
        self.assertEqual([t["id"] for t in out["staff"]], ["operations", "unassigned"])
        self.assertEqual(out["staff"][0]["members"][0]["report"], "swept")
        self.assertEqual([m["id"] for m in out["staff"][1]["members"]], ["newbie"])

    def test_agents_block(self):
        out = office.compose(ORG, AGENTS, STAFF)
        self.assertEqual(sorted(out["agents"]), ["claims", "orchestrator", "subagents"])
        self.assertEqual(out["agents"]["claims"], ["T1 · a.py"])

    def test_error_passes_through(self):
        self.assertNotIn("error", office.compose(ORG, AGENTS, STAFF))
        out = office.compose(dict(ORG, error="org broke"), dict(AGENTS, error="agents broke"), STAFF)
        self.assertEqual(out["error"], "org broke; agents broke")


class TimerRows(unittest.TestCase):
    """A unit member is read through runners.facts + runners.view into a roster-shaped row."""

    def test_unit_member_row(self):
        props = {"fleet-backup.timer": {"Id": "fleet-backup.timer", "UnitFileState": "enabled", "ActiveState": "active",
                                        "Triggers": "fleet-backup.service", "LastTriggerUSec": "@1794261000"},
                 "fleet-backup.service": {"Id": "fleet-backup.service", "ActiveState": "inactive", "Result": "success",
                                          "ExecMainStatus": "0", "ExecMainStartTimestamp": "@1794261000",
                                          "ExecMainExitTimestamp": "@1794261090"}}
        timers = json.dumps([{"unit": "fleet-backup.timer", "next": 1794347400000000}])
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "fleet-backup.timer"), "w") as f:
                f.write("[Timer]\nOnCalendar=*-*-* 02:30\n")
            with mock.patch.object(system, "unit_props", lambda p, u: {k: v for k, v in props.items() if k in u}), \
                    mock.patch.object(runners, "run", lambda cmd, t: timers), mock.patch.object(runners, "UNIT_DIR", d):
                rows = office.timer_rows({"fleet-backup": "fleet-backup.timer"})
        r = rows[0]
        self.assertEqual((r["name"], r["kind"], r["state"], r["health"], r["schedule"]), ("fleet-backup", "bash-timer", "idle", "ok", "daily 02:30"))
        self.assertEqual((r["last"]["exit"], r["last"]["seconds"]), ("0", "90"))
        self.assertEqual(r["runner"]["service"], "fleet-backup.service")
        self.assertNotIn("fallback", r)
        self.assertTrue(r["next"])


class Route(unittest.TestCase):
    """The route on a fake HARNESS_HOME with fixture org and agents reads; the LAN gets 403."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.saved = {k: os.environ.get(k) for k in ("HARNESS_HOME", "STAFF_FILE")}
        os.environ.pop("STAFF_FILE", None)
        os.environ["HARNESS_HOME"] = self.tmp.name
        with open(os.path.join(self.tmp.name, "staff.json"), "w") as f:
            json.dump(STAFF, f)
        cache.forget("office", "org")
        self.patches = [mock.patch.object(office.org_svc, "org_payload", lambda: ORG),
                        mock.patch.object(office.agents, "payload", lambda: AGENTS),
                        mock.patch.object(office, "timer_rows", lambda units: [{"name": n, "kind": "bash-timer", "state": "idle"} for n in units])]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        cache.forget("office", "org")
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def call(self, ip, fwd=None):
        out = []
        h = type("H", (), {"client_address": (ip, 0), "headers": {"X-Forwarded-For": fwd} if fwd else {},
                           "json": lambda self, obj, code=200: out.append((code, obj))})()
        office.office_route(h, "/api/office")
        return out[-1]

    def test_payload(self):
        code, body = self.call("127.0.0.1")
        self.assertEqual(code, 200)
        self.assertEqual(sorted(body), ["agents", "seats", "sessions", "staff"])
        self.assertEqual([m["id"] for m in body["staff"][0]["members"]], ["maintenance", "fleet-backup"])
        self.assertEqual(body["staff"][0]["members"][1]["kind"], "bash-timer")

    def test_bad_staff_file_says_error(self):
        with open(os.path.join(self.tmp.name, "staff.json"), "w") as f:
            json.dump({"teams": [{"id": "x", "name": "X", "members": [{"id": "a", "name": "", "rank": "R"}]}], "hidden": []}, f)
        code, body = self.call("127.0.0.1")
        self.assertEqual(code, 200)
        self.assertIn("name", body["error"])

    def test_lan_is_403(self):
        self.assertEqual(self.call("192.0.2.10")[0], 403)
        self.assertEqual(self.call("127.0.0.1", "192.0.2.10")[0], 403)


if __name__ == "__main__":
    unittest.main()
