"""N3: ranked search on the fixture vault."""
import os, sys, unittest
FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "vault")
os.environ["NOTES_VAULT_DIR"] = FIX
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server


class Search(unittest.TestCase):
    def paths(self, q):
        return [h["path"] for h in server.search_notes(q)["hits"]]

    def test_title_outranks_body(self):
        self.assertEqual(self.paths("gnn")[0], "Ideas/zeta.md")
        self.assertIn("Ideas/delta.md", self.paths("gnn"))

    def test_phrase(self):
        self.assertCountEqual(self.paths('"message passing"'), ["Projects/alpha.md", "Ideas/delta.md"])
        self.assertNotIn("theta.md", self.paths('"message passing"'))

    def test_status_prefix(self):
        self.assertEqual(self.paths("status:idea gnn"), ["Ideas/zeta.md", "Ideas/delta.md"])
        self.assertEqual(len(self.paths("folder:Projects")), 3)
        self.assertEqual(self.paths("tag:gnn"), ["Projects/alpha.md"])

    def test_snippets(self):
        h = server.search_notes("alpha")["hits"]
        top = h[0]
        self.assertEqual(top["path"], "Projects/alpha.md")
        self.assertLessEqual(len(top["snippets"]), 3)
        self.assertTrue(any("<mark>alpha</mark>" in s.lower() for s in top["snippets"]))

    def test_accent(self):
        self.assertEqual(self.paths("revision"), ["Projects/beta.md"])


if __name__ == "__main__":
    unittest.main()
