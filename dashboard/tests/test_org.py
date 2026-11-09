"""GET /api/org: seats, live sessions (protected ones on/off only), hidden count and the tailnet gate, on a fixture registry."""
import json, os, subprocess, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash import cache
from dash.services import org as svc

SEATS = {"seats": [
    {"id": "owner", "name": "You", "role": "owner", "parent": None, "wake": None, "match": None},
    {"id": "ceo", "name": "Orchestrator", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
    {"id": "fx", "name": "Fx owner", "role": "po", "parent": "ceo", "wake": "po-inbox", "match": "~/agents/po-fx"},
]}
ENV = ("HOME", "ORG_FILE", "CLAUDE_SESSIONS_DIR", "HARNESS_CONFIG", "PROTECTED_PROJECTS", "WORK_REPO_ROOTS", "HARNESS_ENV_LOADED")


def start(pid):
    with open(f"/proc/{pid}/stat") as f:
        return f.read().rsplit(")", 1)[1].split()[19]


class Org(unittest.TestCase):
    """A temp home with a fixture org, a protected-project config and registry rows for live, ended and broken sessions."""

    def setUp(self):
        self.saved = {k: os.environ.get(k) for k in ENV}
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.home = os.path.join(t, "home")
        reg = os.path.join(t, "reg")
        for d in ("agents/po-fx", "agents/job", "acme"):
            os.makedirs(os.path.join(self.home, d))
        os.makedirs(reg)
        with open(os.path.join(t, "org.json"), "w") as f:
            json.dump(SEATS, f)
        with open(os.path.join(t, "config.env"), "w") as f:
            f.write('PROTECTED_PROJECTS="acme"\nPROTECTED_ACME_PATHS="%s/acme"\n' % self.home)
        for k in ("PROTECTED_PROJECTS", "WORK_REPO_ROOTS", "HARNESS_ENV_LOADED"):
            os.environ.pop(k, None)
        os.environ.update(HOME=self.home, ORG_FILE=os.path.join(t, "org.json"), CLAUDE_SESSIONS_DIR=reg, HARNESS_CONFIG=os.path.join(t, "config.env"))
        self.procs = [subprocess.Popen(["sleep", "60"]) for _ in range(3)]
        rows = [(self.procs[0].pid, self.home, "busy", "Orchestrator session"), (self.procs[1].pid, self.home + "/agents/job", "idle", "agent-fx-job"),
                (self.procs[2].pid, self.home + "/acme", "busy", "secret client work")]
        for pid, cwd, st, name in rows:
            with open(os.path.join(reg, f"{pid}.json"), "w") as f:
                json.dump({"pid": pid, "cwd": cwd, "procStart": start(pid), "status": st, "statusUpdatedAt": 1794261588030, "name": name, "entrypoint": "cli"}, f)
        with open(os.path.join(reg, "999999.json"), "w") as f:
            json.dump({"pid": 999999, "cwd": self.home, "procStart": "1", "status": "busy"}, f)
        with open(os.path.join(reg, "broken.json"), "w") as f:
            f.write("{not json")
        self.old_home, svc.HOME = svc.HOME, self.home
        cache.forget("org")

    def tearDown(self):
        for p in self.procs:
            p.kill()
            p.wait()
        svc.HOME = self.old_home
        cache.forget("org")
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def call(self, ip, fwd=None):
        out = []
        h = type("H", (), {"client_address": (ip, 0), "headers": {"X-Forwarded-For": fwd} if fwd else {},
                           "json": lambda self, obj, code=200: out.append((code, obj))})()
        svc.org_route(h, "/api/org")
        return out[-1]

    def test_payload(self):
        code, body = self.call("127.0.0.1")
        self.assertEqual(code, 200)
        self.assertEqual([s["id"] for s in body["seats"]], ["owner", "ceo", "fx"])
        self.assertEqual(body["hidden"], 2, "the ended and the broken registry rows are hidden")
        rows = {r.get("name"): r for r in body["sessions"]}
        self.assertEqual(len(body["sessions"]), 3)
        ceo = rows["Orchestrator session"]
        self.assertEqual((ceo["seat"], ceo["state"], ceo["cwd"], ceo["since"]), ("ceo", "working", "~", 1794261588))
        job = rows["agent-fx-job"]
        self.assertEqual((job["seat"], job["parent"], job["state"], job["cwd"], job["started_by"]), (None, "ceo", "idle", "~/agents/job", "fx-job"))

    def test_protected_is_on_off_only(self):
        body = self.call("127.0.0.1")[1]
        prot = [r for r in body["sessions"] if "pid" not in r]
        self.assertEqual(len(prot), 1)
        self.assertEqual(sorted(prot[0]), ["seat", "since", "state"])
        self.assertNotIn("secret", json.dumps(body))
        self.assertNotIn("acme", json.dumps(body))

    def test_lan_is_403(self):
        for ip, code in (("192.0.2.10", 403), ("::ffff:10.0.0.4", 403), ("100.101.102.103", 200), ("::1", 200)):
            self.assertEqual(self.call(ip)[0], code, ip)
        for fwd, code in (("192.0.2.10", 403), ("100.101.102.103, 192.0.2.10", 403), ("garbage", 403), ("100.101.102.103", 200)):
            self.assertEqual(self.call("127.0.0.1", fwd)[0], code, "front forwards " + fwd)


if __name__ == "__main__":
    unittest.main()
