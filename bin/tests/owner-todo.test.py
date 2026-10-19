#!/usr/bin/env python3
"""owner-todo CLI: add/list/done/reopen on a fixture ledger (OWNER_TODO_LEDGER), never the real one."""
import json, os, subprocess, sys, tempfile

CLI = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "owner-todo")
REAL = os.path.expanduser("~/agents/state/owner-todo.jsonl")
fail = 0


def check(name, cond, got=""):
    global fail
    print(f'{"owner-todo: " + name:64}' + ("OK" if cond else f"FAIL — {got}"))
    fail |= not cond


def run(*a):
    r = subprocess.run([sys.executable, CLI, *a], capture_output=True, text=True, env=ENV)
    return r.returncode, r.stdout, r.stderr


tmp = tempfile.mkdtemp()
LEDGER = os.path.join(tmp, "state", "owner-todo.jsonl")
ENV = dict(os.environ, OWNER_TODO_LEDGER=LEDGER, AGENT_NAME="test")
before = os.path.getmtime(REAL) if os.path.exists(REAL) else None

rc, out, _ = run("list")
check("empty ledger lists nothing", rc == 0 and "nothing waits" in out, out)
rc, out, _ = run("add", "Run the ufw script", "--how", "sudo bash ~/drop/x.sh stale\nthen check", "--src", "T362")
check("add prints id 1", rc == 0 and out.strip() == "1", out)
rc, out, _ = run("add", "Grant the bot a role")
check("second add is id 2", out.strip() == "2", out)
rc, out, _ = run("add", "  ")
check("empty text refused", rc == 1, rc)
rc, out, _ = run("list")
check("list shows both, steps indented", "1. Run the ufw script  [T362]" in out and "     sudo bash ~/drop/x.sh stale" in out and "2. Grant" in out, out)
rc, out, _ = run("done", "1", "--note", "ran it")
check("done prints the undo", rc == 0 and "owner-todo reopen 1" in out, out)
rc, out, _ = run("list", "--json")
check("done item leaves the open list", [i["id"] for i in json.loads(out)] == ["2"], out)
rc, out, _ = run("list", "--all", "--json")
it = json.loads(out)[0]
check("--all keeps it, with note", it["done"] and it["note"] == "ran it" and it["how"].endswith("then check"), it)
rc, _, err = run("done", "1")
check("done twice refused", rc == 1 and "already done" in err, err)
rc, _, err = run("done", "9")
check("unknown id refused", rc == 1 and "no item 9" in err, err)
rc, out, _ = run("reopen", "1")
rc, out, _ = run("list", "--json")
check("reopen brings it back", [i["id"] for i in json.loads(out)] == ["1", "2"], out)
with open(LEDGER, "a") as f:
    f.write("not json\n")
rc, out, _ = run("list", "--json")
check("bad line skipped", rc == 0 and len(json.loads(out)) == 2, out)
ev = [json.loads(l) for l in open(LEDGER) if l.startswith("{")]
check("append-only: 4 events, by recorded", len(ev) == 4 and all(e["by"] == "test" for e in ev), ev)
sys.path.insert(0, os.path.join(os.path.dirname(CLI), "..", "lib"))
import owner_todo  # noqa: E402
os.environ["OWNER_TODO_LEDGER"] = LEDGER
GOOD = b'{"op": "add", "id": "1", "text": "Good row"}\n'
for name, data in {"int id": GOOD + b'{"op": "add", "id": 2, "text": "Int id"}\n',
                   "0xff byte": GOOD + b'{"op": "add", "id": "2", "text": "bad \xff"}\n',
                   "no final newline": GOOD + b'{"op": "add", "id": "2", "te'}.items():
    with open(LEDGER, "wb") as f:
        f.write(data)
    try:
        got, bad = owner_todo.read()
        check(name + ": good row listed, problem named", got[0]["text"] == "Good row" and bad and bad[0].startswith("line 2"), (got, bad))
    except Exception as e:
        check(name + ": read does not raise", False, repr(e))
    rc, out, _ = run("add", "After " + name)
    rc, out, _ = run("list", "--json")
    check(name + ": add after it lands", rc == 0 and json.loads(out)[-1]["text"] == "After " + name, out)
os.remove(LEDGER)
rc, out, _ = run("decide")
check("decide: none when empty", rc == 0 and "no decisions" in out, out)
for text, how in [("Run the ufw script", "sudo bash ~/drop/T362/x.sh stale"), ("Say go TSP-040: a hook", "Tell the orchestrator: go TSP-040"),
                  ("Decide on the reports", "save them\nOr say: drop them"), ("Review the diff", "cd ~/repo && git diff"),
                  ("Allow identity", "If intended, tell the orchestrator: allow it"), ("Rename or keep? " + "x" * 120, "reply 'rename' or 'keep'")]:
    run("add", text, "--how", how)
rc, out, _ = run("decide")
lines = out.splitlines()
check("decide: only go/drop items, numbered", [l.split(".")[0] for l in lines[:-1]] == ["2", "3", "5", "6"], out)
check("decide: one line each, long text cut", all(len(l) < 130 for l in lines) and "…" in lines[3], out)
check("decide: sample reply last", lines[-1].startswith("reply: 2 go, 3 drop, 5 go "), out)
after = os.path.getmtime(REAL) if os.path.exists(REAL) else None
check("real ledger untouched", before == after, (before, after))
sys.exit(1 if fail else 0)
