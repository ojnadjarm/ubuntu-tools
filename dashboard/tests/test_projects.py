"""Project tiles: todo parsing, tile state and git facts over fakes; nothing live is touched."""
import os, shutil, tempfile, unittest
from unittest import mock

from dash.services import projects as P

DOCKER = [{"name": "moodle45-app-1", "state": "running", "status": "1 h", "ports": [8045]},
          {"name": "moodle45-db-1", "state": "running", "status": "1 h", "ports": [5445]},
          {"name": "moodle52-app-1", "state": "running", "status": "9 d", "ports": [8052]}]


def notes(text):
    f = tempfile.NamedTemporaryFile("w", suffix=".md", delete=False)
    f.write(text)
    f.close()
    return f.name


def fake_run(log="2026-04-26T08:49:04Z\tMerge main", status=""):
    return lambda cmd, timeout=25: log if "log" in cmd else status


class Projects(unittest.TestCase):
    def test_todo_counts_open_items_of_its_section_only(self):
        path = notes("# vass\n- not me\n## Todo\n- [ ] one\n- two\n- [x] done\n1. three\n### sub\n- four\n## Gotchas\n- no\n")
        self.assertEqual(P.todo_count(path), 4)
        os.unlink(path)

    def test_todo_is_none_without_section_or_file(self):
        path = notes("# vass\n## Gotchas\n- x\n")
        self.assertIsNone(P.todo_count(path))
        self.assertIsNone(P.todo_count("/nonexistent/NOTES.md"))
        os.unlink(path)

    def test_open_tickets_counts_every_state_but_done(self):
        path = notes("# t\n## A\n- **State:** ready to commit, waiting client\n## B\n- **State:** done\n"
                     "## C\n- **State:** `waiting client`\n- state: done later\n## D\nno state\n")
        self.assertEqual(P.open_tickets(path), 3)
        self.assertIsNone(P.open_tickets("/nonexistent/TICKETS.md"))
        os.unlink(path)

    def test_tile_up_with_links_git_and_only_its_containers(self):
        with mock.patch.object(P.sites, "http_code", return_value=200), mock.patch.object(P, "run", fake_run(status=" M a\n?? b\n")):
            t = P.project("vass", P.PROJECTS["vass"], DOCKER)
        self.assertEqual((t["state"], t["up"], t["site_code"], t["dirty"]), ("up", 2, 200, 2))
        self.assertEqual([c["name"] for c in t["containers"]], ["moodle45-app-1", "moodle45-db-1"])
        self.assertEqual(t["commit_at"], "2026-04-26T08:49:04Z")
        self.assertTrue(t["https"].endswith(":8445/") and t["http"].endswith(":8045/") and t["mailhog"].endswith(":8025/"))
        self.assertEqual(t["frontend"], "https://%s:8446/" % P.PUBLIC_HOST)
        self.assertEqual(t["tickets_url"], "/projects/vass/tickets")

    def test_tile_states_down_and_warn(self):
        with mock.patch.object(P.sites, "http_code", return_value=None), mock.patch.object(P, "run", fake_run(log="")):
            down = P.project("vass", P.PROJECTS["vass"], [dict(c, state="exited") for c in DOCKER])
            warn = P.project("vass", P.PROJECTS["vass"], DOCKER)
        self.assertEqual((down["state"], down["up"], down["dirty"], down["commit_at"]), ("down", 0, None, None))
        self.assertEqual(warn["state"], "warn")

    def test_git_reads_never_take_the_index_lock(self):
        seen = []
        with mock.patch.object(P, "run", side_effect=lambda cmd, timeout=25: seen.append(cmd) or "x\ty"):
            P.git_facts("/repo")
        status = [c for c in seen if "status" in c][0]
        self.assertIn("--no-optional-locks", status)
        self.assertTrue(all(c[0] == "git" and c[3] in ("log", "--no-optional-locks") for c in seen))



TICKETS = ("# vass tickets\n\nHeader text.\n\n## JIRA-1 — open one\n\n- **State:** waiting client\n- **Summary:** a\n\n"
           "## JIRA-2 — done one\n\n- **State:** done\n- **Summary:** b\n\n## JIRA-3 — last open\n\n- **State:** pending\n")


class TicketEdits(unittest.TestCase):
    """Close and delete over a temp TICKETS.md under a fake HOME; the real file is never read or written."""

    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.dir = os.path.join(self.home, P.PROJECTS["vass"]["folder"])
        os.makedirs(self.dir)
        self.path = os.path.join(self.dir, "TICKETS.md")
        open(self.path, "w").write(TICKETS)
        self.patch = mock.patch.object(P, "HOME", self.home)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        shutil.rmtree(self.home)

    def text(self):
        return open(self.path).read()

    def backups(self):
        return os.listdir(os.path.join(self.dir, ".tickets-backup"))

    def test_close_sets_only_that_state_line_to_done(self):
        self.assertEqual(P.edit_ticket("vass", "JIRA-1", "close")[0], 200)
        self.assertEqual(self.text(), TICKETS.replace("**State:** waiting client", "**State:** done"))
        self.assertEqual(P.open_tickets(self.path), 1)
        self.assertEqual(open(os.path.join(self.dir, ".tickets-backup", self.backups()[0])).read(), TICKETS)

    def test_delete_removes_the_done_section_only(self):
        self.assertEqual(P.edit_ticket("vass", "JIRA-2", "delete")[0], 200)
        self.assertEqual(self.text(), TICKETS.replace("## JIRA-2 — done one\n\n- **State:** done\n- **Summary:** b\n\n", ""))
        self.assertEqual(len(self.backups()), 1)

    def test_delete_of_the_last_section_restores_the_bytes_before_it_was_appended(self):
        open(self.path, "a").write("\n## PROBE-1 — x\n\n- **State:** pending\n")
        self.assertEqual(P.edit_ticket("vass", "PROBE-1", "close")[0], 200)
        self.assertEqual(P.edit_ticket("vass", "PROBE-1", "delete")[0], 200)
        self.assertEqual(self.text(), TICKETS)

    def test_delete_refused_when_not_done_and_close_refused_when_done(self):
        self.assertEqual(P.edit_ticket("vass", "JIRA-1", "delete"), (400, {"error": "ticket is not done"}))
        self.assertEqual(P.edit_ticket("vass", "JIRA-2", "close"), (400, {"error": "ticket is done"}))
        self.assertEqual(self.text(), TICKETS)
        self.assertFalse(os.path.exists(os.path.join(self.dir, ".tickets-backup")))

    def test_unknown_ids_projects_and_actions_are_refused_untouched(self):
        for args in [("vass", "JIRA-9", "close"), ("vass", "vass", "delete"), ("vass", None, "close"), ("vass", "", "close"),
                     ("nope", "JIRA-1", "close"), (None, "JIRA-1", "close"), ("vass", "JIRA-1", "rename")]:
            self.assertEqual(P.edit_ticket(*args)[0], 400, args)
        self.assertEqual(self.text(), TICKETS)

    def test_close_without_a_state_line_adds_one(self):
        open(self.path, "a").write("\n## JIRA-4 — bare\nbody\n")
        P.edit_ticket("vass", "JIRA-4", "close")
        self.assertTrue(self.text().endswith("## JIRA-4 — bare\n\n- **State:** done\n\nbody\n"))
        self.assertEqual(P.open_tickets(self.path), 2)

    def test_backups_keep_the_newest_twenty(self):
        for _ in range(12):
            P.edit_ticket("vass", "JIRA-1", "close")
            open(self.path, "w").write(TICKETS)
            P.edit_ticket("vass", "JIRA-3", "close")
            open(self.path, "w").write(TICKETS)
        self.assertEqual(len(self.backups()), P.BACKUPS)

    def test_page_shows_close_on_open_and_delete_on_done_only(self):
        page = P.tickets_page("vass")
        self.assertIn('data-tk="close" data-id="JIRA-1"', page)
        self.assertIn('data-tk="delete" data-id="JIRA-2"', page)
        self.assertIn('data-tk="close" data-id="JIRA-3"', page)
        self.assertEqual((page.count('data-tk="delete"'), page.count('data-tk="close"')), (1, 2))
        self.assertIn('src="/static/js/tickets.js"', page)


if __name__ == "__main__":
    unittest.main()
