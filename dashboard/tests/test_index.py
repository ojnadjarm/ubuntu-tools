"""N1: the link index on the fixture vault."""
import os, sys, unittest
FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "vault")
os.environ["NOTES_VAULT_DIR"] = FIX
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server


class Index(unittest.TestCase):
    def setUp(self):
        self.idx = server.vault_index()["notes"]

    def test_cycle_gives_one_backlink_each(self):
        a, b = self.idx["Projects/alpha.md"], self.idx["Projects/beta.md"]
        self.assertEqual([l["path"] for l in b["links_in"] if l["path"] == "Projects/alpha.md"], ["Projects/alpha.md"])
        self.assertEqual([l["path"] for l in a["links_in"] if l["path"] == "Projects/beta.md"], ["Projects/beta.md"])

    def test_basename_heading_alias_resolve(self):
        out = {l["target"]: l["path"] for l in self.idx["Projects/alpha.md"]["links_out"]}
        self.assertEqual(out["beta"], "Projects/beta.md")
        self.assertEqual(out["Projects/gamma"], "Projects/gamma.md")
        self.assertEqual(self.idx["eta.md"]["links_out"][1]["path"], "Projects/alpha.md")

    def test_missing_is_unresolved(self):
        d = server.render_note(os.path.join(FIX, "Projects/beta.md"))
        self.assertEqual(d["unresolved"], ["Missing"])
        self.assertEqual([l["path"] for l in d["links_out"]], ["Projects/alpha.md"])

    def test_counts(self):
        a = self.idx["Projects/alpha.md"]
        self.assertEqual((a["tasks_open"], a["tasks_done"]), (3, 1))
        self.assertEqual(a["tags"], ["gnn", "research"])
        self.assertEqual(a["headings"], ["Alpha project", "Tasks"])
        self.assertEqual(len(a["links_in"]), 3)

    def test_facets(self):
        f = server.vault_index()["facets"]
        self.assertEqual(f["status"], {"active": 2, "reference": 2, "idea": 3})
        self.assertEqual(f["tags"], {"gnn": 1, "research": 2, "inline-tag": 1})
        self.assertEqual(f["folders"]["Projects"], 3)

    def test_api_counts(self):
        n = {x["path"]: x for x in server.notes_api()["notes"]}
        self.assertEqual((n["Projects/alpha.md"]["links_in"], n["Projects/alpha.md"]["links_out"]), (3, 2))


if __name__ == "__main__":
    unittest.main()
