#!/usr/bin/env python3
"""lib/owner_status.py in-process on a copied fixture tree with HOME pointed at it: buckets, malformed rows, empty tree."""
import json, os, shutil, sys, tempfile, time

HERE = os.path.dirname(os.path.realpath(__file__))
TREE = os.path.join(HERE, "fixtures", "owner-status", "tree")
REAL_WORK = os.path.expanduser("~/agent-work")
sys.path.insert(0, os.path.join(HERE, "..", "..", "lib"))
fail = 0


def check(name, cond, got=""):
    global fail
    print(f'{"owner_status: " + name:64}' + ("OK" if cond else f"FAIL — {got}"))
    fail |= not cond


def sandbox(tree=True):
    """A fresh HOME (the fixture tree or empty) with env pointing only inside it."""
    home = tempfile.mkdtemp()
    if tree:
        shutil.copytree(TREE, home, dirs_exist_ok=True)
    fake = os.path.join(home, "bin")
    os.makedirs(fake, exist_ok=True)
    with open(fake + "/systemctl", "w") as f:
        f.write('#!/bin/sh\ncase "$2" in list-units) echo \'[{"unit": "agent@T14-headless.service"}]\';; show) echo 0;; esac\n')
    os.chmod(fake + "/systemctl", 0o755)
    for k in ("AGENT_WORK", "OWNER_TODO_LEDGER", "OWNER_STATUS_STAMP"):
        os.environ.pop(k, None)
    os.environ.update(HOME=home, HARNESS_CONFIG=home + "/none.env", XDG_RUNTIME_DIR=home + "/run",
                      PATH=fake + ":" + BASE_PATH)
    return home


BASE_PATH = os.environ["PATH"]
NOW = time.time()
import owner_status as os_

home = sandbox()
work = home + "/agent-work"
claims = home + "/run/dark-eye/orbit-claims.json"
txt = open(claims).read().replace("@RUN@", home + "/run").replace('"@AT@"', str(NOW - 600))
open(claims, "w").write(txt)
for b in os.listdir(work + "/briefs"):
    os.utime(os.path.join(work, "briefs", b), (NOW - 3600,) * 2)
os.utime(work + "/briefs/T9-stale.md", (NOW - 3 * 86400,) * 2)

check("agent_work resolves inside the fixture HOME", os_.agent_work() == work, os_.agent_work())
d = os_.collect(since_date="2026-10-18", now=NOW)
labels = [(r["label"], r["min"]) for r in d["running"]]
check("running: orbit claim labelled from meta.json, 10 min", ("T13 running job", 10) in labels, labels)
check("running: broken meta.json row falls back to 'agent'", ("agent", 0) in labels, labels)
check("running: headless agent@ unit from systemctl", ("T14-headless (headless)", 0) in labels, labels)
check("running: longest first", d["running"][0]["min"] == 10, labels)
check("done: dated lines since 2026-10-18 only", [l[13:16] for l in d["done"]] == ["T10", "T11"], d["done"])
check("done: sub bullet and undated row skipped", d["history_lines"] == 3, d["history_lines"])
check("waiting: open items only, bad ledger lines skipped", [w["id"] for w in d["waiting"]] == ["1", "2"], d["waiting"])
check("queued: T12 only (not done, running, headless, stale, bad name)", d["queued"] == ["T12"], d["queued"])

out = os_.render(d)
check("render: four sections, at most 15 lines", out.count("\n") < 15 and "Running now: 3" in out and "Done since 2026-10-18: 2" in out
      and "Waiting on you: 2" in out and "Queued: 1  T12" in out, out)

os_.mark(d)
stamp = home + "/agents/state/owner-status.json"
check("mark: stamp under the fixture HOME with the line count", json.load(open(stamp))["lines"] == 3, open(stamp).read())
with open(work + "/history.md", "a") as f:
    f.write("- 2026-10-19 T12 queued one done\n")
d = os_.collect(now=NOW)
check("after mark: only the new line is done, T12 leaves the queue", len(d["done"]) == 1 and "T12" in d["done"][0]
      and d["queued"] == [], d)

open(claims, "w").write('{"x": [1, 2]}')
check("malformed claims row: no raise, only the headless unit", [r["label"] for r in os_.running(NOW)] == ["T14-headless (headless)"])
open(claims, "w").write("{not json")
check("unreadable claims file: no raise", len(os_.running(NOW)) == 1)
open(stamp, "w").write("{broken")
check("broken stamp: falls back to today's date", os_.done(["- 2026-01-01 T1 x"], None, os_._stamp(None))[1] == [])

home = sandbox(tree=False)
with open(home + "/bin/systemctl", "w") as f:
    f.write("#!/bin/sh\necho '[]'\n")
d = os_.collect(now=NOW)
check("empty tree: every bucket empty", d["running"] == d["done"] == d["waiting"] == d["queued"] == [] and d["history_lines"] == 0, d)
check("empty tree: render says 0 everywhere", "Running now: 0" in os_.render(d) and "Queued: 0" in os_.render(d), os_.render(d))
check("real ~/agent-work never resolved", os_.agent_work() != REAL_WORK, os_.agent_work())
raise SystemExit(fail)
