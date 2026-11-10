"""lib/staff.py: staff.json validation and the team assignment of roster rows, on a fake HARNESS_HOME."""
import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))
import staff  # noqa: E402

GOOD = {"teams": [
    {"id": "operations", "name": "Operations", "members": [
        {"id": "maintenance", "name": "Briar", "rank": "Caretaker"},
        {"id": "fleet-backup", "name": "Yarrow", "rank": "Archivist", "unit": "fleet-backup.timer"}]},
    {"id": "quality", "name": "Quality", "members": [{"id": "code-review", "name": "Tarn", "rank": "Code Reviewer"}]},
], "hidden": ["hello"]}


class Load(unittest.TestCase):
    """load() reads $HARNESS_HOME/staff.json and names the first problem."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.saved = {k: os.environ.get(k) for k in ("HARNESS_HOME", "STAFF_FILE")}
        os.environ.pop("STAFF_FILE", None)
        os.environ["HARNESS_HOME"] = self.tmp.name

    def tearDown(self):
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def write(self, data):
        with open(os.path.join(self.tmp.name, "staff.json"), "w") as f:
            json.dump(data, f)

    def bad(self, edit, word):
        data = json.loads(json.dumps(GOOD))
        edit(data)
        self.write(data)
        with self.assertRaises(ValueError) as e:
            staff.load()
        self.assertIn(word, str(e.exception))

    def test_good_file_loads(self):
        self.write(GOOD)
        self.assertEqual(staff.load(), GOOD)

    def test_duplicate_id(self):
        self.bad(lambda d: d["teams"][0]["members"].append({"id": "maintenance", "name": "X", "rank": "Y"}), "duplicate")

    def test_member_in_two_teams(self):
        self.bad(lambda d: d["teams"][1]["members"].append({"id": "maintenance", "name": "X", "rank": "Y"}), "2 teams")

    def test_empty_name(self):
        self.bad(lambda d: d["teams"][0]["members"][0].update(name=" "), "name")

    def test_empty_rank(self):
        self.bad(lambda d: d["teams"][0]["members"][0].update(rank=""), "rank")

    def test_unit_not_timer_or_service(self):
        self.bad(lambda d: d["teams"][0]["members"][1].update(unit="fleet-backup.path"), "unit")


class Assign(unittest.TestCase):
    """assign() puts each roster row in its team, else in Unassigned (not seat folders, not hidden)."""

    ROWS = [{"name": "maintenance", "state": "idle", "kind": "timer-agent", "report": "ok"},
            {"name": "fleet-backup", "state": "off", "kind": "bash-timer"},
            {"name": "hello", "state": "off"}, {"name": "po-fx", "state": "off"}, {"name": "newbie", "state": "idle"}]

    def test_merges_row_and_keeps_name_rank(self):
        out = staff.assign(GOOD["teams"], GOOD["hidden"], self.ROWS, ["po-fx"])
        m = out[0]["members"][0]
        self.assertEqual((m["id"], m["name"], m["rank"], m["state"], m["report"]), ("maintenance", "Briar", "Caretaker", "idle", "ok"))
        self.assertEqual(out[0]["members"][1]["kind"], "bash-timer")

    def test_new_agent_goes_to_unassigned(self):
        out = staff.assign(GOOD["teams"], GOOD["hidden"], self.ROWS, ["po-fx"])
        self.assertEqual([t["id"] for t in out], ["operations", "quality", "unassigned"])
        self.assertEqual(out[-1]["name"], "Unassigned")
        self.assertEqual([(m["id"], m["name"], m["rank"]) for m in out[-1]["members"]], [("newbie", "newbie", "Staff")])

    def test_no_unassigned_room_when_everyone_is_placed(self):
        out = staff.assign(GOOD["teams"], GOOD["hidden"], self.ROWS[:4], ["po-fx"])
        self.assertEqual([t["id"] for t in out], ["operations", "quality"])

    def test_input_teams_unchanged(self):
        before = json.dumps(GOOD)
        staff.assign(GOOD["teams"], GOOD["hidden"], self.ROWS, [])
        self.assertEqual(json.dumps(GOOD), before)


if __name__ == "__main__":
    unittest.main()
