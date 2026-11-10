"""T1560: every product owner and manager seat has a project `about`, from one source: its org.json seat, else its projects.json entry."""
import json, os, re, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash import cache
from dash.services import org as svc
import org  # noqa: E402

SEATS = {"seats": [
    {"id": "owner", "name": "You", "role": "owner", "parent": None, "wake": None, "match": None},
    {"id": "ceo", "name": "Boss", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
    {"id": "fx", "name": "Fennel", "about": "Fx is a test game.", "role": "po", "parent": "ceo", "wake": "po-inbox", "match": "~/agents/po-fx"},
    {"id": "gx", "name": "Gloam", "role": "manager", "parent": "fx", "wake": "po-inbox", "match": "~/agents/po-gx"},
]}
PROJECTS = {"router": "po-fx", "projects": [{"id": "gx", "name": "Gx", "about": "Gx is a test app from the forum."}]}
ENV = ("ORG_FILE", "LIAISON_REGISTRY", "CLAUDE_SESSIONS_DIR")


class About(unittest.TestCase):
    def test_every_live_po_and_manager_has_about(self):
        saved = {k: os.environ.pop(k, None) for k in ("ORG_FILE", "LIAISON_REGISTRY")}
        try:
            seats = org.seats()
            ab = org.abouts(seats)
        finally:
            os.environ.update({k: v for k, v in saved.items() if v is not None})
        self.assertEqual([s["id"] for s in seats if s["role"] in ("po", "manager") and not (ab.get(s["id"]) or "").strip()], [])
        for text in ab.values():
            self.assertLessEqual(len(text), 240, text)
            self.assertIsNone(re.search(r"/home/|~/|@|\d+\.\d+\.\d+\.\d+", text), text)

    def test_api_gives_about_from_one_source(self):
        saved = {k: os.environ.get(k) for k in ENV}
        with tempfile.TemporaryDirectory() as t:
            for name, data in (("org.json", SEATS), ("projects.json", PROJECTS)):
                with open(os.path.join(t, name), "w") as f:
                    json.dump(data, f)
            os.makedirs(os.path.join(t, "reg"))
            os.environ.update(ORG_FILE=os.path.join(t, "org.json"), LIAISON_REGISTRY=os.path.join(t, "projects.json"), CLAUDE_SESSIONS_DIR=os.path.join(t, "reg"))
            cache.forget("org")
            try:
                got = {s["id"]: s.get("about") for s in svc.org_payload()["seats"]}
            finally:
                cache.forget("org")
                for k, v in saved.items():
                    os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)
        self.assertEqual(got, {"owner": None, "ceo": None, "fx": "Fx is a test game.", "gx": "Gx is a test app from the forum."})


if __name__ == "__main__":
    unittest.main()
