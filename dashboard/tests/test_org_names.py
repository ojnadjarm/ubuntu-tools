"""T1554: every staff seat of the real org.json, as GET /api/org gives it, has a proper name, a rank label and its area apart."""
import os, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash import cache
from dash.services import org as svc

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))
import org  # noqa: E402

AGENTS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RANK_WORDS = ("manager", "product owner", "orchestrator")


class Names(unittest.TestCase):
    """The tracked org.json through the API on an empty session registry."""

    def setUp(self):
        self.saved = {k: os.environ.get(k) for k in ("ORG_FILE", "CLAUDE_SESSIONS_DIR")}
        self.tmp = tempfile.TemporaryDirectory()
        os.environ.update(ORG_FILE=os.path.join(AGENTS, "org.json"), CLAUDE_SESSIONS_DIR=self.tmp.name)
        cache.forget("org")

    def tearDown(self):
        cache.forget("org")
        for k, v in self.saved.items():
            os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)
        self.tmp.cleanup()

    def test_staff_seats_have_name_and_rank(self):
        seats = [s for s in svc.org_payload()["seats"] if s["role"] != "owner"]
        self.assertTrue(seats)
        for s in seats:
            self.assertTrue(s["name"].strip(), s["id"])
            self.assertTrue(s["rank"].strip(), s["id"])
            for w in RANK_WORDS:
                self.assertNotIn(w, s["name"].lower(), s["id"])

    def test_owner_stays_you(self):
        owner = [s for s in svc.org_payload()["seats"] if s["role"] == "owner"]
        self.assertEqual([s["name"] for s in owner], ["You"])

    def test_area_is_not_the_name(self):
        for s in org.seats(os.path.join(AGENTS, "org.json")):
            if s.get("area"):
                self.assertNotIn(s["area"].lower(), s["name"].lower(), s["id"])

    def test_rank_labels(self):
        self.assertEqual([org.rank(r) for r in ("ceo", "po", "manager", "worker", "crew")],
                         ["CEO", "Product Owner", "Manager", "Worker", "Crew"])

    def test_proper_name_is_stable_and_free(self):
        a = org.proper_name("new-one", [])
        self.assertEqual(a, org.proper_name("new-one", []))
        self.assertTrue(a.isalpha() and a[0].isupper(), a)
        self.assertNotEqual(org.proper_name("new-one", [a]), a)


if __name__ == "__main__":
    unittest.main()
