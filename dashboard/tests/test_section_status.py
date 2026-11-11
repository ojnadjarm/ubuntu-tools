"""Section status (T1687): lib/section_status.py check and view, validated on org.json and staff.json load, surfaced by office.compose."""
import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))
import org  # noqa: E402
import section_status as st  # noqa: E402
import staff  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import server  # noqa: E402,F401
from dash.services import office  # noqa: E402

SEATS = [
    {"id": "owner", "name": "You", "area": None, "role": "owner", "parent": None, "wake": None, "match": None},
    {"id": "orchestrator", "name": "O", "area": None, "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
    {"id": "vass", "name": "Thistle", "area": "Vass", "role": "po", "parent": "orchestrator", "wake": "pull", "match": "~/x/vass"},
]
TEAMS = {"teams": [{"id": "finance", "name": "Finance", "members": [{"id": "hacienda", "name": "Laurel", "rank": "Tax Clerk"}]}], "hidden": []}


class Check(unittest.TestCase):
    """check() names the section and the problem; absent and known ids pass."""

    def test_absent_and_known_pass(self):
        for raw in (None, {"id": "active"}, {"id": "paused", "since": "2026-11-11"}, {"id": "vacation", "note": "back Monday"}):
            st.check("seat vass", raw)

    def test_unknown_id(self):
        with self.assertRaisesRegex(ValueError, r"seat vass: status id 'closed' not in \('active', 'paused', 'vacation'\)"):
            st.check("seat vass", {"id": "closed"})

    def test_bad_since_note_and_keys(self):
        with self.assertRaisesRegex(ValueError, "since '11/11/2026' is not YYYY-MM-DD"):
            st.check("team finance", {"id": "paused", "since": "11/11/2026"})
        with self.assertRaisesRegex(ValueError, "note must be text"):
            st.check("team finance", {"id": "paused", "note": 3})
        with self.assertRaisesRegex(ValueError, "team finance: status must be an object"):
            st.check("team finance", "paused")
        with self.assertRaisesRegex(ValueError, "status must be an object"):
            st.check("team finance", {"id": "paused", "until": "2026-12-01"})

    def test_view(self):
        self.assertIsNone(st.view(None))
        self.assertIsNone(st.view({"id": "active", "since": "2026-11-11"}))
        self.assertEqual(st.view({"id": "paused", "since": "2026-11-11"}), {"id": "paused", "label": "Paused", "since": "2026-11-11"})
        self.assertEqual(st.view({"id": "vacation", "note": "back Monday"}), {"id": "vacation", "label": "On vacation", "note": "back Monday"})


class Load(unittest.TestCase):
    """org.seats() and staff.load() reject an unknown status id with the section's name; a good status loads."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, data):
        p = os.path.join(self.tmp.name, name)
        with open(p, "w") as f:
            json.dump(data, f)
        return p

    def test_org(self):
        good = [dict(s, status={"id": "paused", "since": "2026-11-11"}) if s["id"] == "vass" else s for s in SEATS]
        self.assertEqual(org.seats(self.write("org.json", {"seats": good}))[2]["status"]["id"], "paused")
        bad = [dict(s, status={"id": "gone"}) if s["id"] == "vass" else s for s in SEATS]
        with self.assertRaisesRegex(ValueError, "seat vass: status id 'gone'"):
            org.seats(self.write("org.json", {"seats": bad}))

    def test_staff(self):
        good = {**TEAMS, "teams": [dict(TEAMS["teams"][0], status={"id": "vacation"})]}
        self.assertEqual(staff.load(self.write("staff.json", good))["teams"][0]["status"], {"id": "vacation"})
        bad = {**TEAMS, "teams": [dict(TEAMS["teams"][0], status={"id": "holiday"})]}
        with self.assertRaisesRegex(ValueError, "team finance: status id 'holiday'"):
            staff.load(self.write("staff.json", bad))


class Compose(unittest.TestCase):
    """office.compose carries {id, label, since?, note?} on a resting seat and team; an active or absent status leaves no key."""

    def test_seat_and_team(self):
        seats = [dict(s, rank="X", status={"id": "paused", "since": "2026-11-11"}) if s["id"] == "vass" else dict(s, rank="X") for s in SEATS]
        cfg = {"teams": [dict(TEAMS["teams"][0], status={"id": "vacation"}), {"id": "ops", "name": "Ops", "members": [], "status": {"id": "active"}}], "hidden": []}
        out = office.compose({"seats": seats, "sessions": []}, {"roster": [], "subagents": []}, cfg)
        by = {s["id"]: s for s in out["seats"]}
        self.assertEqual(by["vass"]["status"], {"id": "paused", "label": "Paused", "since": "2026-11-11"})
        self.assertNotIn("status", by["orchestrator"])
        teams = {t["id"]: t for t in out["staff"]}
        self.assertEqual(teams["finance"]["status"], {"id": "vacation", "label": "On vacation"})
        self.assertNotIn("status", teams["ops"])


if __name__ == "__main__":
    unittest.main()
