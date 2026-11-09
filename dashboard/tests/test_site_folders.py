"""/api/ls folder items: served https page for folders with index.html, one-line description; throwaway fixture drop."""
import os, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server
from dash.services import files


class SiteFolders(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "drop")
        server.DROP = self.root
        self.host = files.PUBLIC_HOST

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, rel, text):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)

    def item(self, name, rel=""):
        return next(i for i in server.ls_dir(rel)[1]["items"] if i["name"] == name)

    def test_index_folder_links_its_served_page(self):
        self.put("my site/index.html", "<title>Hi</title>")
        self.assertEqual(self.item("my site")["site"], "https://%s:8470/my%%20site/" % self.host)

    def test_nested_index_folder_keeps_its_path(self):
        self.put("a/b/index.html", "")
        self.assertEqual(self.item("b", "a")["site"], "https://%s:8470/a/b/" % self.host)

    def test_folder_without_index_has_no_site(self):
        self.put("plain/x.txt", "x")
        self.assertEqual((self.item("plain")["site"], self.item("plain")["about"]), (None, ""))

    def test_about_file_wins(self):
        self.put("v/.about", "\n  All the   films.\nsecond\n")
        self.put("v/README.md", "# Readme\n")
        self.put("v/index.html", "<title>Page</title>")
        self.assertEqual(self.item("v")["about"], "All the films.")

    def test_readme_first_line_then_title(self):
        self.put("r/README.md", "\n## Notes &amp; more\nbody\n")
        self.put("t/index.html", "<html><head><TITLE>\n Mary&#x27;s room </TITLE>")
        self.assertEqual((self.item("r")["about"], self.item("t")["about"]), ("Notes &amp; more", "Mary's room"))

    def test_long_about_is_cut(self):
        self.put("l/.about", "x" * 400)
        self.assertEqual(len(self.item("l")["about"]), 160)

    def test_files_carry_no_folder_fields(self):
        self.put("f.txt", "x")
        self.assertNotIn("site", self.item("f.txt"))


if __name__ == "__main__":
    unittest.main()
