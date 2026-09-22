"""N5/N6/N7: today, the audio-notes day, outline and neighbours on the fixture vault."""
import os, sys, unittest
FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "vault")
os.environ["NOTES_VAULT_DIR"] = FIX
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server


class Today(unittest.TestCase):
    def test_open_tasks_listed(self):
        t = [x for x in server.notes_today()["tasks"] if x["path"] == "Projects/alpha.md"]
        self.assertEqual([x["text"] for x in t], ["write the alpha draft", "review beta", "ship"])
        self.assertEqual(t[0]["line"], 11)

    def test_recent_ordered_by_mtime(self):
        r = server.notes_today()["recent"]
        self.assertEqual([x["mtime"] for x in r], sorted([x["mtime"] for x in r], reverse=True))

    def test_unresolved_and_daily(self):
        self.assertEqual(server.notes_api()["unresolved"], [{"target": "Missing", "from": "Projects/beta.md"}])
        self.assertIsNone(server.notes_today()["daily"])


class Audio(unittest.TestCase):
    def test_day_split(self):
        real, server.today_str = server.today_str, lambda: "2026-09-21"
        try:
            a = server.notes_audio()
        finally:
            server.today_str = real
        self.assertEqual(len(a["today"]["raw"]), 2)
        self.assertEqual(a["today"]["raw"][0], {"at": "10:00", "text": "an idea about delta and message ordering"})
        r = a["today"]["refined"]
        self.assertEqual(len(r), 1)
        self.assertEqual((r[0]["path"], r[0]["heading"], r[0]["gist"], r[0]["sure"]), ("Ideas/delta.md", "Order", "Delta should order messages.", True))


class Orientation(unittest.TestCase):
    def test_hub_neighbours_and_outline(self):
        d = server.render_note(os.path.join(FIX, "hub.md"))
        self.assertEqual(len(d["neighbours"]), 6)
        self.assertEqual([h["id"] for h in d["headings"]], ["h-hub", "h-part-one", "h-part-two"])
        self.assertIn('id="h-part-two"', d["html"])
        a = server.render_note(os.path.join(FIX, "Projects/alpha.md"))
        self.assertEqual({n["path"]: n["dir"] for n in a["neighbours"]},
                         {"Projects/beta.md": "both", "Projects/gamma.md": "both", "eta.md": "in"})


if __name__ == "__main__":
    unittest.main()
