"""/next page and /api/agents: fixture transcripts, fixture action log, stubbed orbiter feed."""
import http.client, json, os, sys, tempfile, threading, time, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server
from dash import cache
from dash.services import agents


def jl(path, rows):
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def tool(name, **inp):
    return {"message": {"content": [{"type": "tool_use", "name": name, "input": inp}]}}


class Next(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        t = cls.tmp.name
        subs = os.path.join(t, "proj", "sess1234-x", "subagents")
        os.makedirs(subs)
        started = "2026-09-22T20:00:00.000Z"

        def agent(aid, label, rows, age):
            json.dump({"agentType": "worker", "description": label}, open(os.path.join(subs, "agent-%s.meta.json" % aid), "w"))
            js = os.path.join(subs, "agent-%s.jsonl" % aid)
            jl(js, [{"timestamp": started}] + rows)
            os.utime(js, (time.time() - age, time.time() - age))

        agent("aaa111x", "T48 L5 kernel baseline", [tool("Bash", description="measure idle")], 3600)
        agent("bbb222x", "T45 trust dialog", [tool("Bash", description="read logs"), tool("SubagentHandback", message="1. 0 errors, fail count 0\nmore")], 3600)
        agent("ccc333x", "T60 live build", [tool("Edit", description="edit app")], 10)
        agent("ddd444x", "T61 forgotten", [tool("Read", description="read spec")], 7200)
        agent("eee555x", "T62 broke", [tool("Bash", description="run")], 7200)
        log = os.path.join(t, "actions.jsonl")
        jl(log, [{"ts": "2026-09-22T22:30:00+0200", "summary": "eye status L5 done \\\n  eye status T62 error boom"},
                 {"ts": "2026-09-22T21:00:00+0200", "summary": "eye status T48 working"}])
        cls.saved = (agents.PROJ, agents.ACTIONS, agents.CLAIMS, agents.orbiters, agents.system.BLOCKS["agents"])
        claims = os.path.join(t, "claims.md")
        open(claims, "w").write("# board\n- T60 worker · dashboard/static/next/** · 2026-09-22\n")
        agents.PROJ, agents.ACTIONS, agents.CLAIMS = os.path.join(t, "proj"), log, claims
        agents.orbiters = lambda: [{"id": "T61x", "label": "other", "until": 0}]
        agents.system.BLOCKS["agents"] = (lambda: [{"name": "keeper", "enabled": "enabled", "schedule": "", "next": "", "last": {}}], [])
        cache.forget("agents", "agents_view")
        cls.srv = server.Server(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        agents.PROJ, agents.ACTIONS, agents.CLAIMS, agents.orbiters, agents.system.BLOCKS["agents"] = cls.saved
        cache.forget("agents", "agents_view")
        cls.tmp.cleanup()

    def get(self, path):
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1], timeout=10)
        c.request("GET", path)
        r = c.getresponse()
        body = r.read()
        c.close()
        return r, body

    def test_next_serves(self):
        r, body = self.get("/")
        self.assertEqual(r.status, 200)
        self.assertIn("text/html", r.getheader("Content-Type"))
        self.assertIn(b"/static/next/js/app.js", body)
        for asset in ("/static/next/js/app.js", "/static/next/next.css", "/static/next/vendor/three.sub.js"):
            self.assertEqual(self.get(asset)[0].status, 200, asset)

    def test_classic_and_old_links(self):
        r, body = self.get("/classic")
        self.assertEqual(r.status, 200)
        self.assertIn(b"/static/js/app.js", body)
        self.assertNotIn(b"/static/next/", body)
        r, body = self.get("/next")
        self.assertEqual((r.status, r.getheader("Location"), body), (302, "/", b""))
        for path in ("/static/machine.html", "/index.html"):
            self.assertEqual(self.get(path)[0].status, 200, path)
        for path, to in (("/voice", "/#voice"), ("/pronunciation", "/#pronunciation")):
            r, body = self.get(path)
            self.assertEqual((r.status, r.getheader("Location")), (302, to), path)

    def test_agent_states(self):
        r, body = self.get("/api/agents")
        self.assertEqual(r.status, 200)
        d = json.loads(body)
        st = {s["label"].split()[0] + (s["label"].split()[1] if s["label"].startswith("T48") else ""): s["state"] for s in d["subagents"]}
        self.assertEqual(st, {"T48L5": "done", "T45": "done", "T60": "working", "T61": "stale", "T62": "error"})
        t45 = [s for s in d["subagents"] if s["label"].startswith("T45")][0]
        self.assertEqual(t45["report"], "0 errors, fail count 0")
        self.assertEqual(d["claims"], ["T60 worker · dashboard/static/next/** · 2026-09-22"])
        self.assertEqual(d["orchestrator"]["session"], "sess1234")
        self.assertEqual([a["name"] for a in d["roster"]], ["keeper"])
        self.assertNotIn("prompt", json.dumps(d))


if __name__ == "__main__":
    unittest.main()
