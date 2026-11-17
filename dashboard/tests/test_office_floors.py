"""Office floors (T1755): staff.json `floors` validation in lib/staff.py and their pass-through in GET /api/office's compose()."""
import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash.services import office
import staff

TEAMS = [{"id": "crew", "name": "Crew", "members": [{"id": "liaison", "name": "Sorrel", "rank": "Liaison"}]}]
FLOOR = {"id": "discord", "name": "Discord", "teams": ["discord", "crew"]}


class Floors(unittest.TestCase):
    """A floor line needs an id (not main), a name and its teams; a team stands on one floor only."""

    def load(self, floors):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"teams": TEAMS, "hidden": [], "floors": floors}, f)
        try:
            return staff.load(f.name)
        finally:
            os.unlink(f.name)

    def test_good_floor_loads(self):
        self.assertEqual(self.load([FLOOR])["floors"], [FLOOR])

    def test_bad_floors(self):
        for floors, word in (([dict(FLOOR, id="")], "empty id"), ([dict(FLOOR, id="main")], "reserved"),
                             ([FLOOR, FLOOR], "duplicate floor"), ([dict(FLOOR, teams=[])], "non-empty"),
                             ([FLOOR, dict(FLOOR, id="labs", teams=["crew"])], "2 floors")):
            with self.subTest(word=word), self.assertRaises(ValueError) as e:
                self.load(floors)
            self.assertIn(word, str(e.exception))

    def test_head_is_one_of_its_teams(self):
        self.assertEqual(self.load([dict(FLOOR, head="discord")])["floors"][0]["head"], "discord")
        with self.assertRaises(ValueError) as e:
            self.load([dict(FLOOR, head="mooblox")])
        self.assertIn("not one of its teams", str(e.exception))

    def test_four_floors_load_in_order(self):
        lines = [dict(FLOOR, id="ops", name="Operations", teams=["quality"], rest=["team"]),
                 dict(FLOOR, id="projects", name="Projects", teams=["mooblox"], rest=["po"]),
                 dict(FLOOR, head="discord"),
                 {"id": "ceo", "name": "CEO", "teams": ["orchestrator"], "head": "orchestrator"}]
        self.assertEqual([f["name"] for f in self.load(lines)["floors"]], ["Operations", "Projects", "Discord", "CEO"])

    def test_bad_rest(self):
        labs = dict(FLOOR, id="labs", teams=["mooblox"])
        for floors, word in (([dict(FLOOR, rest=["seat"])], "not one of po, team"), ([dict(FLOOR, rest="po")], "must be a list"),
                             ([dict(FLOOR, rest=["po"]), dict(labs, rest=["po"])], "rest po on 2 floors")):
            with self.subTest(word=word), self.assertRaises(ValueError) as e:
                self.load(floors)
            self.assertIn(word, str(e.exception))

    def test_compose_sends_floors_only_when_set(self):
        org, ags = {"seats": [], "sessions": []}, {"roster": [], "subagents": []}
        self.assertEqual(office.compose(org, ags, {"teams": TEAMS, "floors": [FLOOR]})["floors"], [FLOOR])
        self.assertNotIn("floors", office.compose(org, ags, {"teams": TEAMS}))


if __name__ == "__main__":
    unittest.main()
