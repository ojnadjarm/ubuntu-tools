#!/usr/bin/env python3
"""orbit-hook on fixtures: workflow transcripts stay lit while written, stale ones go out, plain subagents unchanged.
Sandboxed: HOME, XDG dirs and the Eye bridge are all temporary; the selftest proves the real Eye is unreachable."""
import http.server, json, os, subprocess, sys, tempfile, threading, time

HOOK = os.path.expanduser("~/agents/bin/orbit-hook")
posts = []


class Bridge(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        posts.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *a):
        pass


root = tempfile.mkdtemp(prefix="orbit-test-")
srv = http.server.HTTPServer(("127.0.0.1", 0), Bridge)
threading.Thread(target=srv.serve_forever, daemon=True).start()
os.makedirs(f"{root}/cfg/dark-eye")
json.dump({"port": srv.server_port, "secret": "x"}, open(f"{root}/cfg/dark-eye/config.json", "w"))
os.makedirs(f"{root}/kb/skills")
open(f"{root}/kb/INDEX.md", "w").write("- orbit-hook-orbiters — agents as orbiters on the Eye: subagent start hook\n"
                                       "- night-swarm — research swarm lanes · skill /research-swarm\n")
ENV = dict(os.environ, HOME=root, XDG_CONFIG_HOME=f"{root}/cfg", XDG_RUNTIME_DIR=f"{root}/run",
           GUIDES_DIR=f"{root}/kb", SKILLS_DIR=f"{root}/kb/skills", AGENT_WORK=f"{root}/aw")
CLAIMS = f"{root}/run/dark-eye/orbit-claims.json"
PROJ = f"{root}/.claude/projects/-p"
TP = f"{PROJ}/sess.jsonl"
SUBS = f"{PROJ}/sess/subagents"
bad = 0


def check(name, ok):
    global bad
    print(("ok   " if ok else "FAIL ") + name)
    bad |= not ok


def hook(verb, hook=None, env=None):
    return subprocess.run([HOOK, verb], input=json.dumps(hook or {}), text=True, env=env or ENV, timeout=20,
                          capture_output=True).stdout


def touch(path, age=0):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "a").close()
    t = time.time() - age
    os.utime(path, (t, t))


def claims():
    return json.load(open(CLAIMS))


def posted(want, secs=5):
    end = time.time() + secs
    while time.time() < end:
        if want in posts:
            return True
        time.sleep(0.05)
    return False


def line(path, row, mode="a"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as f:
        f.write(json.dumps(row) + "\n")


def age_claim(oid, secs):
    c = claims()
    c[oid]["at"] = time.time() - secs
    json.dump(c, open(CLAIMS, "w"))


try:
    real_port = json.load(open(os.path.expanduser("~/.config/dark-eye/config.json"))).get("port", 8642)
except Exception:
    real_port = 8642
used = json.load(open(f"{ENV['XDG_CONFIG_HOME']}/dark-eye/config.json"))
check("selftest: the hook's config is the fixture bridge, not the live Eye",
      used["port"] == srv.server_port != real_port and used["secret"] == "x" and ENV["HOME"] != os.path.expanduser("~")
      and ENV["XDG_RUNTIME_DIR"].startswith(root))

wf_id, wf = "wf0001aaaaaaaaaa", f"{SUBS}/workflows/wf_x/agent-wf0001aaaaaaaaaa"
touch(wf + ".jsonl")
json.dump({"description": "T65 mockup"}, open(wf + ".meta.json", "w"))
hook("start", {"agent_id": wf_id, "transcript_path": TP, "agent_type": "worker"})
check("workflow start resolves the nested transcript", claims()["wf0001"]["tx"] == wf + ".jsonl")
check("workflow start labels from the nested meta", posted({"id": "wf0001", "state": "working", "label": "T65 mockup"}))
age_claim("wf0001", 3600)
hook("sweep")
check("workflow written now stays lit 60 min after start", "wf0001" in claims())
touch(wf + ".jsonl", 2000)
hook("sweep")
check("workflow stale 2000 s goes out", "wf0001" not in claims() and {"id": "wf0001", "state": "done", "label": ""} in posts)

pl_id, pl = "pl0001aaaaaaaaaa", f"{SUBS}/agent-pl0001aaaaaaaaaa.jsonl"
touch(pl)
hook("start", {"agent_id": pl_id, "transcript_path": TP, "agent_type": "worker"})
check("plain start resolves next to the parent", claims()["pl0001"]["tx"] == pl)
age_claim("pl0001", 3600)
hook("sweep")
check("plain written now stays lit", "pl0001" in claims())
hook("stop", {"agent_id": pl_id, "transcript_path": TP})
check("plain stop puts it out", "pl0001" not in claims() and {"id": "pl0001", "state": "done", "label": ""} in posts)

ms_id = "ms0001aaaaaaaaaa"
hook("start", {"agent_id": ms_id, "transcript_path": TP, "agent_type": "worker"})
age_claim("ms0001", 3600)
hook("sweep")
check("missing transcript is not idle from the start", "ms0001" in claims())
late = f"{SUBS}/workflows/wf_y/agent-{ms_id}.jsonl"
touch(late)
hook("sweep")
check("missing transcript is re-resolved on sweep", claims()["ms0001"]["tx"] == late)
os.remove(late)
age_claim("ms0001", 43300)
hook("sweep")
check("never-found transcript drops at the Eye's 12 h expiry", "ms0001" not in claims())


lt_id, lt = "lt0001aaaaaaaaaa", f"{SUBS}/workflows/wf_z/agent-lt0001aaaaaaaaaa"
touch(lt + ".jsonl")
t0 = time.monotonic()
hook("start", {"agent_id": lt_id, "transcript_path": TP, "agent_type": "worker"})
took = time.monotonic() - t0
check(f"late meta: hook returns in {took:.2f} s, under the old 2.0 s wait", took < 1.5)
check("late meta: lit at once with the fallback label", {"id": "lt0001", "state": "working", "label": "worker"} in posts)
json.dump({"description": "T72 backfill"}, open(lt + ".meta.json", "w"))
check("late meta: relabelled when the meta lands after the hook returns", posted({"id": "lt0001", "state": "working", "label": "T72 backfill"}))

sp_id, sp = "sp0001aaaaaaaaaa", f"{SUBS}/workflows/wf_z/agent-sp0001aaaaaaaaaa"
touch(sp + ".jsonl")
hook("start", {"agent_id": sp_id, "transcript_path": TP, "agent_type": "worker"})
hook("stop", {"agent_id": sp_id, "transcript_path": TP})
json.dump({"description": "T72 short"}, open(sp + ".meta.json", "w"))
check("late meta after stop does not re-light", not posted({"id": "sp0001", "state": "working", "label": "T72 short"}, 1.5))

nw_id = "nw0001aaaaaaaaaa"
t0 = time.monotonic()
hook("start", {"agent_id": nw_id, "transcript_path": TP, "agent_type": "worker"})
took = time.monotonic() - t0
check(f"workflow session: hook skips the in-hook meta wait ({took:.2f} s)", took < 0.35)
hook("stop", {"agent_id": nw_id, "transcript_path": TP})

TP2 = f"{PROJ}/sess2.jsonl"
pw_id = "pw0001aaaaaaaaaa"
line(TP2, {"type": "assistant", "message": {"content": [
    {"type": "tool_use", "id": "tp1", "name": "Agent", "input": {"subagent_type": "general-purpose", "description": "T391 plain label from the parent", "prompt": "x"}}]}})
t0 = time.monotonic()
hook("start", {"agent_id": pw_id, "transcript_path": TP2, "agent_type": "general-purpose"})
took = time.monotonic() - t0
check(f"plain label: lit at once from the parent's Agent call, no meta, no meta wait ({took:.2f} s)",
      {"id": "pw0001", "state": "working", "label": "T391 plain label from th"} in posts and took < 0.45)
check("plain label: no relabel posts the agent_type later",
      not posted({"id": "pw0001", "state": "working", "label": "general-purpose"}, 0.5))
hook("stop", {"agent_id": pw_id, "transcript_path": TP2})

ox_id = "ox0001aaaaaaaaaa"
other = f"{root}/.claude/projects/-q/sess/subagents/agent-{ox_id}.meta.json"
os.makedirs(os.path.dirname(other))
json.dump({"description": "other session"}, open(other, "w"))
hook("start", {"agent_id": ox_id, "transcript_path": TP2, "agent_type": "worker"})
check("label reads only its own session, not a projects-wide glob", not posted({"id": "ox0001", "state": "working", "label": "other session"}, 1))
hook("stop", {"agent_id": ox_id, "transcript_path": TP2})
os.makedirs(f"{PROJ}/sess2/subagents", exist_ok=True)
json.dump({"description": "end relabel"}, open(f"{PROJ}/sess2/subagents/agent-{ox_id}.meta.json", "w"))



def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))


def agent_tx(path, began, last):
    """A transcript whose first line is dated began and whose mtime is last (seconds ago)."""
    line(path, {"timestamp": iso(time.time() - began)}, "w")
    os.utime(path, (time.time() - last,) * 2)


def task_stop(tp, tid, ago=0):
    line(tp, {"timestamp": iso(time.time() - ago), "message": {"content": [{"type": "tool_use", "name": "TaskStop", "input": {"task_id": tid}}]}})


def launch(tp, tid, rid, ago):
    line(tp, {"timestamp": iso(time.time() - ago), "toolUseResult": {"taskId": tid, "taskType": "local_workflow", "workflowName": "t90-x", "runId": rid}})


def lit(oid):
    return oid in claims()


def out(oid):
    return not lit(oid) and {"id": oid, "state": "done", "label": ""} in posts


TP3 = f"{PROJ}/sess3.jsonl"
S3 = f"{PROJ}/sess3/subagents"
line(TP3, {"timestamp": iso(time.time() - 7200)}, "w")

ts_id = "ts0001aaaaaaaaaa"
agent_tx(f"{S3}/agent-{ts_id}.jsonl", 900, 30)
hook("start", {"agent_id": ts_id, "transcript_path": TP3, "agent_type": "worker"})
agent_tx(f"{S3}/agent-{ts_id}.jsonl", 900, 30)
hook("sweep")
check("plain agent without an end signal stays lit", lit("ts0001"))
task_stop(TP3, ts_id)
hook("sweep")
check("TaskStop in the parent transcript puts a plain agent out on the next sweep", out("ts0001"))

rv_id = "rv0001aaaaaaaaaa"
agent_tx(f"{S3}/agent-{rv_id}.jsonl", 900, 0)
hook("start", {"agent_id": rv_id, "transcript_path": TP3, "agent_type": "worker"})
task_stop(TP3, rv_id, 600)
hook("sweep")
check("an agent written 10 min after its TaskStop stays lit", lit("rv0001"))

RUN = f"{S3}/workflows/wf_run1"
launch(TP3, "wtask0001", "wf_run1", 1200)
b1, b2 = "bd0001aaaaaaaaaa", "bd0002aaaaaaaaaa"
for aid in (b1, b2):
    agent_tx(f"{RUN}/agent-{aid}.jsonl", 1000, 5)
    hook("start", {"agent_id": aid, "transcript_path": TP3, "agent_type": "worker"})
line(f"{RUN}/journal.jsonl", {"type": "started", "label": "build", "agentId": b1}, "w")
line(f"{RUN}/journal.jsonl", {"type": "started", "label": "build", "agentId": b2})
for aid in (b1, b2):
    agent_tx(f"{RUN}/agent-{aid}.jsonl", 1000, 5)
hook("sweep")
check("parallel same-label workflow agents, both writing, both stay lit", lit("bd0001") and lit("bd0002"))
task_stop(TP3, "wtask0001", 30)
hook("sweep")
check("TaskStop of the workflow run puts its agents out", out("bd0001") and out("bd0002"))

launch(TP3, "wtask0002", "wf_run1", 0)
b3 = "bd0003aaaaaaaaaa"
agent_tx(f"{RUN}/agent-{b3}.jsonl", 0, 0)
line(f"{RUN}/journal.jsonl", {"type": "started", "label": "build", "agentId": b3})
hook("start", {"agent_id": b3, "transcript_path": TP3, "agent_type": "worker"})
hook("sweep")
check("the resumed run's new same-label agent stays lit after the old run's TaskStop", lit("bd0003"))

RUN2 = f"{S3}/workflows/wf_run2"
r1, r2, r3 = "rs0001aaaaaaaaaa", "rs0002aaaaaaaaaa", "rs0003aaaaaaaaaa"
agent_tx(f"{RUN2}/agent-{r1}.jsonl", 1500, 900)
agent_tx(f"{RUN2}/agent-{r3}.jsonl", 1500, 5)
for aid in (r1, r3):
    hook("start", {"agent_id": aid, "transcript_path": TP3, "agent_type": "worker"})
agent_tx(f"{RUN2}/agent-{r1}.jsonl", 1500, 900)
agent_tx(f"{RUN2}/agent-{r3}.jsonl", 1500, 5)
line(f"{RUN2}/journal.jsonl", {"type": "started", "label": "build", "agentId": r1}, "w")
line(f"{RUN2}/journal.jsonl", {"type": "started", "label": "review", "agentId": r3})
hook("sweep")
check("a silent workflow agent with no later same-label start stays lit (under 30 min)", lit("rs0001"))
agent_tx(f"{RUN2}/agent-{r2}.jsonl", 60, 0)
line(f"{RUN2}/journal.jsonl", {"type": "started", "label": "build", "agentId": r2})
hook("start", {"agent_id": r2, "transcript_path": TP3, "agent_type": "worker"})
hook("sweep")
check("resume without TaskStop: a later same-label start puts the silent agent out", out("rs0001"))
check("resume without TaskStop: the new agent and another label stay lit", lit("rs0002") and lit("rs0003"))
line(f"{RUN2}/journal.jsonl", {"type": "result", "agentId": r3})
hook("sweep")
check("a journal result row puts a workflow agent out", out("rs0003"))

fs_id = "fs0001aaaaaaaaaa"
agent_tx(f"{S3}/agent-{fs_id}.jsonl", 900, 0)
hook("start", {"agent_id": fs_id, "transcript_path": TP3, "agent_type": "worker"})
AUDIT = os.path.expanduser("~/agents/adapters/claude/hooks/audit-log.py")
t0 = time.monotonic()
subprocess.run([AUDIT], input=json.dumps({"tool_name": "TaskStop", "tool_input": {"task_id": fs_id}, "transcript_path": TP3,
                                          "session_id": "s", "cwd": root}), text=True, env=dict(ENV, HARNESS_HOME=root), timeout=20)
hook_s = time.monotonic() - t0
gone = posted({"id": "fs0001", "state": "done", "label": ""})
lag = time.monotonic() - t0
check(f"TaskStop hook puts the orbiter out at once, before the transcript line lands (lag {lag:.2f} s, hook {hook_s:.2f} s)",
      gone and lag < 2 and "fs0001" not in claims())

TP4 = f"{PROJ}/sess4.jsonl"


def spawn(*calls):
    """One parent assistant row with Agent tool_use blocks (id, subagent_type, description)."""
    line(TP4, {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": i, "name": "Agent", "input": {"subagent_type": k, "description": d, "prompt": "x"}} for i, k, d in calls]}})


def ctx_of(out):
    try:
        return json.loads(out)["hookSpecificOutput"]
    except Exception:
        return {}


spawn(("tu1", "worker", "T379 orbiters at subagent start"))
ctx = ctx_of(hook("start", {"agent_id": "gd0001aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"}))
text = ctx.get("additionalContext", "")
check("guide: start prints SubagentStart additionalContext from the parent's Agent call, top match first",
      ctx.get("hookEventName") == "SubagentStart" and text.splitlines()[1:2] and text.splitlines()[1].startswith("guide 3/4 ")
      and "orbit-hook-orbiters.md" in text)
check(f"guide: at most 3 hits and ~300 tokens ({len(text) // 4} est.)", text.count("\n      ") <= 3 and len(text) // 4 <= 300)
check("guide: an Agent call already taken prints nothing for the next start",
      hook("start", {"agent_id": "gd0002aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"}) == "")
line(TP4, {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "tu1", "content": "done"}]}})
spawn(("tu2", "worker", "research swarm lanes"), ("tu3", "Explore", "T379 subagent start orbiters"))
ex = ctx_of(hook("start", {"agent_id": "px0001aaaaaaaaaa", "transcript_path": TP4, "agent_type": "Explore"})).get("additionalContext", "")
wk = ctx_of(hook("start", {"agent_id": "pw0002aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"})).get("additionalContext", "")
check("guide: parallel spawns each get their own call by subagent_type", "orbit-hook-orbiters" in ex and "night-swarm" in wk
      and "→ invoke /research-swarm" in wk)
spawn(("tu4", "worker", "zzz qqq"))
check("guide: no match prints nothing", hook("start", {"agent_id": "nh0001aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"}) == "")
check("guide: no Agent call (workflow agent) prints nothing",
      hook("start", {"agent_id": "nm0001aaaaaaaaaa", "transcript_path": TP, "agent_type": "worker"}) == "")
os.makedirs(f"{root}/dead/dark-eye")
json.dump({"port": 9, "secret": "x"}, open(f"{root}/dead/dark-eye/config.json", "w"))
spawn(("tu5", "worker", "T379 subagent start"))
out = hook("start", {"agent_id": "dn0001aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"}, dict(ENV, XDG_CONFIG_HOME=f"{root}/dead"))
check("guide: a dead Eye still hands the subagent its guides", "orbit-hook-orbiters.md" in out)
for a in ("gd0001", "gd0002", "px0001", "pw0002", "nh0001", "nm0001", "dn0001"):
    hook("stop", {"agent_id": a + "aaaaaaaaaa", "transcript_path": TP4})

os.makedirs(f"{root}/aw/decisions")
os.makedirs(f"{root}/agents/KB")
open(f"{root}/aw/decisions/ailearning.md", "w").write("# ledger\n" + "".join(
    f'- 2026-10-{i:02d} · Decision number {i} keeps the sheet as it is, padded to look like a real ledger row · "quote {i}"\n'
    for i in range(1, 31)))
open(f"{root}/aw/decisions/vass.md", "w").write('- 2026-10-06 · No git writes in his checkout · (owner)\n')
open(f"{root}/agents/KB/DECISIONS.md", "w").write('- 2026-09-07 · Never push · "never again"\n')
spawn(("tu6", "worker", "T396 ailearning sheet fix"))
dt = ctx_of(hook("start", {"agent_id": "dc0001aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"})).get("additionalContext", "")
dg = dt[dt.find("Owner decisions for ailearning"):]
check(f"decisions: a description naming a project gets its ledger, quotes cut, <= 300 tokens ({len(dg) // 4} est.)",
      "- 2026-10-01 · Decision number 1 keeps the sheet" in dg and '"quote' not in dg and 0 < len(dg) <= 1200)
check("decisions: a long ledger ends with a pointer to the rest", "more in " + f"{root}/aw/decisions/ailearning.md)" in dg)
spawn(("tu7", "worker", "vass fleet check"))
dv = ctx_of(hook("start", {"agent_id": "dc0002aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"})).get("additionalContext", "")
check("decisions: every named project is handed over", "No git writes in his checkout" in dv and "Never push" in dv
      and "ailearning" not in dv)
spawn(("tu8", "worker", "zzz qqq"))
check("decisions: no project and no guide prints nothing",
      hook("start", {"agent_id": "dc0003aaaaaaaaaa", "transcript_path": TP4, "agent_type": "worker"}) == "")
for a in ("dc0001", "dc0002", "dc0003"):
    hook("stop", {"agent_id": a + "aaaaaaaaaa", "transcript_path": TP4})

srv.shutdown()
sys.exit(bad)
