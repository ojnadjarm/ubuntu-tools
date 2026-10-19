#!/usr/bin/env python3
"""agents-status --owner on fixtures: history, briefs, orbit claims, owner-todo ledger, stamp, fake systemctl."""
import json, os, subprocess, tempfile, time

CLI = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "agents-status")
REAL_STAMP = os.path.expanduser("~/agents/state/owner-status.json")
fail = 0


def check(name, cond, got=""):
    global fail
    print(f'{"agents-status --owner: " + name:64}' + ("OK" if cond else f"FAIL — {got}"))
    fail |= not cond


def run(*a):
    r = subprocess.run([CLI, "--owner", *a], capture_output=True, text=True, env=ENV)
    return r.returncode, r.stdout


tmp = tempfile.mkdtemp()
work, rt, fake = (os.path.join(tmp, d) for d in ("work", "run", "bin"))
for d in (work + "/briefs", rt + "/dark-eye", rt + "/sub", fake):
    os.makedirs(d)
today = time.strftime("%Y-%m-%d")
with open(work + "/history.md", "w") as f:
    f.write("# history\n- 2020-01-01 T1 old thing\n  - a sub bullet\n- %s T10 shipped the widget\n- %s T11 fixed it\n" % (today, today))
for t in ("T10-widget", "T12-queued", "T13-running"):
    open("%s/briefs/%s.md" % (work, t), "w").write("x")
old = work + "/briefs/T9-stale.md"
open(old, "w").write("x")
os.utime(old, (time.time() - 3 * 86400,) * 2)
tx = rt + "/sub/agent-abc.jsonl"
open(tx, "w").write("")
json.dump({"agentType": "worker", "description": "T13 running job"}, open(rt + "/sub/agent-abc.meta.json", "w"))
json.dump({"abc123": {"tx": tx, "at": time.time() - 600}}, open(rt + "/dark-eye/orbit-claims.json", "w"))
ledger = tmp + "/todo.jsonl"
with open(ledger, "w") as f:
    for i in range(1, 5):
        f.write(json.dumps({"id": str(i), "op": "add", "text": "step %d" % i, "ts": "2026-10-18T22:00:00+02:00"}) + "\n")
    f.write(json.dumps({"id": "4", "op": "done", "ts": "2026-10-18T22:10:00+02:00"}) + "\n")
open(fake + "/systemctl", "w").write("#!/bin/sh\necho '[]'\n")
os.chmod(fake + "/systemctl", 0o755)
stamp = tmp + "/stamp.json"
ENV = dict(os.environ, AGENT_WORK=work, XDG_RUNTIME_DIR=rt, OWNER_TODO_LEDGER=ledger, OWNER_STATUS_STAMP=stamp,
           PATH=fake + ":" + os.environ["PATH"])
before = os.path.getmtime(REAL_STAMP) if os.path.exists(REAL_STAMP) else None

rc, out = run()
lines = out.splitlines()
check("exit 0, at most 15 lines", rc == 0 and 0 < len(lines) <= 15, out)
check("running: 1 labelled from meta.json with minutes", "Running now: 1" in out and "T13 running job · 10 min" in out, out)
check("done today: 2 dated lines, sub bullet ignored", "Done since %s: 2" % today in out and "T10 shipped" in out, out)
check("waiting on you: 3 open", "Waiting on you: 3" in out and "1. step 1" in out and "step 4" not in out, out)
check("queued: T12 only (not done, running or stale)", "Queued: 1  T12" in out, out)
check("stamp written with history line count", json.load(open(stamp))["lines"] == 3, open(stamp).read())

with open(work + "/history.md", "a") as f:
    f.write("- %s T12 queued one done\n" % today)
rc, out = run()
check("second ask: only the new line, T12 leaves the queue", "Done since" in out and ": 1\n" in out and "T12 queued one" in out
      and "Queued: 0" in out, out)

rc, out = run("--json")
d = json.loads(out)
check("--json has the four sections", all(k in d for k in ("running", "done", "waiting", "queued")), out)
mt = os.path.getmtime(stamp)
rc, out = run("--since", "2020-01-01")
check("--since date counts from that day, stamp untouched", "Done since 2020-01-01: 4" in out and os.path.getmtime(stamp) == mt, out)
check("real stamp untouched", (os.path.getmtime(REAL_STAMP) if os.path.exists(REAL_STAMP) else None) == before)
raise SystemExit(fail)
