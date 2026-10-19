"""/api/agents liveness on fixtures: finished agents leave the live list, live ones stay, persistent ones show idle/running."""
import io, json, os, sys, tempfile, threading, time, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash import cache
from dash.services import agents


def jl(path, rows, mode="w"):
    with open(path, mode) as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))


def tool(name, t, **inp):
    return {"timestamp": iso(t), "message": {"content": [{"type": "tool_use", "name": name, "input": inp}]}}


def note(tid, status, t):
    return {"type": "user", "timestamp": iso(t), "message": {"content": "<task-notification>\n<task-id>%s</task-id>\n<status>%s</status>\n</task-notification>" % (tid, status)}}


class Live(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t, now = self.tmp.name, time.time()
        self.now = now
        self.proj = os.path.join(t, "projects", "-srv-x")
        self.subs = os.path.join(self.proj, "sess5678-y", "subagents")
        os.makedirs(os.path.join(self.subs, "workflows", "wf_abc"))
        self.parent = os.path.join(self.proj, "sess5678-y.jsonl")
        self.saved = (agents.PROJ, agents.ACTIONS, agents.CLAIMS, agents.AGENTS_DIR, agents.orbiters, agents.tmux_sessions,
                      agents.unit_states, agents.system.BLOCKS["agents"])
        agents.PROJ, agents.ACTIONS, agents.CLAIMS = self.proj, os.path.join(t, "none.jsonl"), os.path.join(t, "none.md")
        agents.AGENTS_DIR = "/srv/x/agents"
        agents.orbiters = lambda: []
        agents.tmux_sessions = lambda: {"claude", "notes"}
        agents.unit_states = lambda names: {n: ("active" if n == "keeper" else "inactive") for n in names}
        agents.system.BLOCKS["agents"] = (lambda: [
            {"name": "keeper", "enabled": "enabled", "schedule": "", "next": "", "last": {}},
            {"name": "digest", "enabled": "enabled", "schedule": "", "next": "", "last": {}},
            {"name": "notes", "enabled": "disabled", "schedule": "", "next": "", "last": {}},
            {"name": "hello", "enabled": "disabled", "schedule": "", "next": "", "last": {}}], [])
        cache.forget("agents", "agents_view", "agents_persist")
        agents._parent.clear()
        agents._feed.clear()

    def tearDown(self):
        (agents.PROJ, agents.ACTIONS, agents.CLAIMS, agents.AGENTS_DIR, agents.orbiters, agents.tmux_sessions,
         agents.unit_states, agents.system.BLOCKS["agents"]) = self.saved
        cache.forget("agents", "agents_view", "agents_persist")
        agents._parent.clear()
        agents._feed.clear()
        self.tmp.cleanup()

    def agent(self, aid, label, rows, age, folder=None):
        folder = folder or self.subs
        json.dump({"agentType": "worker", "description": label}, open(os.path.join(folder, "agent-%s.meta.json" % aid), "w"))
        js = os.path.join(folder, "agent-%s.jsonl" % aid)
        jl(js, [{"timestamp": iso(self.now - age - 600)}] + rows)
        os.utime(js, (self.now - age, self.now - age))
        return js

    def states(self):
        cache.forget("agents_view", "agents_persist")
        return {s["label"]: s["state"] for s in agents.collect()["subagents"]}

    def test_finished_leaves_live_one_stays(self):
        n = self.now
        self.agent("aaa", "T70 finished", [tool("Bash", n - 30, description="x"), tool("SubagentHandback", n - 20, message="1. done it")], 10)
        self.agent("bbb", "T71 live", [tool("Edit", n - 5, description="edit")], 5)
        self.agent("ccc", "T72 yesterday", [tool("SubagentHandback", n - 90000, message="old")], 90000)
        st = self.states()
        self.assertEqual(st, {"T70 finished": "done", "T71 live": "working"})
        self.assertEqual([s["label"] for s in agents.collect()["subagents"]][0], "T71 live")

    def test_notification_ends_and_resume_revives(self):
        n = self.now
        self.agent("ddd", "T73 killed", [tool("Bash", n - 40, description="run")], 30)
        self.agent("eee", "T74 resumed", [tool("Bash", n - 5, description="again")], 5)
        jl(self.parent, [note("ddd", "killed", n - 20), note("eee", "completed", n - 300)])
        self.assertEqual(self.states(), {"T73 killed": "stale", "T74 resumed": "working"})
        self.agent("fff", "T75 later", [tool("Bash", n - 5, description="go")], 5)
        self.assertEqual(self.states()["T75 later"], "working")
        jl(self.parent, [note("fff", "completed", n)], "a")
        self.assertEqual(self.states()["T75 later"], "done")

    def test_handback_then_kill_stays_done(self):
        n = self.now
        self.agent("hbk", "T158 handed", [tool("SubagentHandback", n - 25, message="1. done")], 20)
        jl(self.parent, [note("hbk", "killed", n - 20)])
        self.assertEqual(self.states(), {"T158 handed": "done"})

    def test_workflow_agents(self):
        n, wf = self.now, os.path.join(self.subs, "workflows", "wf_abc")
        jl(self.parent, [{"type": "user", "timestamp": iso(n - 900), "toolUseResult": {"status": "async_launched", "taskId": "wtask1", "taskType": "local_workflow",
                                                                                     "workflowName": "T76-swarm", "runId": "wf_abc"}}])
        self.agent("ggg", "research:a", [tool("Read", n - 400, description="read")], 400, wf)
        self.agent("hhh", "mockup:b", [tool("Write", n - 3, description="write")], 3, wf)
        jl(os.path.join(wf, "journal.jsonl"), [{"type": "started", "agentId": "ggg"}, {"type": "result", "agentId": "ggg"}, {"type": "started", "agentId": "hhh"}])
        self.assertEqual(self.states(), {"T76 research:a": "done", "T76 mockup:b": "working"})
        jl(self.parent, [note("wtask1", "killed", n)], "a")
        self.assertEqual(self.states()["T76 mockup:b"], "stale")

    def test_feed_end_survives_a_busy_log(self):
        n, log = self.now, os.path.join(self.tmp.name, "actions.jsonl")
        agents.ACTIONS = log
        self.agent("kkk", "T99 feed-ended", [tool("Bash", n - 7300, description="run")], 7200)
        jl(log, [{"ts": iso(n - 7200), "summary": "eye status T99 done"}] + [{"ts": iso(n - 60), "summary": "x" * 200}] * 8000)
        self.assertEqual(self.states(), {"T99 feed-ended": "done"})
        jl(log, [{"ts": iso(n), "summary": "eye status T99 error"}], "a")
        self.assertEqual(self.states(), {"T99 feed-ended": "error"})

    def test_concurrent_feed_reads_advance_once(self):
        log = os.path.join(self.tmp.name, "actions.jsonl")
        agents.ACTIONS = log
        jl(log, [{"ts": iso(self.now - 60), "summary": "x"}] * 50)
        gate = threading.Barrier(2, timeout=1)

        class Gated(io.FileIO):
            def read(self, n=-1):
                out = super().read(n)
                try:
                    gate.wait()
                except threading.BrokenBarrierError:
                    pass
                return out
        agents.open = Gated
        try:
            ts = [threading.Thread(target=agents.feed) for _ in range(2)]
            [t.start() for t in ts]
            [t.join() for t in ts]
        finally:
            del agents.open
        jl(log, [{"ts": iso(self.now), "summary": "eye status T98 done"}] + [{"ts": iso(self.now - 60), "summary": "x"}] * 50, "a")
        self.assertEqual([s for _, s in agents.feed().get("t98", [])], ["done"])

    def test_workflow_failed_is_error(self):
        wf = os.path.join(self.subs, "workflows", "wf_abc")
        self.agent("iii", "research:c", [tool("Read", self.now - 2000, description="read")], 2000, wf)
        jl(os.path.join(wf, "journal.jsonl"), [{"type": "started", "agentId": "iii"}, {"type": "failed", "agentId": "iii"}])
        self.assertEqual(self.states(), {"research:c": "error"})

    def test_stopped_then_resumed_workflow(self):
        n, wf = self.now, os.path.join(self.subs, "workflows", "wf_abc")
        launch = lambda tid, t: {"type": "user", "timestamp": iso(t), "toolUseResult": {"status": "async_launched", "taskId": tid,
                                 "taskType": "local_workflow", "workflowName": "t87-polish", "runId": "wf_abc"}}
        agents.orbiters = lambda: [{"id": "T87"}, {"id": "old111"}]
        jl(self.parent, [launch("wone", n - 3000), tool("TaskStop", n - 1320, task_id="wone")])
        self.agent("des222", "design", [tool("SubagentHandback", n - 2500, message="1. arch")], 2500, wf)
        self.agent("old111", "build", [tool("Edit", n - 1320, description="edit")], 1320, wf)
        journal = os.path.join(wf, "journal.jsonl")
        jl(journal, [{"type": "launched"}, {"type": "started", "agentId": "des222", "label": "design"}, {"type": "result", "agentId": "des222"},
                     {"type": "started", "agentId": "old111", "label": "build"}])
        states = lambda: sorted((s["id"], s["state"]) for s in agents.collect()["subagents"])
        cache.forget("agents_view")
        self.assertEqual(states(), [("des222", "done"), ("old111", "stale")])
        jl(self.parent, [launch("wtwo", n - 1280)], "a")
        agents.orbiters = lambda: [{"id": "T87"}, {"id": "old111"}, {"id": "new333"}]
        new = self.agent("new333", "build", [tool("Edit", n - 5, description="edit")], 5, wf)
        jl(new, [{"timestamp": iso(n - 1280)}] + [tool("Edit", n - 5, description="edit")])
        os.utime(new, (n - 5, n - 5))
        jl(journal, [{"type": "started", "agentId": "new333", "label": "build"}], "a")
        cache.forget("agents_view")
        self.assertEqual(states(), [("des222", "done"), ("new333", "working"), ("old111", "stale")])

    def test_orbiter_holds_only_newest(self):
        agents.orbiters = lambda: [{"id": "T88"}]
        self.agent("ooo", "T88 older", [tool("Edit", self.now - 2000, description="e")], 2000)
        self.agent("nnn", "T88 newer", [tool("Edit", self.now - 1000, description="e")], 1000)
        self.assertEqual(self.states(), {"T88 older": "stale", "T88 newer": "working"})

    def test_recent_capped(self):
        for i in range(12):
            self.agent("r%02d" % i, "T8%02d" % i, [tool("SubagentHandback", self.now - 100 - i, message="ok")], 100 + i)
        subs = agents.collect()["subagents"]
        self.assertEqual(len(subs), agents.RECENT_N)
        self.assertEqual(subs[0]["label"], "T800")

    def test_persistent_states(self):
        os.makedirs(os.path.join(self.proj, "sess5678-y", "subagents"), exist_ok=True)
        notes = os.path.join(os.path.dirname(self.proj), "-srv-x-agents-notes")
        os.makedirs(notes)
        jl(os.path.join(notes, "s.jsonl"), [{}])
        os.utime(os.path.join(notes, "s.jsonl"), (self.now - 3600, self.now - 3600))
        jl(self.parent, [{}])
        os.utime(self.parent, (self.now - 3600, self.now - 3600))
        d = agents.collect()
        self.assertEqual({r["name"]: r["state"] for r in d["roster"]}, {"keeper": "running", "digest": "idle", "notes": "idle", "hello": "off"})
        self.assertEqual(d["orchestrator"]["state"], "idle")
        jl(os.path.join(notes, "s.jsonl"), [{}], "a")
        cache.forget("agents_persist")
        self.assertEqual({r["name"]: r["state"] for r in agents.collect()["roster"]}["notes"], "running")
        agents.tmux_sessions = lambda: set()
        cache.forget("agents_persist")
        self.assertEqual(agents.collect()["orchestrator"]["state"], "off")

    def test_orchestrator_follows_newest_session_without_subagents(self):
        os.makedirs(os.path.join(self.proj, "sess5678-y", "subagents"), exist_ok=True)
        jl(self.parent, [{}])
        os.utime(self.parent, (self.now - 3600, self.now - 3600))
        jl(os.path.join(self.proj, "newer999-z.jsonl"), [{}])
        d = agents.collect()
        self.assertEqual(d["orchestrator"], {"name": "DarkSaddler", "session": "newer999", "state": "running"})

    def test_parent_scan_concurrent_keeps_offset(self):
        n = self.now
        jl(self.parent, [note("par%d" % i, "completed", n - 100) for i in range(5)])
        size = os.path.getsize(self.parent)
        gate = threading.Barrier(2, timeout=1)

        class Gated(io.FileIO):
            def read(self, n=-1):
                out = super().read(n)
                try:
                    gate.wait()
                except threading.BrokenBarrierError:
                    pass
                return out
        agents.agent_ends.open = Gated
        try:
            ts = [threading.Thread(target=agents.parent, args=(self.parent,)) for _ in range(2)]
            [t.start() for t in ts]
            [t.join() for t in ts]
        finally:
            del agents.agent_ends.open
        self.assertEqual(agents._parent[self.parent][0], size)
        jl(self.parent, [note("late", "completed", n)], "a")
        self.assertEqual(agents.parent(self.parent)[0].get("late", (0, ""))[1], "done")

    def test_scan_chunks_keep_lines_across_boundaries(self):
        n = self.now
        rows = [note("ch%d" % i, "completed", n - 100) for i in range(40)]
        jl(self.parent, rows)
        whole = agents.agent_ends.scan(self.parent, agents.agent_ends.memo())
        chunk = agents.agent_ends.CHUNK
        agents.agent_ends.CHUNK = 97
        try:
            small = agents.agent_ends.scan(self.parent, agents.agent_ends.memo())
            with open(self.parent, "a") as f:
                f.write(json.dumps(note("tail", "completed", n))[:-5])
            part = agents.agent_ends.scan(self.parent, small)
            self.assertEqual(part[0], whole[0])
            self.assertNotIn("tail", part[1])
        finally:
            agents.agent_ends.CHUNK = chunk
        self.assertEqual(small, whole)
        self.assertEqual(len(whole[1]), 40)

    def test_scan_cold_50mb_peak_rss_under_100mb(self):
        import subprocess
        big = os.path.join(self.tmp.name, "big.jsonl")
        pad = json.dumps({"timestamp": "2026-10-15T00:00:00Z", "message": {"content": "x" * 2000}}) + "\n"
        with open(big, "w") as f:
            for i in range((50 << 20) // len(pad)):
                f.write(json.dumps(note("big%d" % i, "completed", self.now)) + "\n" if i % 5000 == 0 else pad)
        code = ("import resource, sys; sys.path.insert(0, %r); import agent_ends as a; m = a.scan(%r, a.memo()); "
                "print(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss, len(m[1]))") % (os.path.dirname(agents.agent_ends.__file__), big)
        rss, notes = map(int, subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True).stdout.split())
        self.assertGreater(notes, 0)
        self.assertLess(rss, 100 * 1024)


if __name__ == "__main__":
    unittest.main()
