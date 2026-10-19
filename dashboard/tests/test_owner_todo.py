"""Open owner to-dos join the `needs` list as kind todo; the Done route closes one; `pc need` never sees them (no `id`)."""
import io, json, os, sys, tempfile, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services import system, todo


class FakeHandler:
    def __init__(self, body):
        self.body, self.out = body, None

    def body_json(self, limit, empty):
        return self.body

    def json(self, obj, code=200):
        self.out = (code, obj)


class OwnerTodo(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.env = mock.patch.dict(os.environ)
        self.env.start()
        os.environ.pop("OWNER_TODO_LEDGER", None)
        self.p = mock.patch.object(todo, "HOME", self.home)
        self.p.start()
        todo.owner_todo.add("Run the ufw script", "sudo bash x.sh", "T362", "test", self.home)
        todo.owner_todo.add("Grant the bot a role", "", "", "test", self.home)

    def tearDown(self):
        self.p.stop()
        self.env.stop()

    def test_open_items_become_needs(self):
        needs = system.verdict({}, [], [], todo.open_items())["needs"]
        self.assertEqual([(n["kind"], n["todo"]) for n in needs], [("todo", "1"), ("todo", "2")])
        self.assertTrue(all("id" not in n for n in needs))

    def test_without_todos_verdict_unchanged(self):
        self.assertTrue(system.verdict({}, [], [])["ok"])

    def test_done_route_closes_one(self):
        h = FakeHandler({"id": "1"})
        todo.done_route(h, "/api/owner-todo/done")
        self.assertEqual(h.out[0], 200)
        self.assertEqual([i["id"] for i in todo.open_items()], ["2"])
        done = todo.owner_todo.items(self.home, all=True)[0]
        self.assertEqual((done["done"], done["note"]), (True, "tapped Done on the dashboard"))

    def test_done_route_refuses_unknown_and_repeat(self):
        for body in ({"id": "9"}, {}, "x"):
            h = FakeHandler(body)
            todo.done_route(h, "")
            self.assertEqual(h.out[0], 400, body)
        todo.done_route(FakeHandler({"id": "2"}), "")
        h = FakeHandler({"id": "2"})
        todo.done_route(h, "")
        self.assertEqual(h.out, (400, {"error": "item 2 is already done"}))


GOOD = b'{"op": "add", "id": "1", "text": "Good row", "ts": "t"}\n'
BROKEN = {"int id": GOOD + b'{"op": "add", "id": 2, "text": "Int id"}\n',
          "0xff byte": GOOD + b'{"op": "add", "id": "2", "text": "bad \xff byte"}\n',
          "no final newline": GOOD + b'{"op": "add", "id": "2", "te'}


class BrokenLedger(unittest.TestCase):
    """/api/status stays 200 on a broken ledger: good rows list and todo_error names the problem."""

    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.ledger = os.path.join(self.home, "agents", "state", "owner-todo.jsonl")
        os.makedirs(os.path.dirname(self.ledger))
        self.env = mock.patch.dict(os.environ)
        self.env.start()
        os.environ.pop("OWNER_TODO_LEDGER", None)
        blocks = {k: v[1] for k, v in system.BLOCKS.items()}
        self.ps = [mock.patch.object(todo, "HOME", self.home), mock.patch.object(system, "swr", return_value=blocks),
                   mock.patch.object(system, "cache_meta", return_value=(False, {}, "")),
                   mock.patch.object(system.sites, "test_site", return_value={})]
        for p in self.ps:
            p.start()

    def tearDown(self):
        for p in self.ps:
            p.stop()
        self.env.stop()

    def status(self):
        h = FakeHandler(None)
        system.status_route(h, "/api/status")
        return h.out

    def test_each_broken_ledger_gives_200_with_todo_error(self):
        for name, data in BROKEN.items():
            with self.subTest(name), open(self.ledger, "wb") as f:
                f.write(data)
            code, out = self.status()
            self.assertEqual(code, 200, name)
            self.assertTrue(out["todo_error"].startswith("line 2: "), (name, out["todo_error"]))
            self.assertEqual(out["todo"][0]["text"], "Good row", name)

    def test_clean_ledger_has_empty_todo_error(self):
        with open(self.ledger, "wb") as f:
            f.write(GOOD)
        code, out = self.status()
        self.assertEqual((code, out["todo_error"], [i["id"] for i in out["todo"]]), (200, "", ["1"]))

    def test_raise_in_reader_becomes_todo_error(self):
        with mock.patch.object(todo.owner_todo, "read", side_effect=RuntimeError("boom")):
            code, out = self.status()
        self.assertEqual((code, out["todo"], out["todo_error"]), (200, [], "RuntimeError: boom"))


if __name__ == "__main__":
    unittest.main()
